use tracing::info;
use zbus::blocking::{Connection, MessageIterator};
use zbus::MatchRule;

/// Listen for `org.freedesktop.login1.Session` `Lock` signal sent by systemd-logind.
pub fn listen_logind_lock(sender: tokio::sync::mpsc::UnboundedSender<()>) {
    std::thread::Builder::new()
        .name("logind-lock".into())
        .spawn(move || {
            let Ok(c) = Connection::system() else {
                info!("Could not connect to system D-Bus for logind Lock signals");
                return;
            };

            let rule = match MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .interface("org.freedesktop.login1.Session")
                .and_then(|b| b.member("Lock"))
            {
                Ok(b) => b.build(),
                Err(err) => {
                    info!("Could not construct logind MatchRule: {err}");
                    return;
                }
            };

            let Ok(messages) = MessageIterator::for_match_rule(rule, &c, Some(16)) else {
                info!("Could not create logind MessageIterator");
                return;
            };

            info!("Systemd logind Session Lock signal subscriber active");
            for _ in messages {
                info!("Received systemd logind Lock signal -> triggering lock screen");
                if sender.send(()).is_err() {
                    break;
                }
            }
        })
        .ok();
}
