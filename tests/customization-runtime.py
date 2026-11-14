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
shutil.copytree(source, root/'shell')
shutil.copytree(source.parent/'assets/icons',root/'assets/icons')
root=root/'shell'
# All app actions and dangerous owners are stubbed; the two panels and Settings use real logic.
(root/'panels.plm').write_text('''scene Panels {
text panel_mon = "winit"; fact open = false; fact cur = 0; fact open_screen = 0; fact fresh = true; fact panel_h = 316;
event close ->; event show ->; event height ->; event width ->; event keep ->;
}''')
(root/'panels.luau').write_text('''local heights={}
on("show",function(id) fact.cur=id;fact.panel_h=heights[id] or 316;fact.open=true end)
on("close",function()fact.open=false end)
on("height",function(p) if type(p)=="table" then local id=p.id or p[1];local h=p.h or p[2];heights[id]=h;if fact.cur==id then fact.panel_h=h end end end)
on("width",function()end);on("keep",function()end)
''')
(root/'topbar.plm').write_text('''uses scene "panels.plm" as Panels
uses scene "settings.plm" as Settings
scene Topbar { event close_menu; event open_panel ->; event request_dock_pins ->; event dock_move_pin ->;
let bp_w = if(Panels.cur == 5, 980, 800)
surface { size: full, full; level: bottom; anchor: top_left }
box { from: 0, 0; size: screen.width, screen.height; color: #282b39 }
box { from: screen.width / 2 - bp_w / 2, screen.height - Panels.panel_h; size: bp_w, Panels.panel_h; corner: 24; color: if(Settings.dark_mode, #252830, #f2f3f7); show: Panels.open }
}''')
(root/'topbar.luau').write_text('-- isolated backdrop only\n')
(root/'dialogs.plm').write_text('scene Dialogs { event set_kind ->; }')
(root/'dialogs.luau').write_text('-- no authentication or session actions\n')
(root/'notifications.plm').write_text('scene Notifications { fact dnd = false; fact quiet = false; text quiet_status = ""; text rules_status = ""; model quiet_apps max 32 { app: text; mode: number; rule: bool } event cycle_app_rule ->; event set_dnd ->; event set_banner_ms ->; event clear_past ->; }')
(root/'notifications.luau').write_text('-- no notification service\n')
(root/'system.plm').write_text('scene System { permissions { services: "audio", "brightness" } service audio as sound { volume: number; muted: bool } service brightness as display { level: number } }')
(root/'system.luau').write_text('-- Fixture: service declarations only.\n')
(root/'activities.plm').write_text('scene Activities { fact quiet_focus = false; fact quiet_presentation = false; fact quiet_game = false; event quiet_toggle ->; event timer_start ->; event timer_toggle ->; event timer_cancel ->; }')
(root/'activities.luau').write_text('-- isolated timer stub\n')
(root/'desktop.plm').write_text(''.join(f'import scene "{n}.plm" as {alias}\n' for n,alias in [('panels','Panels'),('topbar','Topbar'),('dialogs','Dialogs'),('notifications','Notifications'),('system','System'),('activities','Activities'),('settings','Settings'),('dockpanels','Dockpanels')])+'scene Desktop { }\n')
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
def say(command,owner='topbar'):
    return subprocess.run([binary,'--say',owner,command],env=env,text=True,capture_output=True,check=True).stdout.strip()
def wait(name,value):
    for _ in range(200):
        try:
            if say('get '+name)==str(value):return
        except subprocess.CalledProcessError:pass
        time.sleep(.1)
    raise AssertionError((name,value,(root/'desktop.log').read_text()[-4500:]))
def key(*args):
    subprocess.run(['wtype',*args],env=env,check=True);time.sleep(.15)
# Wait for real Settings startup, then pass a synthetic read-only Widgets snapshot to the bar.
for _ in range(200):
    try:
        if say('get preferences_loaded','settings')=='true':break
    except subprocess.CalledProcessError:pass
    time.sleep(.1)
