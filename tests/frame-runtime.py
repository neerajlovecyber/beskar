# Isolated C3 Settings pin-navigation check: python3 tests/settings-runtime.py.
# Uses nested niri, stub owners and a throwaway HOME; never talks to live scene sockets.
from pathlib import Path
import tempfile,shutil,os,json,subprocess,re,time,signal,atexit
processes=[]
def cleanup():
    for proc in reversed(processes):
        if proc.poll() is None:
            proc.terminate()
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired: proc.kill();proc.wait(timeout=5)
atexit.register(cleanup)
source=Path(__file__).resolve().parent.parent/'shell'
root=Path(tempfile.mkdtemp(prefix='beskar-settings-'))
for name in ('common','settings.plm','settings.luau','settings_catalog.luau','settings_search.luau','settings_store.luau','style_options.luau','desktop.luau','settings_display.luau','settings_looks.luau','appearance_profiles.luau','settings_quiet.luau','settings_shortcuts.luau','shortcuts.luau','shortcuts_adapter.py','preferences.luau','spotlight_search.luau','actions.luau','panels_data.luau','exclusive.luau'):
    if (source/name).is_dir(): shutil.copytree(source/name,root/name)
    else: shutil.copy2(source/name,root/name)
(root/'panels.plm').write_text('scene Panels { text panel_mon = "winit"; event close; }')
(root/'topbar.plm').write_text('uses scene "settings.plm" as Settings\nscene Topbar { event close_menu; event open_panel ->; event request_dock_pins ->; event dock_move_pin ->; surface { size: full, full; level: bottom; anchor: top_left } box { from: 0, 0; size: screen.width, screen.height; color: #282b39 } }')
(root/'topbar.luau').write_text('''local pins={"one","two","three"}
local function publish()
 local rows={}
 for i,pin in ipairs(pins) do rows[i]={index=i-1,pin=pin,name=pin,mvl=i>1,mvr=i<#pins} end
 emit("Settings.set_dock_pins",rows)
end
on("request_dock_pins",publish)
on("dock_move_pin",function(p)
 local i=p.id+1;local j=i+p.direction
 if pins[i] and pins[j] then pins[i],pins[j]=pins[j],pins[i] end
 publish()
end)
''')
(root/'dialogs.plm').write_text('scene Dialogs { event set_kind ->; }')
(root/'notifications.plm').write_text('scene Notifications { fact dnd = false; fact quiet = false; text quiet_status = ""; text rules_status = ""; model quiet_apps max 32 { app: text; mode: number; rule: bool } event cycle_app_rule ->; event set_dnd ->; event set_banner_ms ->; event clear_past ->; }')
(root/'activities.plm').write_text('scene Activities { fact quiet_focus = false; fact quiet_presentation = false; fact quiet_game = false; event quiet_toggle ->; event timer_start ->; event timer_toggle ->; event timer_cancel ->; }')
(root/'system.plm').write_text('scene System { permissions { services: "audio", "brightness" } service audio as sound { volume: number; muted: bool } service brightness as display { level: number } }')
(root/'system.luau').write_text('-- Fixture: service declarations only.\n')
(root/'desktop.plm').write_text(''.join(f'import scene "{n}.plm" as {alias}\n' for n,alias in [('panels','Panels'),('topbar','Topbar'),('dialogs','Dialogs'),('notifications','Notifications'),('system','System'),('activities','Activities'),('settings','Settings')])+'scene Desktop { }\n')
(root/'nested.kdl').write_text('output "winit" { scale 1.0; }\nprefer-no-csd\nhotkey-overlay { skip-at-startup; }\n')
home=root/'home';(home/'.config/beskar').mkdir(parents=True)
(home/'.config/pleamar_shell.json').write_text(json.dumps({'dark_mode':False,'skin':1,'accent':2,'accent_auto':False,'hour12':False,'custom_future':'kept'}))
(home/'.config/beskar/prefs.json').write_text(json.dumps({'appearance':0,'apps':False,'weather':False,'custom_future':42}))
(home/'.config/beskar/palette.json').write_text(json.dumps({'style':3}))
(root/'fakebin').mkdir()
for name in ('gsettings','powerprofilesctl'):
    p=root/'fakebin'/name;p.write_text('#!/bin/sh\nexit 0\n');p.chmod(0o755)
