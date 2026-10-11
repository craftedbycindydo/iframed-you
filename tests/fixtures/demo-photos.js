/* Synthetic public preview only. This file is never included in an APK. */
(() => {
  const allNames=['marigolds','dog','cat','lake','orchard'];
  const requested=Number(new URLSearchParams(location.search).get('count'));
  const names=Number.isInteger(requested)&&requested>=1&&requested<=allNames.length?allNames.slice(0,requested):allNames;
  const photos=names.map((name,index)=>({id:String(index+1).padStart(64,'0'),url:'demo-photos/'+name+'.png',at:Date.now()-index*86400000}));
  const excluded=new Set(JSON.parse(localStorage.getItem('demo.photoExclusions')||'[]'));let days=Number(localStorage.getItem('demo.photoDays')||30),maximum=Number(localStorage.getItem('demo.photoMaximum')||30);
  const normalize=window.SkylitPhotoModel.normalize;
  window.SkylitPhotoModel.normalize=raw=>{
    const base=normalize(raw);let parsed={};try{parsed=typeof raw==='string'?JSON.parse(raw):raw||{}}catch(_){}
    const safe=Array.isArray(parsed.photos)?parsed.photos.filter(photo=>photo&&names.some(name=>photo.url==='demo-photos/'+name+'.png')):[];
    return Object.assign(base,{photos:safe});
  };
  window.SkylitDemoPhotos={photos};
  Object.assign(window.Skylit,{
    photoStatus:()=>JSON.stringify({epoch:'synthetic-cache',connected:true,email:'demo@example.invalid',days,maximum,excluded:Array.from(excluded),lastSync:Date.now(),busy:false,error:'',photos}),
    photoDeliverySettings:()=>JSON.stringify({interval:3600,trusted:false,senders:[]}),photoDelivery(){return true;},configureQuiet(){},privacyPause(){},ambientClosed(){},
    photoSource(){},photoRefresh(){},photoConfigure(window,limit){days=window;maximum=limit;localStorage.setItem('demo.photoDays',String(days));localStorage.setItem('demo.photoMaximum',String(maximum));return true},photoExclude(id,value){value?excluded.add(id):excluded.delete(id);localStorage.setItem('demo.photoExclusions',JSON.stringify(Array.from(excluded)));return true},photoRestoreExcluded(){excluded.clear();localStorage.removeItem('demo.photoExclusions');return true},
    photoOpen(idle){setTimeout(()=>window.SkylitPhotos.open(idle),0)},
    photoBrowse(index){setTimeout(()=>window.SkylitPhotos.open(false,index,false),0)},
    localPhotoClosed(){}
  });
})();
