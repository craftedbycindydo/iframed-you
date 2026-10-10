'use strict';
// Calendar rules are independent of rendering so local midnight and DST can be tested.
(function(root){
  const dayHats=['beret','beanie','bucket','cap','party','crown','flower','headphones','bow','nightcap','wizard'];
  function at(epoch,timezone='America/Toronto'){
    let parts;
    try{parts=new Intl.DateTimeFormat('en-CA',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',hourCycle:'h23'}).formatToParts(new Date(epoch));}
    catch(_){timezone='America/Toronto';parts=new Intl.DateTimeFormat('en-CA',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',hourCycle:'h23'}).formatToParts(new Date(epoch));}
    const p=Object.fromEntries(parts.map(p=>[p.type,p.value]));
    const ordinal=Math.floor(Date.UTC(Number(p.year),Number(p.month)-1,Number(p.day))/86400000);
    const hour=Number(p.hour);
    return {date:p.year+'-'+p.month+'-'+p.day,hour,timezone,period:hour>=22||hour<6?'night':hour<9?'morning':hour>=20?'evening':'day',dailyHat:dayHats[((ordinal%dayHats.length)+dayHats.length)%dayHats.length]};
  }
  function idle(period,quietFor,random=Math.random()){
    const pool=period==='night'?['sleepy']:period==='morning'?['yawn','stretch','yawn','curious']:period==='evening'?['yawn','sleepy','stretch']:quietFor>45000?['sleepy']:['curious','wink','delighted','stretch','sneeze','dance','peek','proud','puzzled'];
    return pool[Math.min(pool.length-1,Math.floor(Math.max(0,random)*pool.length))];
  }
  const api={at,idle};if(typeof module!=='undefined'&&module.exports)module.exports=api;else root.MomoRoutine=api;
})(typeof window!=='undefined'?window:globalThis);
