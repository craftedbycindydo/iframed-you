package com.wesbos.homehq;

import android.content.SharedPreferences;
import org.json.*;
import java.util.*;
import java.util.concurrent.*;

/** Runs against Android's actual JSON implementation; no real network or account data. */
public final class CalendarStoreTest {
  static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
  static class Memory implements SharedPreferences {
    final Map<String,String> data=new HashMap<>();
    public Map<String,?> getAll(){return data;}
    public String getString(String k,String d){return data.containsKey(k)?data.get(k):d;}
    public boolean contains(String k){return data.containsKey(k);}
    public Set<String> getStringSet(String k,Set<String> d){return d;}
    public int getInt(String k,int d){return d;}public long getLong(String k,long d){return d;}
    public float getFloat(String k,float d){return d;}public boolean getBoolean(String k,boolean d){return d;}
    public void registerOnSharedPreferenceChangeListener(OnSharedPreferenceChangeListener l){}
    public void unregisterOnSharedPreferenceChangeListener(OnSharedPreferenceChangeListener l){}
    public Editor edit(){return new Editor(){
      public Editor putString(String k,String v){data.put(k,v);return this;}
      public Editor putStringSet(String k,Set<String> v){return this;}
      public Editor putInt(String k,int v){return this;}public Editor putLong(String k,long v){return this;}
      public Editor putFloat(String k,float v){return this;}public Editor putBoolean(String k,boolean v){return this;}
      public Editor remove(String k){data.remove(k);return this;}public Editor clear(){data.clear();return this;}
      public boolean commit(){return true;}public void apply(){}
    };}
  }
  static JSONObject fetch(CalendarStore store,String id)throws Exception{
    CountDownLatch ready=new CountDownLatch(1);String[] response={null};
    store.refresh(id,s->{response[0]=s;ready.countDown();});
    check(ready.await(5,TimeUnit.SECONDS),"refresh timed out");return new JSONObject(response[0]);
  }
  public static void main(String[] args)throws Exception{
    Memory prefs=new Memory();String[] next={"BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR"};
    CalendarStore store=new CalendarStore(prefs,url->{if(next[0]==null)throw new Exception();return next[0];});
    String url="https://calendar.google.com/calendar/ical/test%40example.org/private-test/basic.ics";
    String id=store.add("Test","#687354",url);check(!id.isEmpty(),"add");
    check(store.add("Duplicate","#687354",url).isEmpty(),"duplicate rejected");
    check(!store.snapshot().contains("private-test"),"snapshot must omit credentials");
    JSONObject response=fetch(store,id);check(store.accept(id,response.getString("request"),true),"accept");
    response=fetch(store,id);check(store.metadata(id,"Renamed","#547d91"),"metadata edit");check(!store.metadata(id,"","#547d91"),"empty label rejected");check(!store.metadata(id,"Bad","javascript:bad"),"bad colour rejected");check(store.accept(id,response.getString("request"),true),"pending refresh accepted after metadata edit");JSONObject renamed=new JSONArray(store.snapshot()).getJSONObject(0);check(renamed.getString("name").equals("Renamed")&&renamed.getString("color").equals("#547d91"),"refresh preserves new label and colour");check(!store.snapshot().contains("private-test"),"metadata edit does not expose feed");
    String good=store.snapshot();next[0]=null;check(fetch(store,id).has("error"),"network failure");check(good.equals(store.snapshot()),"retain cache after network failure");
    next[0]="BAD CALENDAR";response=fetch(store,id);check(!store.accept(id,response.getString("request"),false),"reject bad parser result");check(good.equals(store.snapshot()),"retain cache after parser failure");
    response=fetch(store,id);store.resetRequests();check(!store.accept(id,response.getString("request"),true),"old renderer response rejected");
    response=fetch(store,id);check(store.remove(id),"remove");check(!store.accept(id,response.getString("request"),true),"removed calendar cannot be resurrected");check(store.snapshot().equals("[]"),"removed metadata and cache");check(!prefs.getString("feeds","").contains("private-test"),"removed secret");store.close();
    CalendarStore restored=new CalendarStore(prefs,url2->"");check(restored.snapshot().equals("[]"),"removal persists");restored.close();
    System.out.println("CalendarStore: 19 checks passed");
  }
}
