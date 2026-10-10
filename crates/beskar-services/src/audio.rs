use anyhow::Result;
use beskar_core::events::ServiceEvent;
use beskar_core::models::AudioState;
use pulseaudio::protocol::{
    self, ChannelVolume, Command, SetDeviceMuteParams, SetDeviceVolumeParams, SinkInfo, Volume,
};
use std::ffi::CString;
use std::io::BufReader;
use std::os::unix::net::UnixStream;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{info, warn};

/// Connection to PulseAudio/PipeWire-pulse UNIX socket.
/// Directly adapted from pleamar (`references/pleamar/src/platform/pulse.rs`).
struct Pulse {
    sock: BufReader<UnixStream>,
    version: u16,
    seq: u32,
}

type R<T> = std::result::Result<T, String>;

impl Pulse {
    fn connect(name: &str) -> R<Pulse> {
        let path = pulseaudio::socket_path_from_env().ok_or("no sound server socket path")?;
        let mut sock = BufReader::new(UnixStream::connect(path).map_err(|e| e.to_string())?);
        let cookie = pulseaudio::cookie_path_from_env()
            .and_then(|p| std::fs::read(p).ok())
            .unwrap_or_default();
        let auth = protocol::AuthParams {
            version: protocol::MAX_VERSION,
            supports_shm: false,
            supports_memfd: false,
            cookie,
        };
        protocol::write_command_message(sock.get_mut(), 0, &Command::Auth(auth), protocol::MAX_VERSION)
            .map_err(|e| e.to_string())?;
        let (_, reply) = protocol::read_reply_message::<protocol::AuthReply>(&mut sock, protocol::MAX_VERSION)
            .map_err(|e| e.to_string())?;
        let version = protocol::MAX_VERSION.min(reply.version);
        let mut p = Pulse {
            sock,
            version,
            seq: 1,
        };
        let mut props = protocol::Props::new();
        props.set(protocol::Prop::ApplicationName, CString::new(name).unwrap_or_default());
        p.ask::<protocol::SetClientNameReply>(Command::SetClientName(props))?;
        Ok(p)
    }

    fn send(&mut self, c: &Command) -> R<()> {
        self.seq += 1;
        protocol::write_command_message(self.sock.get_mut(), self.seq, c, self.version)
            .map_err(|e| e.to_string())
    }

    fn ask<T: protocol::CommandReply>(&mut self, c: Command) -> R<T> {
        self.send(&c)?;
        protocol::read_reply_message::<T>(&mut self.sock, self.version)
            .map(|(_, t)| t)
            .map_err(|e| e.to_string())
    }

    fn ack(&mut self, c: Command) -> R<()> {
        self.send(&c)?;
        protocol::read_ack_message(&mut self.sock)
            .map(|_| ())
            .map_err(|e| e.to_string())
    }

    fn state(&mut self) -> R<(protocol::ServerInfo, Vec<SinkInfo>)> {
        let server = self.ask::<protocol::ServerInfo>(Command::GetServerInfo)?;
        let sinks = self.ask::<protocol::SinkInfoList>(Command::GetSinkInfoList)?;
        Ok((server, sinks))
    }
}

fn level(v: &ChannelVolume) -> f32 {
    let max = v.channels().iter().map(|c| c.as_u32()).max().unwrap_or(0);
    max as f32 / Volume::NORM.as_u32() as f32
}

pub struct AudioService;

impl Default for AudioService {
    fn default() -> Self {
        Self::new()
    }
}

impl AudioService {
    pub fn new() -> Self {
        Self
    }

    /// Read volume and mute state directly from PulseAudio UNIX socket.
    /// Falls back to wpctl if pulse socket is unavailable.
    pub fn read_state() -> AudioState {
        if let Ok(mut pulse) = Pulse::connect("beskar") {
            if let Ok((server, sinks)) = pulse.state() {
                let default_sink = server.default_sink_name.as_ref();
                if let Some(sink) = sinks.iter().find(|s| Some(&s.name) == default_sink).or(sinks.first()) {
                    let volume = level(&sink.cvolume);
                    let is_muted = sink.muted;
                    let name = sink.description.as_ref().unwrap_or(&sink.name).to_string_lossy().into_owned();
                    return AudioState {
                        volume,
                        is_muted,
                        default_sink_name: Some(name),
                    };
                }
            }
        }

        // Fallback to wpctl
        if let Ok(output) = std::process::Command::new("wpctl")
            .args(["get-volume", "@DEFAULT_AUDIO_SINK@"])
            .output()
        {
            if output.status.success() {
                let text = String::from_utf8_lossy(&output.stdout);
                let is_muted = text.contains("[MUTED]");
                let parts: Vec<&str> = text.split_whitespace().collect();
                if parts.len() >= 2 {
                    if let Ok(vol) = parts[1].parse::<f32>() {
                        return AudioState {
                            volume: vol,
                            is_muted,
                            default_sink_name: None,
                        };
                    }
                }
            }
        }

        AudioState {
            volume: 1.0,
            is_muted: false,
            default_sink_name: None,
        }
    }

