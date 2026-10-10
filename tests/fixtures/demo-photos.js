/* Synthetic public preview only. This file is never included in an APK. */
(() => {
  const allNames=['marigolds','dog','cat','lake','orchard'];
  const requested=Number(new URLSearchParams(location.search).get('count'));
  const names=Number.isInteger(requested)&&requested>=1&&requested<=allNames.length?allNames.slice(0,requested):allNames;
  const photos=names.map((name,index)=>({url:'demo-photos/'+name+'.png',at:Date.now()-index*86400000}));
  const normalize=window.SkylitPhotoModel.normalize;
  window.SkylitPhotoModel.normalize=raw=>{
    const base=normalize(raw);let parsed={};try{parsed=typeof raw==='string'?JSON.parse(raw):raw||{}}catch(_){}
    const safe=Array.isArray(parsed.photos)?parsed.photos.filter(photo=>photo&&names.some(name=>photo.url==='demo-photos/'+name+'.png')):[];
    return Object.assign(base,{photos:safe});
  };
  Object.assign(window.Skylit,{
    photoStatus:()=>JSON.stringify({connected:true,email:'demo@example.invalid',days:30,maximum:30,lastSync:Date.now(),busy:false,error:'',photos}),
    photoSource(){},photoRefresh(){},photoConfigure(){return true},
    photoOpen(idle){setTimeout(()=>window.SkylitPhotos.open(idle),0)},
    photoBrowse(index){setTimeout(()=>window.SkylitPhotos.open(false,index,false),0)},
    localPhotoClosed(){}
  });
})();
