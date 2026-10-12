(function(root,factory){if(typeof module==='object'&&module.exports)module.exports=factory();else root.SkylitOverview=factory();})(typeof globalThis==='object'?globalThis:this,function(){
'use strict';
function upcoming(events,today,now,limit=5){return events.filter(e=>e.allDay?e.endDay>today:e.end>now).sort((a,b)=>a.startDay.localeCompare(b.startDay)||Number(!!b.allDay)-Number(!!a.allDay)||a.start-b.start).slice(0,limit);}
function weather(data,now=Date.now()){if(!data||!data.current||!Number.isFinite(data.current.temperature_2m))return null;return {temperature:Math.round(data.current.temperature_2m),code:data.current.weather_code,stale:!data.fetchedAt||now-data.fetchedAt>30*60000,fetchedAt:data.fetchedAt};}
function fitting(bottoms,limit){let shown=0;while(shown<bottoms.length&&bottoms[shown]<=limit+.5)shown++;return shown;}
return {upcoming,weather,fitting};
});