    pub fn set_volume(delta_percent: i32) {
        if let Ok(mut pulse) = Pulse::connect("beskar cmd") {
            if let Ok((server, sinks)) = pulse.state() {
                if let Some(sink) = sinks.iter().find(|s| Some(&s.name) == server.default_sink_name.as_ref()).or(sinks.first()) {
                    let current = level(&sink.cvolume);
                    let target = (current + (delta_percent as f32 / 100.0)).clamp(0.0, 1.0);
                    let mut cv = ChannelVolume::empty();
                    let raw = Volume::from_u32_clamped((target * Volume::NORM.as_u32() as f32).round() as u32);
                    for _ in 0..sink.cvolume.channels().len().max(1) {
                        cv.push(raw);
                    }
                    let params = SetDeviceVolumeParams {
                        device_index: Some(sink.index),
                        device_name: None,
                        volume: cv,
                    };
                    let _ = pulse.ack(Command::SetSinkVolume(params));
                    return;
                }
            }
        }

        // Fallback to wpctl
        let arg = if delta_percent >= 0 {
            format!("{}%+", delta_percent)
        } else {
            format!("{}%-", -delta_percent)
        };
        let _ = std::process::Command::new("wpctl")
            .args(["set-volume", "@DEFAULT_AUDIO_SINK@", &arg])
            .spawn();
    }

    pub fn toggle_mute() {
        if let Ok(mut pulse) = Pulse::connect("beskar cmd") {
            if let Ok((server, sinks)) = pulse.state() {
                if let Some(sink) = sinks.iter().find(|s| Some(&s.name) == server.default_sink_name.as_ref()).or(sinks.first()) {
                    let params = SetDeviceMuteParams {
                        device_index: Some(sink.index),
                        device_name: None,
                        mute: !sink.muted,
                    };
                    let _ = pulse.ack(Command::SetSinkMute(params));
                    return;
                }
            }
        }

        let _ = std::process::Command::new("wpctl")
            .args(["set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
            .spawn();
    }

    /// Reactive event stream over PulseAudio socket. Zero polling latency!
    pub async fn start_listener(&self, tx: mpsc::Sender<ServiceEvent>) -> Result<()> {
        info!("Starting pure-Rust PulseAudio reactive event subscriber");
        let is_running = Arc::new(AtomicBool::new(true));

        std::thread::Builder::new()
            .name("beskar-pulse".into())
            .spawn(move || {
                let mut last_state = None;

                while is_running.load(Ordering::Relaxed) {
                    let mut run = || -> R<()> {
                        let mut asker = Pulse::connect("beskar audio")?;
                        let mut events = Pulse::connect("beskar audio events")?;

                        events.ack(Command::Subscribe(
                            protocol::SubscriptionMask::SINK | protocol::SubscriptionMask::SERVER,
                        ))?;

                        let mut notify = |asker: &mut Pulse| -> R<()> {
                            let (server, sinks) = asker.state()?;
                            if let Some(sink) = sinks
                                .iter()
                                .find(|s| Some(&s.name) == server.default_sink_name.as_ref())
                                .or(sinks.first())
                            {
                                let state = AudioState {
                                    volume: level(&sink.cvolume),
                                    is_muted: sink.muted,
                                    default_sink_name: Some(
                                        sink.description
                                            .as_ref()
                                            .unwrap_or(&sink.name)
                                            .to_string_lossy()
                                            .into_owned(),
                                    ),
                                };

                                if last_state.as_ref() != Some(&state) {
                                    last_state = Some(state.clone());
                                    let _ = tx.blocking_send(ServiceEvent::Audio(state));
                                }
                            }
                            Ok(())
                        };

                        // Initial state announcement
                        notify(&mut asker)?;

                        loop {
                            protocol::read_command_message(&mut events.sock, events.version)
                                .map_err(|e| e.to_string())?;

                            // Drain queued burst events (e.g. while dragging slider)
                            events.sock.get_ref().set_nonblocking(true).ok();
                            while protocol::read_command_message(&mut events.sock, events.version).is_ok() {}
                            events.sock.get_ref().set_nonblocking(false).ok();

                            notify(&mut asker)?;
                        }
                    };

                    if let Err(e) = run() {
                        warn!("PulseAudio socket listener disconnected ({e}), retrying in 2s...");
                    }
                    std::thread::sleep(std::time::Duration::from_secs(2));
                }
            })?;

        Ok(())
    }
}
