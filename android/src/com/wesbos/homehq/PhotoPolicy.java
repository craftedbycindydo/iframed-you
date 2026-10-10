package com.wesbos.homehq;

/** Side-effect-free limits shared by mail import and private photo storage. */
final class PhotoPolicy {
  static final int MAX_DOWNLOAD=12*1024*1024,MAX_JPEG=4*1024*1024;
  private PhotoPolicy(){}
  static boolean gmail(String email){return email!=null&&(email.matches("[^\\s@]+@gmail\\.com")||email.matches("[^\\s@]+@googlemail\\.com"));}
  static boolean limits(int days,int maximum){return (days==30||days==90)&&maximum>=5&&maximum<=50;}
  static boolean imageSize(int width,int height){return width>=320&&height>=240&&width<=20000&&height<=20000;}
  static int sampleSize(int width,int height){int sample=1;while(Math.max(width,height)/sample>2400||(long)(width/sample)*(height/sample)>10000000L)sample*=2;return sample;}
  static boolean retain(long received,long now,int days){return received>=now-(long)days*86400000L&&received<=now+86400000L;}
  static boolean photoId(String id){return id!=null&&id.matches("[a-f0-9]{64}");}
}
