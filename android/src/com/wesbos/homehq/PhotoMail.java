package com.wesbos.homehq;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import org.json.JSONObject;
import org.json.JSONArray;
import java.util.HashSet;
import javax.mail.Address;
import javax.mail.internet.InternetAddress;
import java.util.Date;
import java.util.Properties;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import javax.mail.Folder;
import javax.mail.Message;
import javax.mail.Session;
import javax.mail.Store;
import javax.mail.AuthenticationFailedException;
import javax.mail.search.ComparisonTerm;
import javax.mail.search.ReceivedDateTerm;
import com.sun.mail.imap.IMAPSSLStore;

/** Read-only Gmail IMAPS importer. Only decoded, resized images reach PhotoStore. */
final class PhotoMail {
  interface Listener {void changed();}
  private final SharedPreferences preferences;
  private final PhotoStore photos;
  private final ExecutorService worker=Executors.newSingleThreadExecutor();
  private final Handler main=new Handler(Looper.getMainLooper());
  private final Listener listener;
  private volatile boolean busy;
  private volatile String error="";
  private volatile int visited, imported, skipped;
  PhotoMail(Context context,PhotoStore store,Listener changed){preferences=context.getSharedPreferences("skylit-photo-mail",Context.MODE_PRIVATE);photos=store;listener=changed;if(!preferences.contains("epoch"))preferences.edit().putString("epoch",java.util.UUID.randomUUID().toString()).apply();photos.prune(days(),maximum());}
  private int days(){int value=preferences.getInt("days",30);return PhotoPolicy.limits(value,30)?value:30;}
  private int maximum(){int value=preferences.getInt("maximum",30);return Math.max(5,Math.min(50,value));}
  private void notifyChange(){main.post(()->listener.changed());}
  boolean configure(int days,int maximum){if(!PhotoPolicy.limits(days,maximum))return false;preferences.edit().putInt("days",days).putInt("maximum",maximum).apply();photos.prune(days,maximum);notifyChange();return true;}
  boolean exclude(String id,boolean value){boolean saved=photos.exclude(id,value);if(saved){photos.prune(days(),maximum());notifyChange();}return saved;}
  boolean restoreExcluded(){boolean saved=photos.restoreExcluded();if(saved){photos.prune(days(),maximum());notifyChange();}return saved;}
  int capacity(){return maximum();}
  void libraryChanged(){photos.prune(days(),maximum());notifyChange();}
  private int interval(){int value=preferences.getInt("interval",86400);return MailImportPolicy.interval(value)?value:86400;}
  synchronized boolean delivery(String raw){if(busy)return false;try{JSONObject row=new JSONObject(raw);int seconds=row.getInt("interval");JSONArray addresses=row.getJSONArray("senders");if(!MailImportPolicy.interval(seconds)||addresses.length()>50)return false;JSONArray clean=new JSONArray();HashSet<String> unique=new HashSet<>();for(int i=0;i<addresses.length();i++){String value=MailImportPolicy.address(addresses.getString(i));if(value.isEmpty())return false;if(unique.add(value))clean.put(value);}boolean trusted=row.getBoolean("trusted");if(trusted&&clean.length()==0)return false;boolean saved=preferences.edit().putInt("interval",seconds).putBoolean("trusted",trusted).putString("senders",clean.toString()).commit();if(saved)notifyChange();return saved;}catch(Exception ignored){return false;}}
  String deliverySettings(){try{return new JSONObject().put("interval",interval()).put("trusted",preferences.getBoolean("trusted",false)).put("senders",new JSONArray(preferences.getString("senders","[]"))).toString();}catch(Exception ignored){return "{}";}}
  synchronized boolean eraseCache(){if(busy)return false;photos.clear();preferences.edit().putString("epoch",java.util.UUID.randomUUID().toString()).apply();notifyChange();return true;}
  synchronized boolean connect(String email,String password){if(busy)return false;String account=email==null?"":email.trim().toLowerCase(java.util.Locale.ROOT),secret=password==null?"":password.replace(" ","");if(!PhotoPolicy.gmail(account)||secret.length()!=16)return false;try{String sealed=MailSecret.seal(secret,account);String previous=preferences.getString("email","");if(!preferences.edit().putString("email",account).putString("secret",sealed).remove("lastSync").commit())return false;if(!account.equals(previous)){photos.clearImported();preferences.edit().putString("epoch",java.util.UUID.randomUUID().toString()).putBoolean("trusted",false).putString("senders","[]").remove("lastAttempt").remove("failures").apply();}error="";notifyChange();sync();return true;}catch(Exception ignored){error="Could not protect the app password on this device.";notifyChange();return false;}}
  synchronized boolean disconnect(){if(busy)return false;preferences.edit().remove("email").remove("secret").remove("lastSync").remove("lastAttempt").remove("failures").remove("senders").remove("trusted").putString("epoch",java.util.UUID.randomUUID().toString()).commit();try{MailSecret.forget();}catch(Exception ignored){}photos.clear();error="";notifyChange();return true;}
  JSONObject status(){JSONObject row=new JSONObject();try{row.put("connected",preferences.contains("secret"));row.put("email",preferences.getString("email",""));row.put("days",days());row.put("maximum",maximum());row.put("lastSync",preferences.getLong("lastSync",0));row.put("busy",busy);row.put("epoch",preferences.getString("epoch",""));row.put("interval",interval());row.put("imported",busy?imported:preferences.getInt("imported",0));row.put("visited",visited);row.put("skipped",busy?skipped:preferences.getInt("skipped",0));row.put("trusted",preferences.getBoolean("trusted",false));row.put("error",error);row.put("photos",photos.list());row.put("excluded",photos.excluded());}catch(Exception ignored){}return row;}
  void maybeSync(){if(preferences.contains("secret")&&MailImportPolicy.due(preferences.getLong("lastSync",0),preferences.getLong("lastAttempt",0),preferences.getInt("failures",0),System.currentTimeMillis(),interval()))sync();}
  synchronized void sync(){if(busy||!preferences.contains("secret"))return;busy=true;error="";visited=0;imported=0;skipped=0;preferences.edit().putLong("lastAttempt",System.currentTimeMillis()).apply();notifyChange();worker.execute(()->{
    Store store=null;Folder folder=null;
    try{
      String account=preferences.getString("email",""),sealed=preferences.getString("secret","");String password=MailSecret.open(sealed,account);
      Properties p=new Properties();p.setProperty("mail.store.protocol","imaps");p.setProperty("mail.imaps.host","imap.gmail.com");p.setProperty("mail.imaps.port","993");p.setProperty("mail.imaps.ssl.enable","true");p.setProperty("mail.imaps.ssl.checkserveridentity","true");p.setProperty("mail.imaps.connectiontimeout","15000");p.setProperty("mail.imaps.timeout","20000");p.setProperty("mail.imaps.writetimeout","20000");
      Session session=Session.getInstance(p);store=new IMAPSSLStore(session,null);store.connect("imap.gmail.com",account,password);
      folder=store.getFolder("INBOX");folder.open(Folder.READ_ONLY);
      int window=days();long cutoff=window==0?0:System.currentTimeMillis()-(long)window*86400000L;int count=folder.getMessageCount();Message[] messages=window==0?(count==0?new Message[0]:folder.getMessages(Math.max(1,count-999),count)):folder.search(new ReceivedDateTerm(ComparisonTerm.GE,new Date(cutoff)));
      final boolean trusted=preferences.getBoolean("trusted",false);HashSet<String> approved=new HashSet<>();JSONArray senders=new JSONArray(preferences.getString("senders","[]"));for(int n=0;n<senders.length();n++)approved.add(senders.getString(n));
      int attachments=0;for(int i=messages.length-1;i>=0&&visited<1000&&attachments<100;i--,visited++){
        Message message=messages[i];Date received=message.getReceivedDate();if(received==null||received.getTime()<cutoff)continue;
        Address[] rawFrom=message.getFrom();String[] from=rawFrom==null?null:new String[rawFrom.length];if(from!=null)for(int n=0;n<rawFrom.length;n++)from[n]=rawFrom[n] instanceof InternetAddress?((InternetAddress)rawFrom[n]).getAddress():"";
        if(!MailImportPolicy.allowed(trusted,approved,from)){skipped++;continue;}
        attachments+=MailParts.collect(message,received.getTime(),100-attachments,(input,at)->{if(photos.add(input,at)){imported++;notifyChange();}photos.prune(days(),maximum());});
      }
      photos.prune(days(),maximum());preferences.edit().putLong("lastSync",System.currentTimeMillis()).putInt("failures",0).putInt("imported",imported).putInt("skipped",skipped).apply();error="";
    }catch(AuthenticationFailedException e){error="Sign-in failed. Check the account and its app password.";}
    catch(Exception e){error="Could not refresh email photos. Check Wi-Fi and try again.";}
    finally{if(!error.isEmpty())preferences.edit().putInt("failures",Math.min(10,preferences.getInt("failures",0)+1)).apply();try{if(folder!=null&&folder.isOpen())folder.close(false);}catch(Exception ignored){}try{if(store!=null)store.close();}catch(Exception ignored){}photos.prune(days(),maximum());busy=false;notifyChange();}
  });}
  void close(){worker.shutdownNow();}
}
