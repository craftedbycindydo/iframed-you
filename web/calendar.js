'use strict';
(() => {
const $=id=>document.getElementById(id),bridge=window.Skylit;
const available=!!(bridge&&bridge.calendarList);
let sources=[],events=[],overviewEvents=[],allEvents=[],allOverviewEvents=[],errors=new Map(),busy=new Set(),revision=0;
const gateModel=SkylitCalendarPolicy,gateKey='skylit.calendarGate';
let gate=(()=>{try{return gateModel.clean(JSON.parse(localStorage.getItem(gateKey)||'{}'));}catch(e){return gateModel.clean({});}})();
function saveGate(){try{localStorage.setItem(gateKey,JSON.stringify(gate));}catch(e){gateMessage('Could not save inviter settings on this frame.');}}
function gateMessage(message){$('calendar-gate-status').textContent=message;}
function applyGate(){events=allEvents.filter(e=>gateModel.allowed(e,gate));overviewEvents=allOverviewEvents.filter(e=>gateModel.allowed(e,gate));paint();}
const prefs=()=>window.SkylitApp.calendarPreferences();
const day=(date)=>{const p={};new Intl.DateTimeFormat('en-CA',{timeZone:prefs().timezone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date).forEach(x=>p[x.type]=x.value);return p.year+'-'+p.month+'-'+p.day;};
const today=()=>day(new Date());
const addDays=(key,n)=>{const d=new Date(key+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
let selected=today(),month=selected.slice(0,7),activeZone=prefs().timezone,lastToday=today();
const label=(key,options)=>new Intl.DateTimeFormat('en-CA',Object.assign({timeZone:'UTC'},options)).format(new Date(key+'T12:00:00Z'));
function node(tag,text,cls){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;}
function range(){const first=month+'-01';const start=addDays(first,-new Date(first+'T12:00:00Z').getUTCDay());return {from:start,to:addDays(start,70),zone:prefs().timezone};}
function parse(body,bounds){return new Promise((resolve,reject)=>{let worker;const fail=()=>{if(worker)worker.terminate();clearTimeout(timeout);reject(Error('Calendar could not be read.'))};const timeout=setTimeout(fail,6000);try{worker=new Worker('calendar-worker.js');worker.onerror=fail;worker.onmessage=e=>{worker.terminate();clearTimeout(timeout);if(e.data.error)reject(Error(e.data.error));else resolve(e.data.events)};worker.postMessage(Object.assign({body},bounds));}catch(e){fail()}});}
function read(){try{sources=JSON.parse(bridge.calendarList());}catch(e){sources=[];}}
function settings(){
  const list=$('calendar-sources');list.textContent='';
  for(const s of sources){const row=node('div',undefined,'cal-source');const text=node('div');const title=node('strong',s.name);title.style.borderLeft='5px solid '+s.color;title.style.paddingLeft='10px';text.append(title);text.append(node('p',errors.get(s.id)||(busy.has(s.id)?'Checking calendar…':s.fetchedAt?'Connected · '+new Intl.DateTimeFormat('en-CA',{timeZone:prefs().timezone,dateStyle:'medium',timeStyle:'short',hour12:prefs().clock==='12'}).format(new Date(s.fetchedAt)):'Waiting for first connection'),'tiny'));const remove=node('button','Remove','quiet');remove.setAttribute('aria-label','Remove '+s.name);remove.onclick=()=>{if(remove.dataset.confirm!=='yes'){remove.dataset.confirm='yes';remove.textContent='Tap to confirm';return;}if(!bridge.calendarRemove(s.id)){formMessage('Could not remove this calendar. Try again.');return;}errors.delete(s.id);busy.delete(s.id);formMessage('Calendar removed from this frame.');allEvents=allEvents.filter(e=>e.source!==s.id);allOverviewEvents=allOverviewEvents.filter(e=>e.source!==s.id);read();applyGate();render();};row.append(text,remove);list.append(row);}
  $('calendar-add').disabled=!available||sources.length>=6;
  if(!available)formMessage('Connect calendars on the frame. This browser preview does not store private links.');
}
function formMessage(text){$('calendar-form-status').textContent=text;}
function status(){let overviewText='';
  let text='Connect a calendar to bring your plans here.';
  if(sources.length){const times=sources.map(s=>s.fetchedAt||0);const last=Math.min(...times);const age=Date.now()-last;const failures=errors.size;overviewText=!navigator.onLine?'Offline · Showing saved events.':failures?'Some calendars could not update · Saved events shown where available.':!last?'Waiting for your first calendar update.':age>30*60000?'Saved events · Waiting for a fresh update.':'';
    text=busy.size?'Refreshing your calendars…':!navigator.onLine?'Offline · Showing saved events.':failures?'Some calendars could not update · Saved events shown where available.':!last?'Waiting for your first calendar update.':age>30*60000?'Saved events · Waiting for a fresh update.':'Up to date';
    if(last)text+=' · Last refreshed '+new Intl.DateTimeFormat('en-CA',{timeZone:prefs().timezone,month:'short',day:'numeric',hour:'numeric',minute:'2-digit',hour12:prefs().clock==='12'}).format(new Date(last));
  }
  $('calendar-status').textContent=text;$('overview-calendar-status').textContent=overviewText;
  $('calendar-refresh').disabled=!available||!sources.length||busy.size>0;
}
function onDay(e,key){return e.startDay<=key&&(e.allDay?e.endDay>key:e.endDay>=key);}
function time(e){if(e.allDay)return 'All day';return new Intl.DateTimeFormat('en-CA',{timeZone:prefs().timezone,hour:'numeric',minute:'2-digit',hour12:prefs().clock==='12'}).format(new Date(e.start));}
function paintGate(){
  $('calendar-gate-enable').checked=gate.enabled;$('calendar-unattributed').checked=gate.unattributed;
  if(document.activeElement!==$('calendar-owner'))$('calendar-owner').value=gate.owner;
  const approved=$('calendar-approved');approved.textContent='';
  for(const address of gate.approved){const row=node('div',undefined,'cal-inviter-row');row.append(node('span',address));const remove=node('button','Remove','quiet');remove.setAttribute('aria-label','Remove approved inviter '+address);remove.onclick=()=>{gate=gateModel.revoke(gate,address);saveGate();applyGate();};row.append(remove);approved.append(row);}
  if(!gate.approved.length)approved.append(node('p','No approved inviters yet.','subtle small'));
  const byKey=new Map();for(const e of allEvents.concat(allOverviewEvents)){const key=e.source+'/'+e.key;if(!byKey.has(key))byKey.set(key,e);}
  const waiting=gateModel.pending([...byKey.values()],gate),host=$('calendar-pending');host.textContent='';
  const waitingCount=waiting.reduce((sum,item)=>sum+item.count,0);
  $('calendar-pending-count').textContent=String(waitingCount);
  $('calendar-review').textContent=waitingCount?'Review inviters · '+waitingCount:'Review inviters';
  for(const item of waiting){const row=node('div',undefined,'cal-inviter-row');row.append(node('span',(item.address||'Organizer not provided')+' · '+item.count+' event'+(item.count===1?'':'s')));if(item.address){const approve=node('button','Show events','secondary');approve.setAttribute('aria-label','Show events from '+item.address);approve.onclick=()=>{gate=gateModel.approve(gate,item.address);saveGate();gateMessage('Inviter approved on this frame.');applyGate();};row.append(approve);}host.append(row);}
  if(!waiting.length)host.append(node('p',gate.enabled?'No invitations waiting in the loaded dates.':'Turn on review to screen new inviters.','subtle small'));
}
function paint(){
  $('calendar-empty').hidden=sources.length>0;$('calendar-content').hidden=!sources.length;
  const legend=$('calendar-legend');legend.textContent='';for(const s of sources){const pill=node('span',undefined,'cal-calendar-pill');const dot=node('i');dot.style.background=s.color;pill.append(dot,document.createTextNode(s.name));legend.append(pill);}
  $('calendar-month-title').textContent=label(month+'-01',{month:'long',year:'numeric'});
  const grid=$('calendar-grid');grid.textContent='';const first=month+'-01';const offset=new Date(first+'T12:00:00Z').getUTCDay();const begin=addDays(first,-offset);
  for(let i=0;i<42;i++){const key=addDays(begin,i),items=events.filter(e=>onDay(e,key));const b=node('button',undefined,'cal-day');b.classList.toggle('outside',!key.startsWith(month));b.classList.toggle('today',key===today());b.setAttribute('aria-pressed',String(key===selected));b.setAttribute('aria-label',label(key,{weekday:'long',month:'long',day:'numeric'})+', '+items.length+' events');b.append(node('span',String(Number(key.slice(-2))),'cal-day-number'));for(const e of items.slice(0,1)){const chip=node('span',e.title,'cal-chip');chip.style.borderLeftColor=e.color;b.append(chip);}if(items.length>1)b.append(node('span','+'+(items.length-1),'cal-more'));b.onclick=()=>{selected=key;if(key.slice(0,7)!==month){month=key.slice(0,7);render()}else paint()};grid.append(b);}
  $('calendar-agenda-title').textContent=selected===today()?'From today':label(selected,{month:'short',day:'numeric'})+' onwards';
  const agenda=$('calendar-agenda');agenda.textContent='';let count=0;
  for(let i=0;i<14;i++){const key=addDays(selected,i),items=events.filter(e=>onDay(e,key));if(!items.length&&i!==0)continue;const group=node('div',undefined,'cal-agenda-day');group.append(node('h3',key===today()?'Today · '+label(key,{month:'short',day:'numeric'}):label(key,{weekday:'short',month:'short',day:'numeric'})));
    if(!items.length)group.append(node('p','No events.','subtle small'));
    for(const e of items){if(count++>=100)break;const detail=node('details',undefined,'cal-event');detail.style.borderLeftColor=e.color;const summary=node('summary');summary.append(node('span',time(e),'cal-event-time'),node('strong',e.title));detail.append(summary);detail.append(node('p',e.name,'tiny'));if(e.location)detail.append(node('p',e.location,'small'));if(!e.allDay)detail.append(node('p',new Intl.DateTimeFormat('en-CA',{timeZone:prefs().timezone,dateStyle:'medium',timeStyle:'short',hour12:prefs().clock==='12'}).format(new Date(e.start))+' – '+new Intl.DateTimeFormat('en-CA',{timeZone:prefs().timezone,dateStyle:'medium',timeStyle:'short',hour12:prefs().clock==='12'}).format(new Date(e.end)),'small'));if(e.description)detail.append(node('p',e.description,'cal-description small'));group.append(detail);}
    agenda.append(group);if(count>=100)break;
  }
  if(!count)agenda.append(node('p',sources.some(s=>!s.fetchedAt)?'Events will appear after the first successful connection.':'No plans in the next two weeks.','subtle small'));
  status();settings();paintOverview();paintGate();
}
function paintOverview(){
 const host=$('overview-events');host.textContent='';const day=today(),list=SkylitOverview.upcoming(overviewEvents,day,Date.now(),5);let key=null,group;
 for(const e of list){
  const groupKey=e.startDay<day?'ongoing':e.startDay;
  if(groupKey!==key){key=groupKey;group=node('section',undefined,'overview-event-group');group.append(node('h3',key==='ongoing'?'Ongoing':key===day?'Today':key===addDays(day,1)?'Tomorrow':label(key,{weekday:'short',month:'short',day:'numeric'})));host.append(group);}
  const row=node('div',undefined,'overview-event'),when=node('time',time(e)),content=node('div');
  content.append(node('strong',e.title));if(sources.length>1)content.append(node('small',e.name));
  row.append(when,content);group.append(row);
 }
 if(!list.length)host.append(node('p',!sources.length?'Add a calendar to see upcoming events.':sources.some(s=>!s.fetchedAt)?'Waiting for the first calendar update.':'No upcoming events in the next two weeks.','subtle'));
}
async function render(){
 const version=++revision,bounds=range(),snapshot=sources.slice(),upcoming={from:today(),to:addDays(today(),14),zone:prefs().timezone};
 const result=[],overview=[],failures=[];
 for(const s of snapshot){if(!s.body)continue;try{
  const list=await parse(s.body,bounds);
  const next=bounds.from<=upcoming.from&&bounds.to>=upcoming.to?list:await parse(s.body,upcoming);
  const annotate=e=>Object.assign({},e,{source:s.id,name:s.name,color:s.color});
  result.push(...list.map(annotate));overview.push(...next.filter(e=>e.startDay<upcoming.to).map(annotate));
 }catch(e){failures.push(s.id);}}
 if(version!==revision)return;
 failures.forEach(id=>errors.set(id,'Could not read saved events. Try refreshing.'));
 allEvents=result.sort((a,b)=>a.startDay.localeCompare(b.startDay)||Number(b.allDay)-Number(a.allDay)||a.start-b.start);allOverviewEvents=overview;applyGate();
}
async function receive(message){const s=sources.find(s=>s.id===message.id);if(!s)return;if(message.error){busy.delete(s.id);errors.set(s.id,message.error);formMessage('Connection failed. Check Wi-Fi, or remove the calendar and add its current private link.');paint();return;}try{await parse(message.body,range());if(!sources.some(x=>x.id===s.id)){bridge.calendarAccept(s.id,message.request,false);return;}if(!bridge.calendarAccept(s.id,message.request,true))throw Error('Save failed');read();errors.delete(s.id);formMessage('Calendar connected. Your events are ready in the Calendar tab.');}catch(e){bridge.calendarAccept(s.id,message.request,false);errors.set(s.id,'Could not read or save this feed. Previous events kept.');formMessage('This feed could not be read. Any previously saved events are still available.');}finally{busy.delete(s.id);render();}}
function refresh(){if(!available)return;for(const s of sources)if(!busy.has(s.id)){busy.add(s.id);bridge.calendarRefresh(s.id)}status();settings();}
function setup(){window.SkylitApp.go('settings');$('calendar-settings').scrollIntoView({block:'start'});}
$('calendar-setup').onclick=setup;$('calendar-connect').onclick=setup;$('calendar-refresh').onclick=refresh;
$('calendar-review').onclick=()=>{const panel=$('calendar-inviters');panel.open=true;panel.scrollIntoView({block:'start'});};
$('calendar-owner').onchange=()=>{const address=gateModel.email($('calendar-owner').value);if(!address){gateMessage('Enter a valid calendar account email.');return;}gate.owner=address;saveGate();gateMessage('Calendar account saved on this frame.');applyGate();};
$('calendar-gate-enable').onchange=()=>{if($('calendar-gate-enable').checked&&!gate.owner){$('calendar-gate-enable').checked=false;gateMessage('Enter the calendar account email first, so its own events stay visible.');return;}gate.enabled=$('calendar-gate-enable').checked;saveGate();gateMessage(gate.enabled?'Inviter review is on. Events from other organizers wait below.':'Inviter review is off. All calendar events are visible.');applyGate();};
$('calendar-unattributed').onchange=()=>{gate.unattributed=$('calendar-unattributed').checked;saveGate();applyGate();};
$('calendar-approve-form').onsubmit=e=>{e.preventDefault();const input=$('calendar-approve-email'),address=gateModel.email(input.value);if(!address){gateMessage('Enter a valid email address.');return;}if(gate.approved.length>=gateModel.MAX_SENDERS){gateMessage('The approved list is full. Remove an address first.');return;}gate=gateModel.approve(gate,address);input.value='';saveGate();gateMessage('Inviter approved on this frame.');applyGate();};
$('calendar-today').onclick=()=>{selected=today();month=selected.slice(0,7);render()};
function move(delta){const date=new Date(month+'-01T12:00:00Z');date.setUTCMonth(date.getUTCMonth()+delta);month=date.toISOString().slice(0,7);selected=month+'-01';render();}
$('calendar-prev').onclick=()=>move(-1);$('calendar-next').onclick=()=>move(1);
$('calendar-form').onsubmit=e=>{e.preventDefault();if(!available)return;const input=$('calendar-feed');const id=bridge.calendarAdd($('calendar-name').value,$('calendar-color').value,input.value.trim());input.value='';if(!id){formMessage('Use the Google iCal address ending in basic.ics. Check for a duplicate calendar or the six-calendar limit.');return;}formMessage('Saved privately. Checking the connection…');$('calendar-name').value='';read();paint();refresh();};
window.SkylitCalendar={receive};
window.addEventListener('online',refresh);window.addEventListener('offline',status);
window.addEventListener('skylit-preferences',()=>{activeZone=prefs().timezone;selected=today();month=selected.slice(0,7);render()});
window.addEventListener('skylit-tab',e=>{if(e.detail==='calendar'||e.detail==='overview'){if(activeZone!==prefs().timezone){activeZone=prefs().timezone;selected=today();month=selected.slice(0,7);}render();}});
setInterval(()=>{const now=today();if(lastToday!==now){if(selected===lastToday){selected=now;month=now.slice(0,7);}lastToday=now;render();}status();paintOverview();if(available&&sources.some(s=>Date.now()-s.fetchedAt>15*60000))refresh();},60000);
if(available)read();paint();render();if(available)refresh();
})();
