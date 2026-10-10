package com.wesbos.homehq;

import java.io.InputStream;
import javax.mail.Multipart;
import javax.mail.Part;
import javax.mail.internet.MimeMultipart;

/** Walks MIME parts without persisting message text or headers. */
final class MailParts {
  interface ImageSink {void accept(InputStream input,long received) throws Exception;}
  private MailParts(){}
  static int collect(Part part,long received,int remaining,ImageSink sink) throws Exception {
    if(remaining<=0)return 0;
    if(part.isMimeType("multipart/*")){
      Multipart multipart=new MimeMultipart(part.getDataHandler().getDataSource());
      int scanned=0;
      for(int i=0;i<multipart.getCount()&&scanned<remaining;i++)scanned+=collect(multipart.getBodyPart(i),received,remaining-scanned,sink);
      return scanned;
    }
    if(!(part.isMimeType("image/jpeg")||part.isMimeType("image/png")||part.isMimeType("image/webp")||part.isMimeType("image/heic")))return 0;
    if(part.getSize()>PhotoPolicy.MAX_DOWNLOAD)return 0;
    try(InputStream input=part.getInputStream()){sink.accept(input,received);}catch(IllegalArgumentException ignored){return 0;}
    return 1;
  }
}
