"""Exercise production native URL and download boundaries with in-memory HTTPS responses."""
import json
from pathlib import Path
import shutil,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class CalendarNativeTest(unittest.TestCase):
    def test_download_policy(self):
        config=ROOT/'.local/build.json'
        home=Path(json.loads(config.read_text())['java']) if config.exists() else None
        javac=str(home/'bin/javac') if home else shutil.which('javac')
        java=str(home/'bin/java') if home else shutil.which('java')
        if not javac or not java:self.skipTest('JDK required')
        code=r'''package com.wesbos.homehq;
import java.net.*;import java.io.*;import java.nio.charset.StandardCharsets;
public class CalendarTest {
 static int status=200;static String body="BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR";
 static boolean visited=false;
 static void check(boolean yes){if(!yes)throw new AssertionError();}
 static class Connection extends HttpURLConnection {
  Connection(URL u){super(u);}
  public void connect(){} public void disconnect(){} public boolean usingProxy(){return false;}
  public int getResponseCode(){check(!getInstanceFollowRedirects());check(getRequestProperty("Cookie")==null);visited=true;return status;}
  public InputStream getInputStream(){return new ByteArrayInputStream(body.getBytes(StandardCharsets.UTF_8));}
 }
 public static void main(String[] args)throws Exception{
  String ok="https://calendar.google.com/calendar/ical/test%40example.org/private-test/basic.ics";
  check(CalendarFeed.valid(ok));
  for(String bad:new String[]{ok.replace("https:","http:"),ok.replace("calendar.google.com","calendar.google.com.evil.test"),ok.replace("calendar.google.com","calendar.google.com:443"),ok.replace("calendar.google.com","user@calendar.google.com"),ok+"?x=1",ok+"#x",ok.replace("/test%40example.org/","/../"),"https://127.0.0.1/calendar/ical/test/public/basic.ics","https://calendar.google.com/calendar/u/0/r"})check(!CalendarFeed.valid(bad));
  URL.setURLStreamHandlerFactory(protocol->"https".equals(protocol)?new URLStreamHandler(){protected URLConnection openConnection(URL u){return new Connection(u);}}:null);
  check(CalendarFeed.download(ok).equals(body));check(visited);
  for(int code:new int[]{301,302,403,404,500}){status=code;try{CalendarFeed.download(ok);throw new AssertionError("HTTP accepted");}catch(Exception expected){}}
  status=200;body="<html>Sign in</html>";try{CalendarFeed.download(ok);throw new AssertionError("HTML accepted");}catch(Exception expected){}
  body="BEGIN:VCALENDAR"+new String(new char[2097152]).replace('\0','x')+"END:VCALENDAR";try{CalendarFeed.download(ok);throw new AssertionError("Oversize accepted");}catch(Exception expected){}
 }
}'''
        with tempfile.TemporaryDirectory() as tmp:
            src=Path(tmp)/'CalendarTest.java';src.write_text(code)
            subprocess.run([javac,'-d',tmp,str(ROOT/'android/src/com/wesbos/homehq/CalendarFeed.java'),str(src)],check=True,capture_output=True,text=True)
            result=subprocess.run([java,'-cp',tmp,'com.wesbos.homehq.CalendarTest'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
