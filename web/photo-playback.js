'use strict';
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.SkylitPhotoPlayback=api;})(typeof window!=='undefined'?window:globalThis,function(){
  const styles=['fade','stack','collage'];
  function style(value){return styles.includes(value)?value:'fade';}
  function collage(index,count){if(!Number.isInteger(count)||count<1)return [];return [0,1,2].map(offset=>(index+offset)%count);}
  function angle(index){return [-5,4,-3,6,-2][Math.abs(index)%5];}
  return {styles,style,collage,angle};
});
