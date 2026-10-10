#!/usr/bin/env python3
"""Run isolated calendar-store checks on a paired frame; no household preferences touched."""
from pathlib import Path
import json,os,subprocess
ROOT=Path(__file__).resolve().parents[1]
c=json.loads((ROOT/'.local/build.json').read_text())
build=ROOT/'.local/calendar-test';build.mkdir(exist_ok=True)
classes=build/'classes';classes.mkdir(exist_ok=True)
java=Path(c['java']);env=dict(os.environ,JAVA_HOME=str(java),PATH=str(java/'bin')+':'+os.environ['PATH'])
sources=[ROOT/'android/src/com/wesbos/homehq'/name for name in ['CalendarStore.java','CalendarFeed.java']]+[ROOT/'tests/android/CalendarStoreTest.java']
subprocess.run([str(java/'bin/javac'),'-source','8','-target','8','-classpath',c['android_jar'],'-d',str(classes),*map(str,sources)],env=env,check=True)
subprocess.run([str(Path(c['build_tools'])/'d8'),'--min-api','23','--lib',c['android_jar'],'--output',str(build),*map(str,classes.rglob('*.class'))],env=env,check=True)
frame=['python3',str(ROOT/'scripts/frame.py')]
remote='/data/local/tmp/skylit-calendar-test.dex'
try:
 subprocess.run(frame+['push',str(build/'classes.dex'),remote],check=True)
 subprocess.run(frame+['shell','env','CLASSPATH='+remote,'app_process','/','com.wesbos.homehq.CalendarStoreTest'],check=True)
finally:
 subprocess.run(frame+['shell','rm','-f',remote],check=True)