else:raise AssertionError((root/'desktop.log').read_text()[-4000:])
layouts=[dict(id=i,name='Desktop '+str(i),cards=i%16,outputs=2) for i in range(1,25)]
snapshot=dict(v=1,rev=3,ready=True,state='ok',writable=False,max=24,count=24,current=4,base=4,layouts=[[r['id'],r['name'],r['cards'],r['outputs']] for r in layouts],status=dict(seq=1,ok=True,code='refreshed',msg=''))
say('text wb_layouts '+json.dumps(snapshot,separators=(',',':')))
say('emit show 10','panels');time.sleep(1)
say('emit wb_tab 1');wait('wb_page','1')
# Name input focus must not swallow selection/navigation.
key('-k','Down');wait('wb_selected','5')
key('-k','Next');wait('wb_selected','10')
key('Work');wait('wb_name','Work')
assert say('get wb_can_save')=='false'
subprocess.run(['grim',str(root/'desktops.png')],env=env,check=True)
# Card options use the existing surface and forward changes to the Widgets owner.
(root/'widgets.plm').write_text('scene Widgets { fact last_opt = 0; fact last_stack = 0; fact last_page = 0; fact last_unstack = 0; event w_opt ->; event w_opt_reset ->; event w_stack ->; event w_page_next ->; event w_page_prev ->; event w_unstack ->; event edit_done ->; event w_bar_open ->; }')
(root/'widgets.luau').write_text('on("w_opt",function(n) fact.last_opt=n end)\non("w_stack",function(n) fact.last_stack=n end)\non("w_page_next",function(n) fact.last_page=n end)\non("w_page_prev",function(n) fact.last_page=-n end)\non("w_unstack",function(n) fact.last_unstack=n end)')
widget_stub=subprocess.Popen([binary,'--no-hud','--scene',str(root/'widgets.plm')],env=env,stdout=(root/'widgets.log').open('w'),stderr=subprocess.STDOUT,start_new_session=True)
processes.append(widget_stub);time.sleep(.4)
card=dict(v=1,rev=1,editing=True,sel=3,kind=1,name='Clock',sz=0,nsz=3,out='winit',lock=False,options=[dict(id=1,key='lock',label='Lock position',value=1,n=2,labels=['Unlocked','Locked']),dict(id=3,key='seconds',label='Seconds',value=1,n=3,labels=['Automatic','Show','Hide'])])
say('text wb_card_options '+json.dumps(card,separators=(',',':')));wait('wb_page','2')
key('-k','Right');assert say('get last_opt','widgets')=='12'
key('-k','Down');key('-k','KP_Enter');assert say('get last_opt','widgets')=='32'
subprocess.run(['grim',str(root/'card-options.png')],env=env,check=True)
# The same Card page offers stacking and retains modifier-specific key routing.
card['stack']=dict(id=0,n=1,i=1,m=[],pick=[[4,3],[5,4]])
say('text wb_card_options '+json.dumps(card,separators=(',',':')));time.sleep(.2)
key('-M','ctrl','-k','Right','-m','ctrl');key('-M','ctrl','-k','KP_Enter','-m','ctrl')
assert say('get last_stack','widgets')=='5'
assert say('get last_opt','widgets')=='32','stack keys must not also change a card option'
card['stack']=dict(id=1,n=2,i=1,m=[[3,1],[5,4]],pick=[])
say('text wb_card_options '+json.dumps(card,separators=(',',':')));time.sleep(.2)
key('-k','Next');assert say('get last_page','widgets')=='3'
key('-k','Prior');assert say('get last_page','widgets')=='-3'
key('-M','ctrl','-k','u','-m','ctrl');assert say('get last_unstack','widgets')=='3'
subprocess.run(['grim',str(root/'card-stack.png')],env=env,check=True)
# Wallpaper transition shortcuts reach Settings and persist without choosing a picture.
say('emit show 5','panels');time.sleep(1)
key('-M','ctrl','-k','F2','-m','ctrl');time.sleep(.4)
assert say('get wallpaper_fx','settings')=='1'
assert json.loads((home/'.config/beskar/prefs.json').read_text())['wallpaper_fx']==1
subprocess.run(['grim',str(root/'wallpapers.png')],env=env,check=True)
assert 'runtime error' not in (root/'desktop.log').read_text(),(root/'desktop.log').read_text()[-5000:]
print('C2/C4 isolated native keys and read-only page checks passed:',root)
