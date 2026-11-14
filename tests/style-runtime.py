# Native check of reduced motion on the pinned runtime: python3 tests/style-runtime.py
# Films throwaway fixtures (no screen, no compositor, a virtual clock) with a THROWAWAY XDG_RUNTIME_DIR, so it never touches a
# live scene's socket, and a temporary HOME. It proves, with the real shell/style_options.luau and the real wallpaper scene:
#   1. In a multi-scene composite (the way `desktop.plm` imports its scenes) the preference lives in one imported scene and the
#      ROOT scene's logic applies pleamar's `motion.reduced`: every spring of every imported scene settles at once (open and
#      close), a `wave` goes quiet, and turning it off animates again. A plugin of an imported scene cannot set the fact itself.
#   2. The real wallpaper scene reveals a new picture in a frame under reduced motion and ends in the same state as the full
#      reveal (new picture in wp_a_path, cover gone), and still takes 1.3 s of spring without it.
from pathlib import Path
import os, shutil, subprocess, sys, tempfile, time
repo = Path(__file__).resolve().parent.parent
shell = repo / 'shell'
binary = repo / 'bin/exp/pleamar'
tmp = Path(tempfile.mkdtemp(prefix='beskar-style-'))
runtime = tmp / 'run'
runtime.mkdir()
runtime.chmod(0o700)
env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), PLEAMAR_NO_PORTAL='1', HOME=str(tmp / 'home'), XDG_CONFIG_HOME=str(tmp / 'home/.config'))
passed = 0
def check(v, why):
    global passed
    if not v:
        print('FAIL:', why)
        shutil.rmtree(tmp, ignore_errors=True)
        sys.exit(1)
    passed += 1

def film(scene, seconds, names, mouse=None, extra=None):
    args = [str(binary), '--scene', str(scene), '--film', str(tmp / 'film'), '--seconds', str(seconds), '--record', names]
    if mouse: args += ['--mouse', mouse]
    shutil.rmtree(tmp / 'film', ignore_errors=True)
    out = subprocess.run(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=240).stdout
    cols = names.split(',')
    rows = []
    for line in out.splitlines():
        p = line.split('\t')
        if len(p) == len(cols) + 1:
            try: rows.append((float(p[0]), dict(zip(cols, p[1:]))))
            except ValueError: pass
    if not rows:
        print('no rows recorded; the runtime said:\n' + out[-1500:])
    return rows

def at(rows, ms, name):
    best = min(rows, key=lambda r: abs(r[0] - ms))
    return best[1][name]

# ── 1. multi-scene composite ─────────────────────────────────────────
d = tmp / 'ms'
d.mkdir()
shutil.copy2(shell / 'style_options.luau', d / 'style_options.luau')
(d / 'setter.plm').write_text('''scene Setter {
    surface { size: 100, 40; anchor: bottom_left }
    permissions { }
    fact reduce_motion = false
    event reduce_on ->
    event reduce_off ->
    box { from: 0, 0; size: 100, 40; color: #303030 }
}''')
(d / 'setter.luau').write_text('on("reduce_on", function() fact.reduce_motion = true end)\non("reduce_off", function() fact.reduce_motion = false end)\n')
for n in ('a', 'b'):
    (d / f'p{n}.plm').write_text(f'''scene P{n} {{
    surface {{ size: 200, 60; anchor: top_left }}
    permissions {{ }}
    fact open = false
    event open_it ->
    event shut_it ->
    prop seen = 0 ~calm
    prop ph = 100 ~calm
    follow ph = if(open, 400, 100)
    layer panel ~quick {{
        shown while open {{ seen: 1 ~calm }}
        gone {{ seen: 0 ~quick }}
    }}
    prop wv = 0
    wave wv = 1 at 3
    box {{ from: 0, 0; size: 200, 60; color: #202020; opacity: seen }}
}}''')
    (d / f'p{n}.luau').write_text('on("open_it", function() fact.open = true end)\non("shut_it", function() fact.open = false end)\n')
(d / 'desk.plm').write_text('import scene "setter.plm" as Setter\nimport scene "pa.plm" as Pa\nimport scene "pb.plm" as Pb\nscene Desk { }\n')
# the root scene's logic, exactly what shell/desktop.luau should hold
(d / 'desk.luau').write_text('''local Style = require("style_options")
local motion = Style.bind_motion({ fact = fact, on = on })
on("fact:Setter.reduce_motion", function(v) motion.set(v) end)
if fact["Setter.reduce_motion"] then motion.set(true) end
''')
names = 'Pa.seen,Pb.seen,Pa.ph,Pb.wv,motion.reduced'
full = film(d / 'desk.plm', 1.2, names, 'emit:Pa.open_it@100 emit:Pb.open_it@100 emit:Pa.shut_it@700')
check(float(at(full, 150, 'Pa.seen')) < 0.2 and float(at(full, 300, 'Pa.seen')) < 0.9, 'without reduction the reveal takes time')
check(float(at(full, 300, 'Pa.ph')) < 390 and float(at(full, 1100, 'Pb.wv')) != 0, 'without reduction the follow spring and the wave run')
check(float(at(full, 750, 'Pa.seen')) > 0.5, 'without reduction the close takes time')
red = film(d / 'desk.plm', 1.6, names, 'emit:Setter.reduce_on@20 emit:Pa.open_it@100 emit:Pb.open_it@100 emit:Pa.shut_it@700 emit:Setter.reduce_off@1000 emit:Pa.open_it@1100')
check(float(at(red, 50, 'motion.reduced')) == 1, 'the root logic sets motion.reduced from the imported scene\'s fact')
check(float(at(red, 160, 'Pa.seen')) == 1 and float(at(red, 160, 'Pb.seen')) == 1, 'both imported scenes\' open springs settle at once')
check(float(at(red, 160, 'Pa.ph')) == 400, 'a follow spring settles at once')
check(float(at(red, 400, 'Pb.wv')) == 0, 'a wave goes quiet')
check(float(at(red, 780, 'Pa.seen')) == 0 and float(at(red, 780, 'Pb.seen')) == 1, 'the close settles at once; the other panel is still open')
check(float(at(red, 1033, 'motion.reduced')) == 0, 'turning the preference off gives the system value back')
check(0 < float(at(red, 1183, 'Pa.seen')) < 0.9, 'and motion is back')
check(float(at(red, 1580, 'Pa.seen')) > 0.95, 'ending at the same final state')

