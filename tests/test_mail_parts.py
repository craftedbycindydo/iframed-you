"""Decode a serialized multipart message with the pinned Android mail libraries."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]


class MailPartsTest(unittest.TestCase):
    def test_multipart_image_delivery_and_limits(self):
        config=ROOT/'.local/build.json'
        java_home=Path(json.loads(config.read_text())['java']) if config.exists() else None
        javac=str(java_home/'bin/javac') if java_home else shutil.which('javac')
        java=str(java_home/'bin/java') if java_home else shutil.which('java')
        if not javac or not java:
            self.skipTest('JDK needed for mail MIME test')
        jars=[ROOT/'vendor/mail/android-mail-1.6.7.jar',ROOT/'vendor/mail/android-activation-1.6.7.jar']
        source='''package com.wesbos.homehq;
import java.io.*;import java.util.*;import javax.activation.*;import javax.mail.*;
import javax.mail.internet.*;import javax.mail.util.ByteArrayDataSource;
public class MailPartsTest {
  static void yes(boolean value){if(!value)throw new AssertionError();}
  public static void main(String[] args)throws Exception {
    Session session=Session.getInstance(new Properties());
    MimeMessage message=new MimeMessage(session);
    MimeMultipart multipart=new MimeMultipart();
    MimeBodyPart text=new MimeBodyPart();text.setText("not a photo");multipart.addBodyPart(text);
    byte[] original=new byte[]{1,2,3,4,5};
    MimeBodyPart image=new MimeBodyPart();
    image.setDataHandler(new DataHandler(new ByteArrayDataSource(original,"image/jpeg")));
    image.setFileName("picture.jpg");multipart.addBodyPart(image);
    message.setContent(multipart);message.saveChanges();
    ByteArrayOutputStream serialized=new ByteArrayOutputStream();message.writeTo(serialized);
    MimeMessage decoded=new MimeMessage(session,new ByteArrayInputStream(serialized.toByteArray()));
    int[] delivered={0};
    int scanned=MailParts.collect(decoded,123L,10,(input,received)->{
      yes(received==123L);yes(Arrays.equals(input.readAllBytes(),original));delivered[0]++;
    });
    yes(scanned==1&&delivered[0]==1);
    yes(MailParts.collect(decoded,123L,0,(input,received)->{throw new AssertionError();})==0);
  }
}'''
        with tempfile.TemporaryDirectory() as directory:
            harness=Path(directory)/'MailPartsTest.java'
            harness.write_text(source)
            classpath=os.pathsep.join(map(str,jars))
            subprocess.run([javac,'-classpath',classpath,'-d',directory,str(ROOT/'android/src/com/wesbos/homehq/MailParts.java'),str(ROOT/'android/src/com/wesbos/homehq/PhotoPolicy.java'),str(harness)],check=True,capture_output=True,text=True)
            result=subprocess.run([java,'-cp',directory+os.pathsep+classpath,'com.wesbos.homehq.MailPartsTest'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
