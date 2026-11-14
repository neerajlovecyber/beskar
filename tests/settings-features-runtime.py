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
(root/'nested.kdl').write_text('output "winit" { scale 1.0; }\nprefer-no-csd\nhotkey-overlay { skip-at-startup; }\n')
home=root/'home';(home/'.config/beskar').mkdir(parents=True)
(home/'.config/pleamar_shell.json').write_text(json.dumps({'dark_mode':False,'skin':1,'accent':2,'accent_auto':False,'hour12':False,'custom_future':'kept'}))
(home/'.config/beskar/prefs.json').write_text(json.dumps({'appearance':0,'apps':False,'weather':False,'custom_future':42}))
(home/'.config/beskar/palette.json').write_text(json.dumps({'style':3}))
(root/'bridge/shell').mkdir(parents=True)
shutil.copy2(source/'shortcuts_adapter.py',root/'bridge/shell/shortcuts_adapter.py')
(home/'.config/beskar/shell-dir').write_text(str(root/'bridge'))
(home/'.config/niri/sub').mkdir(parents=True)
(home/'.config/niri/config.kdl').write_text('include "sub/keys.kdl"\n')
(home/'.config/niri/sub/keys.kdl').write_text('binds {\n Mod+J { focus-window-down; }\n}\n')
(root/'notifications.plm').write_text((root/'notifications.plm').read_text().replace('event cycle_app_rule','fact last_rule = 0; event cycle_app_rule'))
(root/'notifications.luau').write_text('''local rows={{app="Example Chat",mode=0,rule=false}}
model.quiet_apps=rows
on("cycle_app_rule",function(app) if app==rows[1].app then rows[1].mode=(rows[1].mode+1)%3;rows[1].rule=rows[1].mode>0;fact.last_rule=rows[1].mode;model.quiet_apps=rows end end)
''')
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
say('emit show');time.sleep(.8)
# These controls use the real Settings store and the real process-root motion bridge.
say('text custom_accent_edit not-a-colour');say('emit custom_accent_apply');time.sleep(.2)
assert say('get custom_accent')=='-1'
say('focus side_q');key('custom accent');key('-k','Return');wait('setting_target','32')
say('text custom_accent_edit ');say('focus custom_accent_edit');key('#fff');key('-k','Return');wait('custom_accent','16777215')
assert say('get accent_auto')=='false' and float(say('get acc_cr'))<.8,'light mode adjusts white away from its surfaces'
say('emit set_mode 1');time.sleep(.3);assert float(say('get acc_cr'))==1 and say('get acc_fg_dark')=='true'
say('emit choose_accent 2');say('emit set_mode 0');wait('custom_accent','-1')
say('emit style_text_pick 2');say('emit style_glass_pick 0');say('emit toggle_reduce_motion');time.sleep(.3)
assert say('get style_text')=='2' and say('get style_glass')=='0' and say('get reduce_motion')=='true'
motion=subprocess.run([binary,'--say','desktop','get motion.reduced'],env=env,text=True,capture_output=True,check=True).stdout.strip()
assert float(motion)==1,motion
say('emit style_text_pick 99');time.sleep(.2);assert say('get style_text')=='2'
say('emit look_open');wait('look_open','true');time.sleep(.3)
key('Evening');key('-k','Return');time.sleep(.6)
store=home/'.config/beskar/appearance-looks.json'
for _ in range(100):
    if store.exists():break
    time.sleep(.1)
