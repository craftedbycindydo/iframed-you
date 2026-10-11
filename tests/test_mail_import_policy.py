"""Exercise native mail scheduling, sender filtering and YouTube bridge boundaries."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class MailImportPolicyTest(unittest.TestCase):
    def test_native_policy(self):
        config=ROOT/'.local/build.json'
        java_home=Path(json.loads(config.read_text())['java']) if config.exists() else None
        javac=str(java_home/'bin/javac') if java_home else shutil.which('javac')
        java=str(java_home/'bin/java') if java_home else shutil.which('java')
        if not javac or not java:
            self.skipTest('JDK needed for native policy test')
        source='''package com.wesbos.homehq;
import java.util.HashSet;
import java.util.Arrays;
public class MailImportPolicyTest {
 static void yes(boolean value){if(!value)throw new AssertionError();}
 public static void main(String[] args){
  long now=1000000000L;
  yes(MailImportPolicy.due(now-900000L,0,0,now,900));
  yes(!MailImportPolicy.due(now-899999L,0,0,now,900));
  yes(!MailImportPolicy.due(now-900000L,0,0,now,3600));
  yes(MailImportPolicy.due(0,0,0,now,86400));
  yes(!MailImportPolicy.due(0,now-1000,1,now,900));
  yes(MailImportPolicy.due(0,now-300000,1,now,900));
  yes(MailImportPolicy.backoff(10)==3600000L);
  yes(MailImportPolicy.due(now+3600000L,0,0,now,900));
  HashSet<String> approved=new HashSet<>(Arrays.asList("sender@example.invalid"));
  yes(MailImportPolicy.allowed(true,approved,new String[]{" SENDER@example.invalid "}));
  yes(!MailImportPolicy.allowed(true,approved,new String[]{"sender@example.invalid.attacker.test"}));
  yes(!MailImportPolicy.allowed(true,approved,new String[]{"sender@example.invalid","other@example.invalid"}));
  yes(!MailImportPolicy.allowed(true,approved,null));
  yes(MailImportPolicy.allowed(false,approved,null));
  yes(YouTubeLink.valid("https://www.youtube.com/watch?v=abcdefghijk"));
  yes(YouTubeLink.valid("https://m.youtube.com/playlist?list=PLabcdefghijk"));
  yes(!YouTubeLink.valid("https://youtube.com.evil.test/watch?v=abcdefghijk"));
  yes(!YouTubeLink.valid("https://account@youtube.com/watch?v=abcdefghijk"));
  yes(!YouTubeLink.valid("https://youtube.com/watch?v=abcdefghijk&redirect=secret"));
  yes(!YouTubeLink.valid("https://youtube.com:443/watch?v=abcdefghijk"));
 }
}'''
        with tempfile.TemporaryDirectory() as directory:
            harness=Path(directory)/'MailImportPolicyTest.java'
            harness.write_text(source)
            native=ROOT/'android/src/com/wesbos/homehq'
            subprocess.run([javac,'-d',directory,str(native/'MailImportPolicy.java'),str(native/'YouTubeLink.java'),str(harness)],check=True,capture_output=True,text=True)
            result=subprocess.run([java,'-cp',directory,'com.wesbos.homehq.MailImportPolicyTest'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
