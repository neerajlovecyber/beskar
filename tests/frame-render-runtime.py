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
shutil.copy2(source/'topbar.plm',root/'topbar.plm')
(root/'topbar.plm').write_text((root/'topbar.plm').read_text().replace('    event card_click ->','    event fixture ->\n    event card_click ->'))
(root/'topbar.luau').write_text('''local function fill(n)
model.mon={{active=1,busy=0,nws=12,modules=n~=1,dock=n~=2}}
local ws,apps,icons,dock={},{},{},{}
for i=1,12 do ws[i]={out=0,idx=i,active=i==12,wins=1} end
for i=1,8 do apps[i]={out=0,icon="",name="App "..i,wid=i,focused=i==8,rank=i};icons[i]={icon=""} end
for i=1,10 do dock[i]={icon="",name="App "..i,running=true,pinned=true,canpin=false,mvl=i>1,mvr=i<10,sep=false,preview_thumb="",preview_title="",preview_has=false} end
model.ws_list=ws;model.cur_apps=apps;model.icons=icons;model.dock_items=dock
text.clock_text="12:34 PM"
end
on("fixture",fill);fill(0)
''')
(root/'dialogs.plm').write_text('scene Dialogs { event set_kind ->; }')
(root/'dialogs.luau').write_text('-- no authentication or session actions\n')
(root/'notifications.plm').write_text('scene Notifications { fact dnd = false; fact notif_count = 9; fact quiet = true; text quiet_status = ""; text rules_status = ""; model quiet_apps max 32 { app: text; mode: number; rule: bool } event cycle_app_rule ->; event set_dnd ->; event set_banner_ms ->; event clear_past ->; }')
(root/'notifications.luau').write_text('-- no notification service\n')
shutil.copy2(source/'system.plm',root/'system.plm')
(root/'system.luau').write_text('-- Fixture: service declarations only.\n')
(root/'activities.plm').write_text('scene Activities { fact timer_state = 0; text timer_text = ""; fact quiet_focus = false; fact quiet_presentation = false; fact quiet_game = false; event quiet_toggle ->; event timer_start ->; event timer_toggle ->; event timer_cancel ->; }')
(root/'activities.luau').write_text('-- isolated timer stub\n')
(root/'weather.plm').write_text('scene Weather { text icon = "󰖕"; text bar_temp = "20°C"; }')
(root/'weather.luau').write_text('-- isolated')
(root/'infopanels.plm').write_text('scene Infopanels { fact upd_n = 50; }')
(root/'infopanels.luau').write_text('-- isolated')
(root/'controlcenter.plm').write_text('scene Controlcenter { fact bt_connected = true; }')
(root/'controlcenter.luau').write_text('-- isolated')
(root/'desktop.plm').write_text(''.join(f'import scene "{n}.plm" as {alias}\n' for n,alias in [('system','System'),('panels','Panels'),('topbar','Topbar'),('dialogs','Dialogs'),('notifications','Notifications'),('activities','Activities'),('weather','Weather'),('infopanels','Infopanels'),('controlcenter','Controlcenter'),('settings','Settings'),('dockpanels','Dockpanels')])+'scene Desktop { }\n')
# Freeze a minimal Settings boundary for frame rendering so unrelated Settings UI
# edits cannot change this fixture. Real Settings persistence has a separate fixture.
theme=(root/'common/theme_facts.plm').read_text()
owned=set(re.findall(r'fact\s+(\w+)',theme))
source_settings=(source/'settings.plm').read_text()
needed=set(re.findall(r'Settings\.(\w+)',(root/'topbar.plm').read_text()+(root/'common/dock_panels.plm').read_text()+(root/'common/theme_owner.plm').read_text()))
declarations=[]
for line in source_settings.splitlines():
    m=re.match(r'\s*(fact|text)\s+(\w+)\s*=\s*(.*)',line)
    if m and m[2] in needed and m[2] not in owned:
        declarations.append(m[1]+' '+m[2]+' = '+m[3].split('//')[0].strip())