assert store.exists(),say('get look_status')
assert say('get look_selected')!='0'
first=json.loads(store.read_text());assert 'Evening' in store.read_text()
saved=first['looks'][0]['values']
assert saved['appearance.text']==2 and saved['appearance.glass-strength']==0 and saved['appearance.motion'] is True
subprocess.run(['grim',str(root/'looks.png')],env=env,check=True)
say('emit choose_skin 2');time.sleep(.4)
say('emit look_load');time.sleep(.5);assert say('get skin')=='1'
say('emit reset_appearance_undo');time.sleep(.4);assert say('get skin')=='2'
# Review is pure; explicit Apply changes only the appearance section.
body=json.dumps({'kind':'beskar.appearance','version':1,'values':{'appearance.skin':0}},separators=(',',':'))
say('text look_document '+body);say('emit look_preview');wait('look_preview','true')
assert say('get skin')=='2'
assert 'Classic Solid' in say('get look_changes') and 'Liquid Glass' in say('get look_changes')
say('emit look_apply');time.sleep(.5);assert say('get skin')=='0'
say('emit reset_appearance_undo');time.sleep(.4);assert say('get skin')=='2'
say('text look_document '+json.dumps({'kind':'beskar.appearance','version':1,'values':{'command':'evil'}}));say('emit look_preview');time.sleep(.2)
assert say('get look_preview')=='false' and say('get skin')=='2'
# Keyboard opens and closes the subpage without closing Settings.
key('-k','Escape');wait('look_open','false');assert say('get open')=='true'
say('emit set_tab 3');say('emit quiet_open');wait('quiet_edit','true')
key('-M','ctrl','-k','Right','-m','ctrl')
assert subprocess.run([binary,'--say','notifications','get last_rule'],env=env,text=True,capture_output=True,check=True).stdout.strip()=='1'
say('text quiet_from 23:45');say('text quiet_to 06:15');say('emit quiet_hours_save');say('emit quiet_toggle');time.sleep(.4)
prefs=json.loads((home/'.config/beskar/prefs.json').read_text())
assert prefs['quiet_start']==1425 and prefs['quiet_end']==375 and prefs['quiet_enabled'] is True
subprocess.run(['grim',str(root/'quiet.png')],env=env,check=True)
say('text quiet_from 24:00');say('emit quiet_hours_save');time.sleep(.2);assert say('get quiet_start')=='1425'
key('-k','Escape');wait('quiet_edit','false');assert say('get open')=='true'
# Include discovery sees the nested binding; inline/user-owned configuration remains read-only.
say('emit set_tab 5')
for _ in range(100):
    if say('get bind_count')=='1 shortcuts':break
    time.sleep(.1)
assert say('get bind_count')=='1 shortcuts',say('get shortcut_status')
say('text bind_q keys.kdl');time.sleep(.3);assert say('get bind_count')=='1 shortcuts'
say('text bind_q no-such-file');time.sleep(.3);assert say('get bind_count')=='0 shortcuts'
say('text bind_q ');say('emit shortcut_open');wait('shortcut_open','true');time.sleep(.5)
assert say('get shortcut_editable')=='false'
assert 'no reachable Beskar include' in say('get shortcut_status')
key('-k','Escape');wait('shortcut_open','false');assert say('get open')=='true'
# A reachable Beskar include enables only the owned writer; validation uses real niri,
# while reload is a harmless marker in this temporary tree.
(home/'.config/niri/beskar.kdl').write_text('// Beskar-owned include anchor\n')
(home/'.config/niri/config.kdl').write_text('include "sub/keys.kdl"\ninclude "beskar.kdl"\n')
real_niri=shutil.which('niri')
fake=root/'fakebin/niri'
fake.write_text('#!'+shutil.which('python3')+'\nimport subprocess,sys\nfrom pathlib import Path\n'+
    'args=sys.argv[1:]\nif args and args[0]=="validate":sys.exit(subprocess.call(['+repr(real_niri)+']+args))\n'+
    'if args==["msg","action","load-config-file"]:Path('+repr(str(root/'reloaded'))+').write_text("ok");sys.exit(0)\n'+
    'print("{}")\n')
fake.chmod(0o755)
say('emit shortcut_open');wait('shortcut_editable','true')
key('Mod+Shift+K');key('-k','Return')
owned=home/'.config/niri/beskar-shortcuts.kdl'
for _ in range(150):
    if (root/'reloaded').exists():break
    time.sleep(.1)
assert owned.exists(),say('get shortcut_status')
assert 'Mod+Shift+K' in owned.read_text() and (root/'reloaded').exists(),say('get shortcut_status')
assert (home/'.config/niri/sub/keys.kdl').read_text()=='binds {\n Mod+J { focus-window-down; }\n}\n'
# Conflicts stop before the first write and show the source; a second explicit submit overrides.
wait('shortcut_status','Shortcut saved and niri reloaded');wait('shortcut_busy','false')
old_owned=owned.read_text();say('text shortcut_key Mod+J');key('-k','Return')
wait('shortcut_conflict','true')
assert owned.read_text()==old_owned and 'keys.kdl:2' in say('get shortcut_status')
(root/'reloaded').unlink();key('-k','Return')
for _ in range(150):
    if (root/'reloaded').exists():break
    time.sleep(.1)
assert (root/'reloaded').exists() and 'Mod+J' in owned.read_text(),say('get shortcut_status')
subprocess.run(['grim',str(root/'shortcuts.png')],env=env,check=True)
assert 'runtime error' not in (root/'desktop.log').read_text(),(root/'desktop.log').read_text()[-5000:]
subprocess.run(['grim',str(root/'features.png')],env=env,check=True)
print('Native saved looks, import/undo, quiet hours/app rules, included shortcut discovery and owned conflict/save passed:',root)
