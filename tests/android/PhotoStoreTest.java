package com.wesbos.homehq;

import android.content.SharedPreferences;
import android.graphics.Bitmap;
import org.json.*;
import java.io.*;
import java.util.*;
import java.util.concurrent.*;

/** Actual Android image/JSON/storage behavior in an isolated shell-owned directory. */
public final class PhotoStoreTest {
  static int checks;
  static void check(boolean value,String message){if(!value)throw new AssertionError(message);checks++;}
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
  static byte[] image(int seed){Bitmap b=Bitmap.createBitmap(400,300,Bitmap.Config.ARGB_8888);Random random=new Random(seed);int[] pixels=new int[400*300];for(int i=0;i<pixels.length;i++)pixels[i]=0xff000000|random.nextInt(0xffffff);b.setPixels(pixels,0,400,0,0,400,300);ByteArrayOutputStream out=new ByteArrayOutputStream();b.compress(Bitmap.CompressFormat.PNG,100,out);b.recycle();return out.toByteArray();}
  static void remove(File f){if(f.isDirectory()){File[] files=f.listFiles();if(files!=null)for(File child:files)remove(child);}f.delete();}
  static boolean excluded(PhotoStore store,String id){return store.excluded().toString().contains(id);}
  public static void main(String[] args)throws Exception{
    File root=new File(args[0]);root.mkdirs();long now=System.currentTimeMillis(),day=86400000L;byte[] first=image(1),second=image(2);
    try{
      Memory memory=new Memory();File folder=new File(root,"persistence");PhotoStore store=new PhotoStore(folder,memory);
      check(store.add(new ByteArrayInputStream(first),now-day),"initial image saved");String id=store.list().getJSONObject(0).getString("id");
      check(!store.add(new ByteArrayInputStream(first),now),"duplicate deduplicated");check(store.list().length()==1,"duplicate count");
      check(store.exclude(id,true),"exclude saved");check(!store.exclude("../escape",true),"invalid exclusion rejected");
      store=new PhotoStore(folder,memory);check(excluded(store,id),"exclusion survives reopening");
      check(!store.add(new ByteArrayInputStream(first),now),"same source rejected by check");
      store.prune(30,30);check(store.list().length()==1,"excluded cache retained for undo when space permits");
      check(store.exclude(id,false)&&!excluded(store,id),"undo restores eligibility");
      check(!store.add(new ByteArrayInputStream(first),now),"undo retains cached duplicate");
      store.exclude(id,true);new File(folder,id+".jpg").delete();store.prune(7,30);check(store.list().length()==0,"missing cache pruned");
      check(excluded(store,id),"pruning never forgets exclusion");check(!store.add(new ByteArrayInputStream(first),now),"pruned excluded source cannot reimport");
      check(store.restoreExcluded(),"restore exclusions");check(store.add(new ByteArrayInputStream(first),now),"restored source imports again");
      store.exclude(id,true);store.clear();check(store.excluded().length()==0&&store.list().length()==0,"explicit clear removes images and exclusions");
      // Exercise every date option against received dates on Android, without real email.
      for(int days:new int[]{7,30,90,180}){
        PhotoStore aged=new PhotoStore(new File(root,"age"+days),new Memory());int expected=0;
        for(int i=0;i<6;i++){long age=new long[]{1,5,20,45,120,220}[i];aged.add(new ByteArrayInputStream(image(10+i)),now-age*day);if(age<=days)expected++;}
        aged.prune(days,50);check(aged.list().length()==expected,"received-date window "+days);
      }
      // Count mode spans old dates; exclusions never consume visible slots and total files stay bounded.
      ArrayList<byte[]> images=new ArrayList<>();for(int i=0;i<60;i++)images.add(image(100+i));
      for(int limit:new int[]{10,20,30,40,50}){
        PhotoStore counted=new PhotoStore(new File(root,"count"+limit),new Memory());String excludedId="";
        for(int i=0;i<60;i++){counted.add(new ByteArrayInputStream(images.get(i)),now-(200+i)*day);if(i==0)excludedId=counted.list().getJSONObject(0).getString("id");}
        counted.exclude(excludedId,true);counted.prune(0,limit);JSONArray rows=counted.list();int visible=0;long newest=0;
        for(int i=0;i<rows.length();i++){JSONObject row=rows.getJSONObject(i);if(!row.getString("id").equals(excludedId)){visible++;newest=Math.max(newest,row.getLong("at"));}}
        check(visible==limit,"count window "+limit);check(rows.length()<=50,"hard cache bound "+limit);check(newest==now-201*day,"excluded newest does not use slot "+limit);check(excluded(counted,excludedId),"count prune retains rule "+limit);
      }
      PhotoStore restoredLimit=new PhotoStore(new File(root,"restore-limit"),new Memory());String oldId="";
      for(int i=0;i<31;i++){restoredLimit.add(new ByteArrayInputStream(images.get(i)),now-(200+i)*day);if(i==30)oldId=restoredLimit.list().getJSONObject(30).getString("id");}
      restoredLimit.exclude(oldId,true);restoredLimit.prune(0,30);check(restoredLimit.list().length()==31,"excluded cache can occupy spare space");
      restoredLimit.restoreExcluded();restoredLimit.prune(0,30);check(restoredLimit.list().length()==30,"restore respects selected gallery capacity");
      // Interleaved importer/owner exclusion resolves safely under the store lock.
      PhotoStore raced=new PhotoStore(new File(root,"race"),new Memory());raced.add(new ByteArrayInputStream(second),now);String racedId=raced.list().getJSONObject(0).getString("id");
      final PhotoStore race=raced;Thread importer=new Thread(()->{try{for(int i=0;i<10;i++)race.add(new ByteArrayInputStream(second),now);}catch(Exception e){throw new RuntimeException(e);}});importer.start();raced.exclude(racedId,true);importer.join();check(!raced.add(new ByteArrayInputStream(second),now)&&excluded(raced,racedId),"refresh/exclusion race cannot resurrect source");
      memory.data.put("excluded",new JSONArray(Arrays.asList(id,"invalid",id)).toString());check(new PhotoStore(folder,memory).excluded().length()==1,"loaded exclusions validate and deduplicate");
      Memory phoneMemory=new Memory();PhotoStore phoneStore=new PhotoStore(new File(root,"phone"),phoneMemory);byte[] sent=image(900),mailed=image(901);
      check(phoneStore.add(sent,now-200*day,"phone"),"phone picture saved");String sentId=phoneStore.list().getJSONObject(0).getString("id");
      check(phoneStore.add(new ByteArrayInputStream(mailed),now-day),"mailed picture saved beside it");String mailedId=phoneStore.list().getJSONObject(0).getString("id");
      phoneStore.prune(7,30);check(phoneStore.list().length()==2,"phone pictures ignore the mail age window");
      phoneStore=new PhotoStore(new File(root,"phone"),phoneMemory);phoneStore.prune(7,30);check(phoneStore.list().length()==2,"phone origin survives reopening");
      check(phoneStore.remove(mailedId)&&excluded(phoneStore,mailedId)&&!phoneStore.add(new ByteArrayInputStream(mailed),now),"removing a mailed picture blocks its re-import");
      check(phoneStore.add(mailed,now,"phone")&&!excluded(phoneStore,mailedId),"a phone upload overrides that exclusion");
      check(phoneStore.remove(sentId)&&!excluded(phoneStore,sentId)&&phoneStore.add(sent,now,"phone"),"a removed phone picture can be sent again");
      check(!phoneStore.remove("../escape")&&!phoneStore.remove(sentId.replace(sentId.charAt(0),sentId.charAt(0)=='a'?'b':'a')),"unknown ids are not removed");
      check(phoneStore.add(new ByteArrayInputStream(image(902)),now-day),"another mailed picture");phoneStore.clearImported();check(phoneStore.list().length()==2&&phoneStore.excluded().length()==0,"changing the mail account keeps phone pictures only");
      byte[] shared=image(903),another=image(904);check(phoneStore.add(shared,now-400*day,"album")&&phoneStore.add(another,now-300*day,"album"),"album pictures saved");String sharedId=phoneStore.list().getJSONObject(3).getString("id");
      phoneStore.prune(7,30);check(phoneStore.list().length()==4&&phoneStore.list().getJSONObject(3).getString("origin").equals("album"),"album pictures ignore the mail age window and report their origin");
      check(phoneStore.removeOrigin("album",sentId)==0&&phoneStore.removeOrigin("album",sharedId)==1&&!excluded(phoneStore,sharedId)&&phoneStore.list().length()==3,"album removal touches only album pictures and leaves no exclusion");
      check(phoneStore.add(shared,now-400*day,"album")&&phoneStore.remove(sharedId)&&excluded(phoneStore,sharedId)&&!phoneStore.add(shared,now,"album"),"an album picture trashed on the frame is not taken again");
      check(!phoneStore.add(sent,now,"album")&&phoneStore.removeOrigin("album",null)==1&&phoneStore.list().length()==2,"disconnecting the album keeps phone pictures, even identical ones");
      phoneStore.clear();check(phoneStore.list().length()==0,"explicit erase removes phone pictures too");
      System.out.println("PhotoStore: "+checks+" isolated Android checks passed");
    }finally{remove(root);}
  }
}
