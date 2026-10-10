package com.wesbos.homehq;

import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.HashMap;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Private configuration and validated last-good feeds. All public snapshots omit URLs. */
final class CalendarStore {
  interface Receiver { void accept(String result); }
  interface Downloader { String get(String url) throws Exception; }
  private final Downloader downloader;
  private final SharedPreferences prefs;
  private final ExecutorService executor=Executors.newSingleThreadExecutor();
  private final HashMap<String,JSONObject> pending=new HashMap<>();
  private final HashMap<String,String> requests=new HashMap<>();
  CalendarStore(SharedPreferences prefs){this(prefs,CalendarFeed::download);}
  CalendarStore(SharedPreferences prefs,Downloader downloader){this.prefs=prefs;this.downloader=downloader;}
  private JSONArray rows(){try{return new JSONArray(prefs.getString("feeds","[]"));}catch(Exception e){return new JSONArray();}}
  private JSONObject find(String id){JSONArray a=rows();for(int i=0;i<a.length();i++)if(id.equals(a.optJSONObject(i).optString("id")))return a.optJSONObject(i);return null;}
  synchronized String snapshot(){
    JSONArray result=new JSONArray(),a=rows();
    for(int i=0;i<a.length();i++)try{JSONObject row=new JSONObject(a.getJSONObject(i).toString());row.remove("url");result.put(row);}catch(Exception e){}
    return result.toString();
  }
  synchronized String add(String name,String color,String url){
    try{
      if(!CalendarFeed.valid(url))return "";
      JSONArray a=rows();if(a.length()>=6)return "";
      for(int i=0;i<a.length();i++)if(url.equals(a.getJSONObject(i).optString("url")))return "";
      String id=UUID.randomUUID().toString();
      JSONObject row=new JSONObject().put("id",id).put("name",name.trim().isEmpty()?"Calendar":name.trim().substring(0,Math.min(60,name.trim().length())))
        .put("color",color.matches("#[a-fA-F0-9]{6}")?color:"#9a513b").put("url",url).put("body","").put("fetchedAt",0);
      a.put(row);if(!prefs.edit().putString("feeds",a.toString()).commit())return "";return id;
    }catch(Exception e){return "";}
  }
  synchronized boolean remove(String id){
    JSONArray a=rows(),next=new JSONArray();for(int i=0;i<a.length();i++)if(!id.equals(a.optJSONObject(i).optString("id")))next.put(a.optJSONObject(i));
    requests.remove(id);pending.remove(id);return prefs.edit().putString("feeds",next.toString()).commit();
  }
  synchronized void refresh(String id,Receiver callback){
    JSONObject row=find(id);if(row==null||requests.containsKey(id))return;
    final String request=UUID.randomUUID().toString(),url=row.optString("url");requests.put(id,request);
    executor.execute(()->{
      JSONObject result=new JSONObject();
      try{result.put("id",id).put("request",request).put("body",downloader.get(url)).put("fetchedAt",System.currentTimeMillis());}
      catch(Exception e){try{result.put("id",id).put("request",request).put("error","Could not fetch this calendar. Check Wi-Fi and the private link.");}catch(Exception ignored){}}
      synchronized(CalendarStore.this){
        if(!request.equals(requests.get(id))||find(id)==null)return;
        if(!result.has("error"))pending.put(id,result);else requests.remove(id);
      }
      callback.accept(result.toString());
    });
  }
  synchronized boolean accept(String id,String request,boolean valid){
    JSONObject candidate=pending.get(id);if(candidate==null||!request.equals(candidate.optString("request")))return false;
    pending.remove(id);requests.remove(id);if(!valid)return false;
    JSONArray a=rows();try{for(int i=0;i<a.length();i++){JSONObject row=a.getJSONObject(i);if(id.equals(row.optString("id"))){row.put("body",candidate.getString("body")).put("fetchedAt",candidate.getLong("fetchedAt"));return prefs.edit().putString("feeds",a.toString()).commit();}}}catch(Exception e){}return false;
  }
  synchronized void resetRequests(){requests.clear();pending.clear();}
  synchronized void close(){requests.clear();pending.clear();executor.shutdownNow();}
}