# a plugin of an imported scene cannot write the fact (why the root scene applies it)
(d / 'setter.luau').write_text('on("reduce_on", function() local ok, e = pcall(function() fact["motion.reduced"] = 1 end); fact.reduce_motion = ok end)\n')
probe = film(d / 'desk.plm', 0.3, 'Setter.reduce_motion', 'emit:Setter.reduce_on@20')
check(at(probe, 250, 'Setter.reduce_motion') in ('0', '0.0000', 'false'), 'an imported scene\'s logic is refused motion.reduced (read the log: "has no fact called")')

# ── 2. the real wallpaper scene ──────────────────────────────────────
w = tmp / 'wp'
w.mkdir()
for n in ('wallpaper.luau', 'wallpaper_store.luau', 'style_options.luau'):
    shutil.copy2(shell / n, w / n.replace('wallpaper.luau', 'wpfix.luau'))
shutil.copy2(shell / 'wallpaper.plm', w / 'wpfix.plm')
home = tmp / 'home'
(home / '.config/beskar').mkdir(parents=True)
(home / 'Pictures').mkdir()
subprocess.run(['magick', '-size', '320x180', 'xc:red', str(home / 'Pictures/a.png')], check=True)
subprocess.run(['magick', '-size', '320x180', 'xc:blue', str(home / 'Pictures/b.png')], check=True)
b_path = home / 'Pictures/b.png'

def wallpaper_run(reduced):
    (home / '.config/beskar/wallpaper').write_bytes((home / 'Pictures/a.png').read_bytes())
    (home / '.config/beskar/prefs.json').write_text('{"reduce_motion": %s}' % ('true' if reduced else 'false'))
    names = 'rv,wp_go,wp_a_path,motion.reduced'
    cmd = [str(binary), '--scene', str(w / 'wpfix.plm'), '--film', str(tmp / 'wfilm'), '--seconds', '3000', '--record', names]
    shutil.rmtree(tmp / 'wfilm', ignore_errors=True)
    proc = subprocess.Popen(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    sock = runtime / 'pleamar/wpfix.sock'
    for _ in range(100):
        if sock.exists(): break
        time.sleep(0.1)
    time.sleep(2.5)
    subprocess.run([str(binary), '--say', 'wpfix', f'text wp_new {b_path}'], env=env, capture_output=True, timeout=20)
    time.sleep(7)
    proc.terminate()
    out = proc.communicate(timeout=30)[0]
    rows = []
    for line in out.splitlines():
        p = line.split('\t')
        if len(p) == 5:
            try: rows.append((float(p[0]), dict(zip(names.split(','), p[1:]))))
            except ValueError: pass
    return rows

def reveal(rows):
    go = next((t for t, r in rows if r['wp_go'] == '1.0000'), None)
    done = next((t for t, r in rows if str(b_path) == r['wp_a_path']), None)
    over = next((t for t, r in rows if go is not None and t > go and r['wp_go'] == '0.0000'), None)
    peak = next((t for t, r in rows if go is not None and t >= go and float(r['rv']) > 0.99), None)
    return go, peak, done, over, rows[-1][1] if rows else None

if shutil.which('magick'):
    fgo, fpeak, fdone, fover, fend = reveal(wallpaper_run(False))
    check(fgo is not None and fpeak is not None and fpeak - fgo > 800, 'full motion: the cover takes ~1.3 s of spring (%s)' % (None if fgo is None else fpeak - fgo))
    rgo, rpeak, rdone, rover, rend = reveal(wallpaper_run(True))
    check(rgo is not None and rpeak is not None and rpeak - rgo < 40, 'reduced: the cover is complete in a couple of frames (%s)' % (None if rgo is None else rpeak - rgo))
    check(rdone is not None and rdone - rgo < 400, 'reduced: the new picture is swapped in a short hold later')
    check(rend['wp_a_path'] == str(b_path) and rend['wp_go'] == '0.0000' and rend['rv'] == '0.0000', 'reduced: final state is the new picture, cover gone')
    check(fend['wp_a_path'] == rend['wp_a_path'] and fend['wp_go'] == rend['wp_go'], 'the final state equals the full-motion one')
    check(rend['motion.reduced'] == '1.0000' and fend['motion.reduced'] == '0.0000', 'the saved reduce_motion preference was read at start')
else:
    print('skipped the wallpaper scene: ImageMagick is missing')
shutil.rmtree(tmp, ignore_errors=True)
print('style-runtime: %d checks passed' % passed)
