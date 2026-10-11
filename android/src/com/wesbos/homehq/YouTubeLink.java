package com.wesbos.homehq;

import java.net.URI;

/** Owner-entered video/playlist links only, independently checked at the bridge. */
final class YouTubeLink {
  private YouTubeLink(){}
  static boolean valid(String value){try{URI u=new URI(value);String host=u.getHost(),query=u.getRawQuery();if(!"https".equals(u.getScheme())||!("www.youtube.com".equals(host)||"m.youtube.com".equals(host)||"youtube.com".equals(host))||u.getPort()!=-1||u.getUserInfo()!=null||u.getFragment()!=null||query==null)return false;return "/watch".equals(u.getPath())&&query.matches("v=[A-Za-z0-9_-]{11}")||"/playlist".equals(u.getPath())&&query.matches("list=[A-Za-z0-9_-]{10,100}");}catch(Exception ignored){return false;}}
}
