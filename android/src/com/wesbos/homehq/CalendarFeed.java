package com.wesbos.homehq;

import java.net.URI;
import java.net.HttpURLConnection;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;

/** Direct Google iCalendar downloads: no cookies, redirects, proxy or URL logging. */
public final class CalendarFeed {
  public static boolean valid(String value) {
    try {
      URI u=new URI(value);
      return value.length()<=2048 && "https".equals(u.getScheme()) &&
        "calendar.google.com".equals(u.getHost()) && u.getRawUserInfo()==null &&
        u.getPort()==-1 && u.getRawQuery()==null && u.getRawFragment()==null &&
        u.getPath().split("/",-1).length==6 && u.getPath().split("/",-1)[3].contains("@") &&
        u.getPath().split("/",-1)[3].matches("[A-Za-z0-9._#@+\\-]+") &&
        u.getRawPath().matches("/calendar/ical/[A-Za-z0-9@._%+\\-]+/(?:private-[A-Za-z0-9]+|public)/basic\\.ics");
    } catch(Exception e) { return false; }
  }
  public static String download(String url) throws Exception {
    if(!valid(url))throw new Exception("Unsupported calendar address");
    HttpURLConnection c=(HttpURLConnection)new URI(url).toURL().openConnection();
    c.setInstanceFollowRedirects(false);c.setConnectTimeout(10000);c.setReadTimeout(10000);
    c.setUseCaches(false);c.setRequestProperty("Accept","text/calendar");
    c.setRequestProperty("User-Agent","Skylit/2.5");
    try {
      if(c.getResponseCode()!=200)throw new Exception("Calendar unavailable");
      if(c.getContentLength()>2097152)throw new Exception("Calendar too large");
      long deadline=System.nanoTime()+30000000000L;
      try(InputStream in=c.getInputStream();ByteArrayOutputStream out=new ByteArrayOutputStream()){
        byte[] buffer=new byte[8192];int n;
        while((n=in.read(buffer))!=-1){
          if(out.size()+n>2097152||System.nanoTime()>deadline)throw new Exception("Calendar limit");
          out.write(buffer,0,n);
        }
        String body=new String(out.toByteArray(),StandardCharsets.UTF_8);
        if(!body.trim().startsWith("BEGIN:VCALENDAR")||!body.trim().endsWith("END:VCALENDAR"))throw new Exception("Not a calendar");
        return body;
      }
    } finally { c.disconnect(); }
  }
}
