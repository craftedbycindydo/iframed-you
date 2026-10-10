package com.wesbos.homehq;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import org.json.JSONObject;
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
  PhotoMail(Context context,PhotoStore store,Listener changed){preferences=context.getSharedPreferences("skylit-photo-mail",Context.MODE_PRIVATE);photos=store;listener=changed;photos.prune(days(),maximum());}
  private int days(){int value=preferences.getInt("days",30);return value==90?90:30;}
  private int maximum(){int value=preferences.getInt("maximum",30);return Math.max(5,Math.min(50,value));}
  private void notifyChange(){main.post(()->listener.changed());}
  boolean configure(int days,int maximum){if(!PhotoPolicy.limits(days,maximum))return false;preferences.edit().putInt("days",days).putInt("maximum",maximum).apply();photos.prune(days,maximum);notifyChange();return true;}
  synchronized boolean connect(String email,String password){if(busy)return false;String account=email==null?"":email.trim().toLowerCase(java.util.Locale.ROOT),secret=password==null?"":password.replace(" ","");if(!PhotoPolicy.gmail(account)||secret.length()!=16)return false;try{String sealed=MailSecret.seal(secret,account);String previous=preferences.getString("email","");if(!preferences.edit().putString("email",account).putString("secret",sealed).remove("lastSync").commit())return false;if(!account.equals(previous))photos.clear();error="";notifyChange();sync();return true;}catch(Exception ignored){error="Could not protect the app password on this device.";notifyChange();return false;}}
  synchronized boolean disconnect(){if(busy)return false;preferences.edit().remove("email").remove("secret").remove("lastSync").commit();try{MailSecret.forget();}catch(Exception ignored){}photos.clear();error="";notifyChange();return true;}
  JSONObject status(){JSONObject row=new JSONObject();try{row.put("connected",preferences.contains("secret"));row.put("email",preferences.getString("email",""));row.put("days",days());row.put("maximum",maximum());row.put("lastSync",preferences.getLong("lastSync",0));row.put("busy",busy);row.put("error",error);row.put("photos",photos.list());}catch(Exception ignored){}return row;}
  void maybeSync(){if(preferences.contains("secret")&&System.currentTimeMillis()-preferences.getLong("lastSync",0)>=24*60*60*1000L)sync();}
  synchronized void sync(){if(busy||!preferences.contains("secret"))return;busy=true;error="";notifyChange();worker.execute(()->{
    Store store=null;Folder folder=null;
    try{
      String account=preferences.getString("email",""),sealed=preferences.getString("secret","");String password=MailSecret.open(sealed,account);
      Properties p=new Properties();p.setProperty("mail.store.protocol","imaps");p.setProperty("mail.imaps.host","imap.gmail.com");p.setProperty("mail.imaps.port","993");p.setProperty("mail.imaps.ssl.enable","true");p.setProperty("mail.imaps.ssl.checkserveridentity","true");p.setProperty("mail.imaps.connectiontimeout","15000");p.setProperty("mail.imaps.timeout","20000");p.setProperty("mail.imaps.writetimeout","20000");
      Session session=Session.getInstance(p);store=new IMAPSSLStore(session,null);store.connect("imap.gmail.com",account,password);
      folder=store.getFolder("INBOX");folder.open(Folder.READ_ONLY);
      long cutoff=System.currentTimeMillis()-(long)days()*86400000L;Message[] messages=folder.search(new ReceivedDateTerm(ComparisonTerm.GE,new Date(cutoff)));
      int attachments=0,visited=0;for(int i=messages.length-1;i>=0&&visited<1000&&attachments<100;i--,visited++){
        Message message=messages[i];Date received=message.getReceivedDate();if(received==null||received.getTime()<cutoff)continue;
        attachments+=MailParts.collect(message,received.getTime(),100-attachments,(input,at)->{photos.add(input,at);photos.prune(days(),maximum());});
      }
      photos.prune(days(),maximum());preferences.edit().putLong("lastSync",System.currentTimeMillis()).apply();error="";
    }catch(AuthenticationFailedException e){error="Sign-in failed. Check the account and its app password.";}
    catch(Exception e){error="Could not refresh email photos. Check Wi-Fi and try again.";}
    finally{try{if(folder!=null&&folder.isOpen())folder.close(false);}catch(Exception ignored){}try{if(store!=null)store.close();}catch(Exception ignored){}photos.prune(days(),maximum());busy=false;notifyChange();}
  });}
  void close(){worker.shutdownNow();}
}
