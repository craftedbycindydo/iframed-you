package com.wesbos.homehq;

import java.util.Locale;
import java.util.Set;

/** Pure scheduling and exact-address policy; no message or credential persistence. */
final class MailImportPolicy {
  private MailImportPolicy(){}
  static boolean interval(int seconds){return seconds==900||seconds==3600||seconds==86400;}
  static String address(String value){if(value==null)return "";String address=value.trim().toLowerCase(Locale.ROOT);return address.length()<=254&&address.matches("[^\\s@<>]+@[^\\s@<>]+\\.[^\\s@<>]+")?address:"";}
  static boolean allowed(boolean enabled,Set<String> approved,String[] from){if(!enabled)return true;if(from==null||from.length==0)return false;for(String sender:from){String value=address(sender);if(value.isEmpty()||!approved.contains(value))return false;}return true;}
  static long backoff(int failures){return Math.min(3600000L,300000L*(1L<<Math.min(4,Math.max(0,failures-1))));}
  static boolean due(long success,long attempt,int failures,long now,int seconds){if(!PhotoPolicy.clockSet(now))return false;if(!interval(seconds))seconds=86400;if(attempt>0&&failures>0&&attempt<=now+300000L&&now-attempt<backoff(failures))return false;return success<=0||success>now+300000L||now-success>=seconds*1000L;}
}