(root/'settings.plm').write_text('scene Settings { include "common/theme_facts.plm"\n'+'\n'.join(declarations)+'\n'+('\n'.join('event '+name+' ->' for name in needed if re.search(r'event\s+'+re.escape(name)+r'\b',source_settings)))+'\nfact preferences_loaded = true\nevent bar_left_order_pick ->\nevent bar_right_order_pick ->\n}')
# This fixture exercises the real frame renderer against explicit owner snapshots;
# Settings persistence and keyboard behavior are covered by frame-runtime.py.
(root/'settings.luau').write_text('''fact.preferences_loaded=true
on("bar_left_order_pick",function(n) fact.bar_left_order=n end)
on("bar_right_order_pick",function(n) fact.bar_right_order=n end)
''')
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

for _ in range(150):
    try:
        if say('get preferences_loaded','settings')=='true':break
    except subprocess.CalledProcessError:pass
    time.sleep(.1)
else:raise AssertionError((root/'desktop.log').read_text()[-4000:])
time.sleep(.8)
def describe():return say('describe','topbar')
def zones(body,needle):
    out=[]
    for line in body.splitlines():
        if 'button ' in line and needle in line:
            m=re.search(r'at ([\d.-]+),([\d.-]+) ([\d.]+)×([\d.]+)',line)
            if m:out.append(tuple(float(v) for v in m.groups()))
    return out
body=describe()
assert zones(body,'logo_hit') and zones(body,'SwitchesIcon') and zones(body,'BellIcon'),body
tray=zones(body,'tray_hit');assert 0<len(tray)<8,body
for x,y,w,h in tray:assert 0<=x and x+w<=944 and y<50,(x,y,w,h)
assert len(zones(body,'WsDot'))<12 and len(zones(body,'CurApp'))<8,body
# The actual renderer wheel rule pages overflow icons without changing the tray model.
wheel_zone=re.search(r'\s+(\S*tray_wheel\S*)\s',body)
assert wheel_zone,body
original_tray=re.findall(r'button\s+(\S*tray_hit\S*)',body)
wheel_name=wheel_zone[1].removeprefix('Topbar.')
say('wheel '+wheel_name+' -1','topbar');time.sleep(.2)
scrolled_tray=re.findall(r'button\s+(\S*tray_hit\S*)',describe())
assert scrolled_tray and scrolled_tray!=original_tray,(body,describe())
say('wheel '+wheel_name+' 100','topbar');time.sleep(.2)
assert re.findall(r'button\s+(\S*tray_hit\S*)',describe())==original_tray
before_ws=zones(body,'WsDot');before_apps=zones(body,'CurApp')
say('emit bar_left_order_pick 1','settings');say('emit bar_right_order_pick 1','settings');time.sleep(.8)
body=describe();after_ws=zones(body,'WsDot');after_apps=zones(body,'CurApp')
assert after_apps[0][0]<after_ws[0][0] and before_ws[0][0]<before_apps[0][0],(body,before_ws,before_apps)
subprocess.run(['grim',str(root/'frame-crowded.png')],env=env,check=True)
say('emit fixture 1','topbar');time.sleep(.5);body=describe()
assert not zones(body,'WsDot') and not zones(body,'CurApp') and not zones(body,'tray_hit'),body
assert zones(body,'logo_hit') and zones(body,'SwitchesIcon'),body
say('emit fixture 2','topbar');time.sleep(1);body=describe();assert not zones(body,'DockItem'),body
# An open dock panel still forces the dock's glass up on this output.
say('fact bp_on true','topbar');say('fact bp_screen 0','topbar');time.sleep(.8)
subprocess.run(['grim',str(root/'frame-policy-panel.png')],env=env,check=True)
assert 'runtime error' not in (root/'desktop.log').read_text(),(root/'desktop.log').read_text()[-4000:]
print('Frame native crowded-output caps, single-copy module reordering, policy and core routes passed:',root)
