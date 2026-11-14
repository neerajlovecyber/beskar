# Isolated C1 runtime check: python3 tests/settings-runtime.py.
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
(root/'topbar.plm').write_text('scene Topbar { event close_menu; event open_panel ->; event request_dock_pins ->; event dock_move_pin ->; surface { size: full, full; level: bottom; anchor: top_left } box { from: 0, 0; size: screen.width, screen.height; color: #282b39 } }')
(root/'dialogs.plm').write_text('scene Dialogs { event set_kind ->; }')
(root/'notifications.plm').write_text('scene Notifications { fact dnd = false; fact quiet = false; text quiet_status = ""; text rules_status = ""; model quiet_apps max 32 { app: text; mode: number; rule: bool } event cycle_app_rule ->; event set_dnd ->; event set_banner_ms ->; event clear_past ->; }')
(root/'activities.plm').write_text('scene Activities { fact quiet_focus = false; fact quiet_presentation = false; fact quiet_game = false; event quiet_toggle ->; event timer_start ->; event timer_toggle ->; event timer_cancel ->; }')
(root/'system.plm').write_text('scene System { permissions { services: "audio", "brightness" } service audio as sound { volume: number; muted: bool } service brightness as display { level: number } }')
(root/'system.luau').write_text('-- Fixture: service declarations only.\n')
(root/'desktop.plm').write_text(''.join(f'import scene "{n}.plm" as {alias}\n' for n,alias in [('panels','Panels'),('topbar','Topbar'),('dialogs','Dialogs'),('notifications','Notifications'),('system','System'),('activities','Activities'),('settings','Settings')])+'scene Desktop { }\n')
(root/'nested.kdl').write_text('output "winit" { scale 1.25; }\nprefer-no-csd\nhotkey-overlay { skip-at-startup; }\n')
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
wait('preferences_loaded','true');assert say('get preference_can_restore')=='true'
# Startup must not rewrite a user's legacy files.
assert 'version' not in json.loads((home/'.config/pleamar_shell.json').read_text())
say('emit show');time.sleep(.8)
key('glass');wait('settings_search','true');key('-k','Return');wait('setting_target','2');assert say('get skin')=='1'
subprocess.run(['grim',str(root/'search-glass.png')],env=env,check=True)
# Search reaches distant rows in other categories without changing their choices.
unchanged={p:p.read_bytes() for p in (home/'.config').rglob('*.json')}
for query,tab,target,label in (
    ('dock hide delay',4,22,'Dock hide delay'),
    ('banner duration',3,11,'Banner stays for'),
    ('quiet hours',3,7,'Quiet modes & app delivery'),
    ('show workspaces',4,17,'Show workspaces'),
):
    say('focus side_q');key(query);wait('settings_search','true')
    key('-k','KP_Enter');wait('setting_target',str(target));wait('tab',str(tab));time.sleep(.2)
    view=say('describe');(root/('search-'+str(target)+'.txt')).write_text(view)
    assert label in view,(query,view)
    subprocess.run(['grim',str(root/('search-'+str(target)+'.png'))],env=env,check=True)
    assert all(p.read_bytes()==body for p,body in unchanged.items()),'search must not save preferences'
say('focus side_q');key('glass');key('-k','Return');wait('tab','0');wait('setting_target','2')
say('emit reset_appearance_review');wait('reset_review','true');key('-k','Return');wait('reset_review','false');assert say('get skin')=='1','Cancel is default'
say('emit reset_appearance_review');wait('reset_review','true');time.sleep(.2);key('-k','Right');key('-k','Return');wait('reset_undo','true');wait('skin','0');wait('appearance','1')
for _ in range(30):
    try:
        disk=json.loads((home/'.config/pleamar_shell.json').read_text())
        if disk.get('version')==1 and disk.get('skin')==0:break
    except (ValueError,FileNotFoundError):pass
    time.sleep(.1)
else:raise AssertionError('reset not saved')
assert disk['custom_future']=='kept'
say('emit reset_appearance_undo');wait('skin','1');wait('appearance','0');wait('accent','2');wait('pal_style','3')
time.sleep(.5);subprocess.run(['grim',str(root/'undo-light.png')],env=env,check=True)
assert json.loads((home/'.config/beskar/prefs.json').read_text())['custom_future']==42
scene.terminate();scene.wait(timeout=5)
# A fresh process must restore the undo values.
scene=start();wait('preferences_loaded','true');wait('skin','1');wait('appearance','0');wait('pal_style','3')
scene.terminate();scene.wait(timeout=5)
(home/'.config/beskar/prefs.json').write_text('{damaged')
scene=start();wait('preferences_loaded','true');wait('preference_can_restore','false');say('emit toggle_weather');time.sleep(.4)
assert (home/'.config/beskar/prefs.json').read_text()=='{damaged','corrupt document must be preserved'
assert 'runtime error' not in (root/'desktop.log').read_text(),(root/'desktop.log').read_text()[-3000:]
scene.terminate();scene.wait(timeout=5);niri.terminate();niri.wait(timeout=5)
print('C1 nested keyboard, reset/cancel/undo, persistence/restart and corrupt-file checks passed:',root)
