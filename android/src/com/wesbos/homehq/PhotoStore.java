package com.wesbos.homehq;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.os.Build;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;

/** Small, private, metadata-free photo cache. No mail body is persisted. */
final class PhotoStore {
  private final File directory;
  private final SharedPreferences preferences;
  private static final class Item {String id;long at;Item(String i,long t){id=i;at=t;}}
  PhotoStore(Context context){directory=new File(context.getFilesDir(),"mail-photos");directory.mkdirs();preferences=context.getSharedPreferences("skylit-photo-index",Context.MODE_PRIVATE);}
  private ArrayList<Item> read(){ArrayList<Item> list=new ArrayList<>();try{JSONArray rows=new JSONArray(preferences.getString("items","[]"));for(int i=0;i<rows.length();i++){JSONObject row=rows.getJSONObject(i);String id=row.optString("id");if(PhotoPolicy.photoId(id))list.add(new Item(id,row.optLong("at")));}}catch(Exception ignored){}return list;}
  private void write(ArrayList<Item> list){JSONArray rows=new JSONArray();for(Item item:list){JSONObject row=new JSONObject();try{row.put("id",item.id);row.put("at",item.at);rows.put(row);}catch(Exception ignored){}}preferences.edit().putString("items",rows.toString()).commit();}
  private static byte[] bounded(InputStream stream) throws Exception {ByteArrayOutputStream out=new ByteArrayOutputStream();byte[] buffer=new byte[32768];int n,total=0;while((n=stream.read(buffer))!=-1){total+=n;if(total>PhotoPolicy.MAX_DOWNLOAD)throw new IllegalArgumentException("Photo exceeds size limit");out.write(buffer,0,n);}return out.toByteArray();}
  private static String digest(byte[] data) throws Exception {byte[] hash=MessageDigest.getInstance("SHA-256").digest(data);StringBuilder result=new StringBuilder();for(byte b:hash)result.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return result.toString();}
  private static int orientation(byte[] data){if(Build.VERSION.SDK_INT<24)return 1;try{return new android.media.ExifInterface(new ByteArrayInputStream(data)).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION,1);}catch(Exception ignored){return 1;}}
  private static Bitmap rotate(Bitmap image,int orientation){Matrix matrix=new Matrix();switch(orientation){case 2:matrix.postScale(-1,1);break;case 3:matrix.postRotate(180);break;case 4:matrix.postScale(1,-1);break;case 5:matrix.postRotate(90);matrix.postScale(-1,1);break;case 6:matrix.postRotate(90);break;case 7:matrix.postRotate(270);matrix.postScale(-1,1);break;case 8:matrix.postRotate(270);break;default:return image;}Bitmap result=Bitmap.createBitmap(image,0,0,image.getWidth(),image.getHeight(),matrix,true);image.recycle();return result;}
  synchronized boolean add(InputStream input,long receivedAt) throws Exception {
    byte[] original=bounded(input);if(original.length<4096)return false;
    String id=digest(original);ArrayList<Item> items=read();
    for(int i=0;i<items.size();i++)if(items.get(i).id.equals(id)){if(new File(directory,id+".jpg").isFile()){items.get(i).at=Math.max(items.get(i).at,receivedAt);write(items);return false;}items.remove(i);break;}
    BitmapFactory.Options options=new BitmapFactory.Options();options.inJustDecodeBounds=true;BitmapFactory.decodeByteArray(original,0,original.length,options);
    if(!PhotoPolicy.imageSize(options.outWidth,options.outHeight))return false;
    int sample=PhotoPolicy.sampleSize(options.outWidth,options.outHeight);
    options.inJustDecodeBounds=false;options.inSampleSize=sample;Bitmap image=BitmapFactory.decodeByteArray(original,0,original.length,options);if(image==null)return false;
    try{
      image=rotate(image,orientation(original));ByteArrayOutputStream output=new ByteArrayOutputStream();
      for(int quality=86;quality>=60;quality-=13){output.reset();if(!image.compress(Bitmap.CompressFormat.JPEG,quality,output))return false;if(output.size()<=PhotoPolicy.MAX_JPEG)break;}
      if(output.size()>PhotoPolicy.MAX_JPEG)return false;
      File target=new File(directory,id+".jpg"),temporary=new File(directory,id+".tmp");
      try(FileOutputStream file=new FileOutputStream(temporary)){file.write(output.toByteArray());file.getFD().sync();}
      if(!temporary.renameTo(target)){temporary.delete();throw new java.io.IOException("Could not save image");}
      items.add(new Item(id,receivedAt));write(items);return true;
    }finally{if(!image.isRecycled())image.recycle();}
  }
  synchronized int prune(int days,int maximum){long now=System.currentTimeMillis();ArrayList<Item> items=read(),kept=new ArrayList<>();Collections.sort(items,(a,b)->Long.compare(b.at,a.at));HashSet<String> ids=new HashSet<>();for(Item item:items)if(PhotoPolicy.retain(item.at,now,days)&&kept.size()<maximum&&new File(directory,item.id+".jpg").isFile()&&ids.add(item.id))kept.add(item);write(kept);File[] files=directory.listFiles();if(files!=null)for(File file:files)if(!file.getName().endsWith(".jpg")||!ids.contains(file.getName().replace(".jpg","")))file.delete();return kept.size();}
  synchronized JSONArray list(){ArrayList<Item> items=read();Collections.sort(items,(a,b)->Long.compare(b.at,a.at));JSONArray rows=new JSONArray();for(Item item:items)if(new File(directory,item.id+".jpg").isFile()){JSONObject row=new JSONObject();try{row.put("id",item.id);row.put("at",item.at);row.put("url","https://appassets.androidplatform.net/private-photos/"+item.id+".jpg");rows.put(row);}catch(Exception ignored){}}return rows;}
  synchronized InputStream open(String id) throws Exception {if(!PhotoPolicy.photoId(id))throw new IllegalArgumentException("Invalid photo");File image=new File(directory,id+".jpg");if(!image.isFile())throw new java.io.FileNotFoundException();return new FileInputStream(image);}
  synchronized void clear(){preferences.edit().remove("items").commit();File[] files=directory.listFiles();if(files!=null)for(File file:files)file.delete();}
}
