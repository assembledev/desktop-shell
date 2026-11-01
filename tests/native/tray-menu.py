"""Run in Wayland: nix develop --command python3 tests/native/tray-menu.py.

Uses Qt's native tray client and the real SystemTray singleton on a private bus.
Pass --pointer to also check stationary compositor clicks with Hyprland and
wlrctl. No personal application menus are opened or activated.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--pointer", action="store_true", help="also move the cursor and test stationary clicks (Hyprland and wlrctl required)")
parser.add_argument("root", nargs="?", type=Path, help=argparse.SUPPRESS)
args = parser.parse_args()
pointer = shutil.which("wlrctl") if args.pointer else None
if args.pointer and (not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") or not shutil.which("hyprctl") or not pointer):
    parser.error("--pointer requires a Hyprland session, hyprctl and wlrctl")
source = Path(__file__).resolve().parents[2]
if args.root is None:
    if not os.environ.get("WAYLAND_DISPLAY"):
        sys.exit("tray regression requires a Wayland session")
    with tempfile.TemporaryDirectory(prefix="tray-menu-test-") as temporary:
        root = Path(temporary)
        shutil.copytree(source / "src/modules", root / "modules")
        shutil.copyfile(source / "tests/native/tray-menu.qml", root / "shell.qml")
        headers = subprocess.check_output(["qmake", "-query", "QT_INSTALL_HEADERS"], text=True).strip()
        libraries = subprocess.check_output(["qmake", "-query", "QT_INSTALL_LIBS"], text=True).strip()
        subprocess.run(["c++", "-std=c++20", "-fPIC", str(source / "tests/native/tray-client.cpp"),
                        "-I" + headers, *["-I" + headers + "/Qt" + name for name in ["Widgets", "Gui", "Core"]],
                        "-L" + libraries, "-Wl,-rpath," + libraries, "-lQt6Widgets", "-lQt6Gui", "-lQt6Core",
                        "-o", str(root / "client")], check=True)
        config = root / "dbus.conf"
        config.write_text('''<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:tmpdir=/tmp</listen>
<policy context="default"><allow own="*"/><allow send_destination="*"/><allow receive_sender="*"/></policy>
</busconfig>''')
        sys.exit(subprocess.call(["dbus-run-session", "--config-file=" + str(config), "--",
                                  sys.executable, __file__, str(root), *(["--pointer"] if args.pointer else [])]))

root = args.root
qs = shutil.which("quickshell")
env=os.environ.copy();env['QT_QPA_PLATFORM']='wayland';env['QT_QPA_PLATFORMTHEME']='';
for name in list(env):
 if name.startswith('DESKTOP_SHELL_'):env.pop(name)
clientlog=(root/'client-output').open('w');qslog=(root/'quickshell-output').open('w')
client=subprocess.Popen([str(root/'client'),str(root/'actions')],env=env,stdout=clientlog,stderr=subprocess.STDOUT)
process=subprocess.Popen([qs,'--no-color','--path',str(root/'shell.qml')],env=env,stdout=qslog,stderr=subprocess.STDOUT)
def ipc(method,*args):
 return subprocess.check_output([qs,'ipc','--path',str(root/'shell.qml'),'call','fixture',method,*map(str,args)],env=env,text=True,stderr=subprocess.DEVNULL).strip()
def state():return json.loads(ipc('state'))
def waitfor(predicate,label):
 s=None
 for i in range(90):
  try:
   s=state()
   if predicate(s):return s
  except (subprocess.CalledProcessError,json.JSONDecodeError):pass
  if process.poll() is not None:raise RuntimeError('fixture process exited; inspect isolated log')
  time.sleep(.05)
 print('TIMEOUT_STATE',json.dumps(s),flush=True);raise AssertionError(label)
def key(k):
 assert ipc('key',k)=='true','native key event rejected because fixture not active'
 time.sleep(.08)
def actions():return (root/'actions').read_text().splitlines()
def report(label,s):print(label,json.dumps({k:s[k] for k in ['expanded','depth','keyboardRequested','active','triggerCount','contentY','listHeight']}),flush=True)
original_cursor=json.loads(subprocess.check_output(['hyprctl','cursorpos','-j'],text=True)) if pointer else None
def dsp(code):subprocess.run(['hyprctl','dispatch',code],check=True,stdout=subprocess.DEVNULL)
try:
 s=waitfor(lambda s:s['items']==1 and s['hasMenu'],'private Qt tray did not register')
 if pointer:
  # Click a real layer trigger, then repeat without moving the pointer.
  def findlayer(value):
   if isinstance(value,dict):
    if value.get('namespace')=='desktop-shell:tray-test-bar':return value
    for child in value.values():
     found=findlayer(child)
     if found:return found
   elif isinstance(value,list):
    for child in value:
     found=findlayer(child)
     if found:return found
  layer=findlayer(json.loads(subprocess.check_output(['hyprctl','layers','-j'],text=True)))
  assert layer,'fixture layer not mapped'
  dsp('hl.dsp.cursor.move({x='+str(layer['x']+60)+',y='+str(layer['y']+18)+'})');time.sleep(.25)
  subprocess.run([pointer,'pointer','click'],check=True);time.sleep(.45)
  s=state();assert s['expanded'] and s['triggerCount']==1, 'first stationary click did not open';report('stationary first click',s)
  subprocess.run([pointer,'pointer','click'],check=True);time.sleep(.35)
  s=state();assert not s['expanded'], 'stationary second click did not dismiss';report('stationary second click',s)
  subprocess.run([pointer,'pointer','click'],check=True);time.sleep(.4)
  s=state();assert s['expanded'] and s['triggerCount']==2, 'stationary third click did not reopen';report('stationary third click',s)
 if not s['expanded']:ipc('open')
 s=waitfor(lambda s:s['expanded'] and len(s['rows'])>=7 and s['active'],'menu did not gain native keyboard focus')
 report('native root ready',s)
 key("Home")
 s=state();assert s['rows'][0]['focus'],'Home did not focus first enabled action'
 key("Down") # Down: skip disabled
 s=state();assert s['rows'][2]['focus'],'Down failed to skip disabled action'
 before=actions();assert ipc('mouse',1)=='true';time.sleep(.12);assert actions()==before,'disabled item sent DBus action'
 key("Space") # Space toggles check exactly once and closes
 time.sleep(.2);assert actions()==['Check 1'],('check activation count',actions())
 ipc('open');s=waitfor(lambda s:s['expanded'] and len(s['rows'])>=7 and s['active'],'reopen root failed')
 assert s['rows'][2]['checked'],'DBus check state was not reflected on reopen'
 key("Home");key("Down");key("Down") # Home Down Down => Submenu
 key("Right")
 s=waitfor(lambda s:s['depth']==2 and len(s['rows'])==2,'submenu children missing');report('submenu',s)
 key("Left")
 s=waitfor(lambda s:s['depth']==1 and len(s['rows'])>=7,'submenu back failed')
 assert s['rows'][4]['focus'],'parent focus was not restored'
 key("Down");key("Right") # Down => Async, Right
 s=waitfor(lambda s:s['depth']==2 and any(r['text']=='Async child' for r in s['rows']),'async child failed to arrive')
 assert s['rows'][0]['focus'],'async child did not receive focus';report('async submenu',s)
 key("Left");waitfor(lambda s:s['depth']==1 and len(s['rows'])>=7,'return from async failed')
 key("End");key("Right") # End => long submenu
 s=waitfor(lambda s:s['depth']==2 and len(s['rows'])==45,'long submenu failed')
 key("End");s=state();assert s['rows'][-1]['focus'] and s['contentY']>0,'End did not reveal last row';report('long menu End',s)
 for i in range(4):key("Up") # Up burst
 s=state();assert s['rows'][40]['focus'],'repeated Up input lost'
 key("Escape");s=waitfor(lambda s:s['depth']==1,'Escape did not leave submenu')
 key("Escape");s=waitfor(lambda s:not s['expanded'],'Escape did not close root')
 assert actions()==['Check 1'],('unexpected actions',actions())
 runtime_errors=[line for line in (root/'quickshell-output').read_text().splitlines() if 'TypeError:' in line]
 assert not runtime_errors, '\n'.join(runtime_errors)
 print('PASS native Qt tray: disabled skip/action suppression, exact-once check, submenu focus restoration, async arrival, scroll, repeated keys, Escape',flush=True)
except Exception:
 print((root/'quickshell-output').read_text(),file=sys.stderr)
 print((root/'client-output').read_text(),file=sys.stderr)
 raise
finally:
 try:ipc('quit')
 except Exception:pass
 for p in [process,client]:
  if p.poll() is None:p.terminate()
 for p in [process,client]:
  try:p.wait(timeout=2)
  except subprocess.TimeoutExpired:p.kill();p.wait()
 if original_cursor:
  dsp('hl.dsp.cursor.move({x='+str(original_cursor['x'])+',y='+str(original_cursor['y'])+'})')