env=os.environ.copy();env.pop('NIRI_SOCKET',None)
log=(root/'nested.log').open('w');niri=subprocess.Popen(['niri','-c',str(root/'nested.kdl')],env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
processes.append(niri)
for _ in range(200):
    content=(root/'nested.log').read_text();match=re.search(r'listening on Wayland socket: (\S+)',content)
    if match:break
    if niri.poll() is not None:raise RuntimeError(content)
    time.sleep(.1)
else:raise RuntimeError('no nested socket')
env.update(WAYLAND_DISPLAY=match[1],PLEAMAR_SOCKETS=str(root/'sockets'),XDG_DATA_HOME=str(root/'data'),HOME=str(home),PATH=str(root/'fakebin')+':'+env['PATH'],PLEAMAR_SWAPCHAIN='1',PLEAMAR_NO_LENS='1')
binary=str(source.parent/'bin/exp/pleamar')
def start():
    proc=subprocess.Popen([binary,'--no-hud','--scene',str(root/'desktop.plm')],env=env,stdout=(root/'desktop.log').open('a'),stderr=subprocess.STDOUT,start_new_session=True)
    processes.append(proc)
    return proc
scene=start();(root/'fixture.json').write_text(json.dumps({'root':str(root),'niri':niri.pid,'scene':scene.pid,'display':match[1]}))
def say(command):
    return subprocess.run([binary,'--say','settings',command],env=env,text=True,capture_output=True,check=True).stdout.strip()
def wait(name,value):
    for _ in range(200):
        try:
            if say('get '+name)==str(value):return
        except subprocess.CalledProcessError:pass
        time.sleep(.1)
    raise AssertionError((name,value,(root/'desktop.log').read_text()[-4500:]))
def key(*args):
    subprocess.run(['wtype',*args],env=env,check=True);time.sleep(.15)
wait('preferences_loaded','true')
say('emit show');time.sleep(.5)
say('emit set_tab 4');say('emit pin_open');wait('pin_edit','true');time.sleep(.3)
key('-k','Down');wait('pin_sel','1')
key('-k','Right');wait('pin_sel','2')
key('-k','Left');wait('pin_sel','1')
subprocess.run(['grim',str(root/'dock-order.png')],env=env,check=True)
key('-k','Escape');wait('pin_edit','false');assert say('get open')=='true'
# Options are bounded and go through the same safe preference store.
say('emit dock_size_pick 2');wait('dock_size_i','2')
say('emit dock_delay_pick 0');wait('dock_delay_i','0')
say('emit dock_size_pick 99');time.sleep(.2);assert say('get dock_size_i')=='2'
time.sleep(.4)
disk=json.loads((home/'.config/beskar/prefs.json').read_text());assert disk['dock_size']==2 and disk['dock_delay']==0
for event, name, value in [('bar_left_order_pick','bar_left_order',1),('bar_right_order_pick','bar_right_order',1),('module_output_pick','module_output_policy',2),('dock_output_pick','dock_output_policy',1),('dock_show_delay_pick','dock_show_delay',2)]:
    say('emit '+event+' '+str(value));wait(name,str(value))
say('text frame_output_edit HDMI-A-1');say('emit frame_output_save');time.sleep(.4)
assert say('get frame_output_name')=='HDMI-A-1'
say('text frame_output_edit bad/name');say('emit frame_output_save');time.sleep(.2)
assert say('get frame_output_name')=='HDMI-A-1'
disk=json.loads((home/'.config/beskar/prefs.json').read_text())
assert disk['frame_output_name']=='HDMI-A-1' and disk['module_output_policy']==2 and disk['dock_show_delay']==2
assert 'runtime error' not in (root/'desktop.log').read_text(),(root/'desktop.log').read_text()[-4000:]
print('C3 Settings native pin selection/move/Escape and bounded option persistence passed:',root)
