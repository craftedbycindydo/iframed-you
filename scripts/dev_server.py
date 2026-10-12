#!/usr/bin/env python3
from pathlib import Path
import argparse, json, shutil, signal, subprocess, tempfile

ROOT=Path(__file__).resolve().parents[1]
PURE_SOURCES=('ApiException','CalendarFeed','Digests','Fields','FrameTime','HouseholdStore','ICloudAlbum','ICloudHttp','ICloudSync','Identity','Json','KeyValue','LocalApi','LocalHttp','LocalServer','Pairing','PhotoPolicy')

def jdk():
    config=ROOT/'.local/build.json'
    home=Path(json.loads(config.read_text())['java']) if config.exists() else None
    javac=str(home/'bin/javac') if home else shutil.which('javac')
    java=str(home/'bin/java') if home else shutil.which('java')
    return javac,java

def compile_pure(javac,classes):
    sources=[ROOT/'android/src/com/wesbos/homehq'/f'{name}.java' for name in PURE_SOURCES]+sorted((ROOT/'tests/android/jvm').glob('*.java'))
    subprocess.run([javac,'--release','8','-Xlint:-options','-d',str(classes),*map(str,sources)],check=True,capture_output=True,text=True)

def main():
    parser=argparse.ArgumentParser(description="Run the frame's local phone API on this computer with throwaway in-memory data.")
    parser.add_argument('--port',type=int,default=8765)
    parser.add_argument('--lan',action='store_true',help='Listen on every interface instead of 127.0.0.1')
    parser.add_argument('--fake-icloud',action='store_true',help='Serve a canned four-picture album for any valid shared album link instead of contacting Apple')
    parser.add_argument('--advertise',action='store_true',help='Also publish _skylit._tcp through dns-sd')
    parser.add_argument('--pair-window',action='store_true',help='Open a 120 s pairing window at start. Press Enter to open another.')
    parser.add_argument('--auto-approve',type=float,nargs='?',const=2.0,metavar='SECONDS',help='After the code appears, wait this long (default 2) and then tap as --tap says')
    parser.add_argument('--tap',choices=('pick','decoy','cancel','none'),default='pick',help='What --auto-approve taps: the right number, a wrong one, Cancel, or nothing')
    parser.add_argument('--control-port',type=int,metavar='PORT',help='Serve /state, /open, /cancel and /tap/NN as plain HTTP on 127.0.0.1 only (0 picks a free port)')
    args=parser.parse_args()
    javac,java=jdk()
    if not javac or not java: raise SystemExit('A JDK is required')
    signal.signal(signal.SIGTERM,signal.default_int_handler)
    with tempfile.TemporaryDirectory() as classes:
        compile_pure(javac,classes)
        server=subprocess.Popen([java,'-cp',classes,'com.wesbos.homehq.DevServer',str(args.port),'lan' if args.lan else 'loopback','fake-icloud' if args.fake_icloud else 'live-icloud',
            'window' if args.pair_window else 'closed','none' if args.auto_approve is None else args.tap,str(int((args.auto_approve or 0)*1000)),
            str(-1 if args.control_port is None else args.control_port)],stdout=subprocess.PIPE,text=True)
        advert=None
        try:
            first=server.stdout.readline()
            print(first,end='',flush=True)
            if args.advertise and first:
                advert=subprocess.Popen(['dns-sd','-R','Skylit','_skylit._tcp','local',first.split()[-1],'v=2','id='+first.split()[3]])
            for line in server.stdout: print(line,end='',flush=True)
        except KeyboardInterrupt:
            pass
        finally:
            if advert: advert.terminate()
            server.terminate()
            server.wait()

if __name__=='__main__': main()
