"""Exercise the actual native photo retention and validation policy with a JDK."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class PhotoPolicyTest(unittest.TestCase):
    def test_mail_and_cache_boundaries(self):
        config=ROOT/'.local/build.json'
        java_home=Path(json.loads(config.read_text())['java']) if config.exists() else None
        javac=str(java_home/'bin/javac') if java_home else shutil.which('javac')
        java=str(java_home/'bin/java') if java_home else shutil.which('java')
        if not javac or not java:
            self.skipTest('JDK needed for native photo policy test')
        source='''package com.wesbos.homehq;
public class PhotoPolicyTest {
  static void yes(boolean ok){if(!ok)throw new AssertionError();}
  public static void main(String[] args){
    yes(PhotoPolicy.gmail("household"+"@gmail.com"));
    yes(!PhotoPolicy.gmail("household"+"@gmail.com.attacker.test"));
    yes(!PhotoPolicy.gmail("household"+"@outlook.com"));
    yes(PhotoPolicy.limits(30,5)&&PhotoPolicy.limits(90,50));
    yes(!PhotoPolicy.limits(91,30)&&!PhotoPolicy.limits(30,500));
    yes(PhotoPolicy.imageSize(320,240)&&!PhotoPolicy.imageSize(1,1));
    yes(PhotoPolicy.sampleSize(8000,6000)>=4);
    long now=100L*86400000L;
    yes(PhotoPolicy.retain(now-30L*86400000L,now,30));
    yes(!PhotoPolicy.retain(now-31L*86400000L,now,30));
    yes(!PhotoPolicy.retain(now+2L*86400000L,now,30));
    yes(PhotoPolicy.photoId("a".repeat(64)));
    yes(!PhotoPolicy.photoId("../"+"a".repeat(64)));
  }
}'''
        with tempfile.TemporaryDirectory() as directory:
            harness=Path(directory)/'PhotoPolicyTest.java'
            harness.write_text(source)
            subprocess.run([javac,'-d',directory,str(ROOT/'android/src/com/wesbos/homehq/PhotoPolicy.java'),str(harness)],check=True,capture_output=True,text=True)
            result=subprocess.run([java,'-cp',directory,'com.wesbos.homehq.PhotoPolicyTest'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
