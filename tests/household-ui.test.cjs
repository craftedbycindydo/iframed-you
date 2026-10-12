const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const model=require('../web/household-model.js'),appearance=require('../web/appearance.js');
const source=fs.readFileSync('web/household.js','utf8');
class Element{
 constructor(tag='div'){this.tag=tag;this.children=[];this.dataset={};this.style={};this.attrs={};this._text='';this.value='';this.hidden=false;this.isConnected=true;}
 set textContent(v){this._text=String(v);this.children=[]}get textContent(){return this._text+this.children.map(c=>c.textContent).join('')}
 append(...c){this.children.push(...c)}replaceChildren(...c){this._text='';this.children=c}setAttribute(k,v){this.attrs[k]=v}
 focus(){this.doc.activeElement=this}
 all(cls){return this.children.flatMap(c=>((c.className||'').split(' ').includes(cls)?[c]:[]).concat(c.all(cls)))}
}
const snapshot=()=>({rev:3,people:[{id:'p1',name:'Maya',color:'#00A36C'}],chores:[{id:'c1',title:'Make bed',emoji:'🛏️',personId:'p1',days:[],done:[]},{id:'c2',title:'Recycling',emoji:'',personId:null,days:[],done:['2026-10-12']},{id:'c3',title:'Sunday only',emoji:'',personId:'p1',days:[0],done:[]}],shopping:[{id:'s1',name:'Milk',qty:2,note:'',done:false}]});
function launch({bridge='real',initial=snapshot(),storage={},fail=null}={}){
 const now={value:Date.parse('2026-10-12T09:00:00Z')},elements=new Map(),listeners={},keys=[],timers=[],toasts=[],calls=[],reports=[],values=new Map(Object.entries(storage));
 class FixedDate extends Date{constructor(...a){super(...(a.length?a:[now.value]))}static now(){return now.value}}
 const document={activeElement:null,body:new Element('body'),createElement:tag=>{const e=new Element(tag);e.doc=document;return e},getElementById:id=>{if(!elements.has(id)){const e=document.createElement('div');e.id=id;elements.set(id,e)}return elements.get(id)},addEventListener:(name,fn)=>{if(name==='keydown')keys.push(fn)}};
 let store=model.normalize(initial),n=0,devices=[{id:'d1',name:'Karan phone',pairedAt:'2026-10-08T17:30:00Z'},{id:'d2',name:'Tablet',pairedAt:'2026-10-09T10:00:00Z'}];
 const settings={location:null,appearance:{palette:'linen',mode:'auto'}},applied=[];
 const app={notify:m=>toasts.push(m),calendarPreferences:()=>({timezone:'UTC',clock:'24'}),sharedSettings:()=>JSON.parse(JSON.stringify(settings)),
  setCity:c=>{applied.push(['city',c]);settings.location={name:c.name,latitude:c.latitude,longitude:c.longitude,timezone:c.timezone};listeners['skylit-settings'].forEach(f=>f())},
  setDisplayPreferences:d=>{applied.push(['display',d]);if(d.theme)settings.appearance.palette=d.theme;if(d.mode)settings.appearance.mode=d.mode;listeners['skylit-settings'].forEach(f=>f())}};
 const real={householdSnapshot:()=>JSON.stringify(store),householdMutate:json=>{const op=JSON.parse(json);calls.push(op);if(fail&&fail(op))return JSON.stringify({ok:false,error:'The frame refused this change.'});const r=model.apply(store,op,{id:()=>'n'+(++n),today:'2026-10-12'});if(r.ok)store=r.snapshot;return JSON.stringify(r)},reportSettings:json=>reports.push(JSON.parse(json)),pairingStatus:()=>JSON.stringify({devices,port:8765,advertised:true}),pairingRevoke:id=>{calls.push({revoke:id});devices=devices.filter(d=>d.id!==id);return true},pairingRevokeAll:()=>{calls.push({revokeAll:true});devices=[];return true}};
 const window={SkylitApp:app,SkylitHouseholdModel:model,SkylitAppearance:appearance,addEventListener:(name,fn)=>(listeners[name]=listeners[name]||[]).push(fn)};
 if(bridge==='real')window.Skylit=real;if(bridge==='old')window.Skylit={configure(){},calendarList:()=>'[]'};
 const localStorage={getItem:k=>values.has(k)?values.get(k):null,setItem:(k,v)=>values.set(k,String(v))};
 vm.runInNewContext(source,{window,document,localStorage,Date:FixedDate,Intl,JSON,Math,Number,Object,Array,String,Set,Map,setTimeout:()=>0,setInterval:fn=>{timers.push(fn);return timers.length},clearInterval:id=>{timers[id-1]=null}});
 const $=document.getElementById,rows=()=>$('chores-today').all('chore-row');
 return {window,$,rows,calls,toasts,reports,values,now,applied,settings,overlay:()=>document.body.children[0],tick:()=>timers.filter(Boolean).forEach(f=>f()),key:key=>{const e={key,preventDefault(){},stopImmediatePropagation(){}};keys.forEach(f=>f(e))},setStore:s=>{store=model.normalize(s)},store:()=>store,document};
}
const submit={preventDefault(){}};

test('chores render from the snapshot grouped by person, with overview summary',()=>{
 const h=launch(),groups=h.$('chores-today').children;
 assert.equal(groups.length,2);assert.match(groups[0].textContent,/Maya/);assert.match(groups[0].textContent,/0 of 1 done/);assert.match(groups[1].textContent,/Anyone/);assert.match(groups[1].textContent,/All done/);
 assert.deepEqual(h.rows().map(r=>[r.all('chore-title')[0].textContent,r.attrs['aria-pressed']]),[['Make bed','false'],['Recycling','true']]);
 assert.doesNotMatch(h.$('chores-today').textContent,/Sunday only/);
 assert.equal(h.$('chores-progress').textContent,'1 of 2 done today');assert.equal(h.$('overview-chores').hidden,false);assert.equal(h.$('overview-chores-count').textContent,'1 of 2 done today');assert.equal(h.$('overview-chores-bar').style.width,'50%');
 assert.equal(h.$('chores-editor').hidden,true);assert.equal(h.calls.length,0);
});
test('overview summary stays hidden and an empty state appears when there are no chores',()=>{
 const h=launch({initial:{rev:1}});
 assert.equal(h.$('overview-chores').hidden,true);assert.equal(h.$('chores-progress').hidden,true);assert.match(h.$('chores-today').textContent,/No chores yet/);
 h.$('chores-today').all('primary')[0].onclick();assert.equal(h.$('chores-editor').hidden,false);assert.equal(h.$('chores-today').hidden,true);
});
test('tapping a chore sends chore.done for today and reconciles with the returned snapshot',()=>{
 const h=launch();h.rows()[0].onclick();
 assert.deepEqual(h.calls,[{op:'chore.done',id:'c1',date:'2026-10-12',done:true}]);assert.equal(h.rows()[0].attrs['aria-pressed'],'true');assert.equal(h.$('chores-progress').textContent,'2 of 2 done today');
 h.rows()[1].onclick();assert.deepEqual(h.calls[1],{op:'chore.done',id:'c2',date:'2026-10-12',done:false});assert.equal(h.rows()[1].attrs['aria-pressed'],'false');assert.equal(h.toasts.length,0);
});
test('a refused or broken mutate shows the error and leaves the chore unchanged',()=>{
 const h=launch({fail:op=>op.op==='chore.done'});h.rows()[0].onclick();
 assert.deepEqual(h.toasts,['The frame refused this change.']);assert.equal(h.rows()[0].attrs['aria-pressed'],'false');assert.equal(h.$('chores-progress').textContent,'1 of 2 done today');
 h.window.Skylit.householdMutate=()=>{throw Error('bridge gone')};h.rows()[0].onclick();assert.equal(h.toasts[1],'Could not save this change.');assert.equal(h.rows()[0].attrs['aria-pressed'],'false');
 h.window.Skylit.householdMutate=()=>'not json';h.rows()[0].onclick();assert.equal(h.toasts.length,3);
});
test('receive re-renders, accepts JSON text, and ignores stale or malformed snapshots',()=>{
 const h=launch(),next=snapshot();next.rev=4;next.chores[0].done=['2026-10-12'];next.chores.push({id:'c9',title:'<img src=x onerror=alert(1)>',emoji:'',personId:null,days:[],done:[]});
 h.window.SkylitHousehold.receive(next);assert.equal(h.rows().length,3);assert.equal(h.rows()[0].attrs['aria-pressed'],'true');assert.equal(h.rows()[2].all('chore-title')[0].textContent,'<img src=x onerror=alert(1)>');
 h.window.SkylitHousehold.receive(snapshot());assert.equal(h.rows().length,3);
 h.window.SkylitHousehold.receive('garbage');h.window.SkylitHousehold.receive(null);assert.equal(h.rows().length,3);
 next.rev=5;next.chores=[];h.window.SkylitHousehold.receive(JSON.stringify(next));assert.equal(h.rows().length,0);assert.equal(h.$('overview-chores').hidden,true);
});
test('the day rolls over without a reload',()=>{
 const h=launch();assert.equal(h.rows()[1].attrs['aria-pressed'],'true');
 h.now.value=Date.parse('2026-10-13T00:01:00Z');h.tick();assert.equal(h.rows()[1].attrs['aria-pressed'],'false');
 h.rows()[1].onclick();assert.equal(h.calls[0].date,'2026-10-13');
});
test('manage view adds, edits and removes people and chores through the bridge',()=>{
 const h=launch();h.$('chores-manage').onclick();assert.equal(h.$('chores-editor').hidden,false);assert.equal(h.$('chores-manage').attrs['aria-pressed'],'true');
 h.$('person-name').value='  Sam ';h.$('person-colors').children[2].onclick();h.$('person-form').onsubmit(submit);
 assert.deepEqual(h.calls[0],{op:'person.add',name:'Sam',color:model.colors[2][0]});assert.equal(h.$('person-name').value,'');assert.match(h.$('people-list').textContent,/Sam/);
 h.$('chore-title').value='Sweep';h.$('chore-emoji').value='🧹';h.$('chore-person').value=h.store().people[1].id;h.$('chore-days').children[6].onclick();h.$('chore-days').children[0].onclick();h.$('chore-form').onsubmit(submit);
 assert.deepEqual(h.calls[1],{op:'chore.add',title:'Sweep',emoji:'🧹',personId:h.store().people[1].id,days:[0,6]});assert.match(h.$('chore-list').textContent,/Sweep.*Sam · Weekends/);
 h.$('chore-list').children[0].all('quiet')[0].onclick();assert.equal(h.$('chore-title').value,'Make bed');assert.equal(h.$('chore-save').textContent,'Save chore');
 h.$('chore-title').value='Make the bed';h.$('chore-form').onsubmit(submit);assert.deepEqual(h.calls[2],{op:'chore.update',id:'c1',title:'Make the bed',emoji:'🛏️',personId:'p1',days:[]});assert.equal(h.$('chore-save').textContent,'Add chore');
 h.$('people-list').children[0].all('quiet')[0].onclick();assert.equal(h.$('person-name').value,'Maya');h.$('person-form').onsubmit(submit);assert.deepEqual(h.calls[3],{op:'person.update',id:'p1',name:'Maya',color:'#00A36C'});
 const remove=h.$('chore-list').children[0].all('quiet')[1];remove.onclick();assert.equal(h.calls.length,4);assert.match(remove.textContent,/again/);remove.onclick();assert.deepEqual(h.calls[4],{op:'chore.remove',id:'c1'});
 const drop=h.$('people-list').children[0].all('quiet')[1];drop.onclick();drop.onclick();assert.deepEqual(h.calls[5],{op:'person.remove',id:'p1'});assert.doesNotMatch(h.$('people-list').textContent,/Maya/);
 h.$('person-name').value='';h.$('person-form').onsubmit(submit);assert.equal(h.calls.length,6);assert.equal(h.toasts.length,1);
});
test('shopping reads and writes the native store and keeps Undo',()=>{
 const h=launch();h.window.SkylitShopping.mount();
 assert.match(h.$('shopping-items').textContent,/Milk × 2/);assert.equal(h.$('shopping-completed-label').textContent,'Completed · 0');
 h.$('shopping-input').value=' Eggs ';h.$('shopping-add').onsubmit(submit);assert.deepEqual(h.calls[0],{op:'item.add',name:'Eggs'});assert.equal(h.$('shopping-input').value,'');assert.equal(h.$('shopping-undo').hidden,false);
 h.$('shopping-undo').onclick();assert.equal(h.calls[1].op,'item.remove');assert.deepEqual(h.store().shopping.map(x=>x.name),['Milk']);assert.equal(h.$('shopping-undo').hidden,true);
 h.$('shopping-items').children[0].onclick();assert.deepEqual(h.calls[2],{op:'item.update',id:'s1',done:true});assert.match(h.$('shopping-completed').textContent,/Milk/);
 h.$('shopping-undo').onclick();assert.deepEqual(h.calls[3],{op:'item.update',id:'s1',done:false});
 h.$('shopping-items').children[0].onclick();h.$('shopping-clear').onclick();assert.deepEqual(h.calls[5],{op:'items.clearDone'});assert.equal(h.store().shopping.length,0);assert.match(h.$('shopping-items').textContent,/clear/);
 h.$('shopping-undo').onclick();assert.deepEqual(h.store().shopping.map(x=>[x.name,x.qty,x.done]),[['Milk',2,true]]);
 h.window.SkylitHousehold.receive({...h.store(),rev:99,shopping:[{id:'s7',name:'From phone',qty:1,note:'aisle 3',done:false}]});assert.match(h.$('shopping-items').textContent,/From phone.*aisle 3/);
 assert.equal(h.values.has('skylit.household'),false);
});
test('legacy shopping migrates exactly once and is then no longer written',()=>{
 const legacy={note:'Keep me',shopping:[{id:'a',text:'Bread',done:false},{id:'b',text:'x'.repeat(100),done:true},{id:'c',text:'  '}],countdowns:[{title:'Trip',date:'2026-12-01'}],timers:[]};
 const first=launch({initial:{rev:0},storage:{'skylit.household':JSON.stringify(legacy)}});
 assert.deepEqual(first.calls.map(c=>c.op),['item.add','item.add','item.update']);assert.deepEqual(first.store().shopping.map(x=>[x.name.length,x.done]),[[5,false],[80,true]]);
 const kept=JSON.parse(first.values.get('skylit.household'));assert.deepEqual(kept.shopping,[]);assert.equal(kept.note,'Keep me');assert.deepEqual(kept.countdowns,legacy.countdowns);
 const second=launch({initial:first.store(),storage:Object.fromEntries(first.values)});assert.equal(second.calls.length,0);
 const emptied=launch({initial:{rev:9},storage:Object.fromEntries(first.values)});assert.equal(emptied.calls.length,0);
 const occupied=launch({storage:{'skylit.household':JSON.stringify(legacy)}});assert.equal(occupied.calls.length,0);assert.equal(JSON.parse(occupied.values.get('skylit.household')).shopping.length,3);
 const refused=launch({initial:{rev:0},storage:{'skylit.household':JSON.stringify(legacy)},fail:()=>true});assert.equal(refused.calls.length,1);assert.equal(JSON.parse(refused.values.get('skylit.household')).shopping.length,3);
 assert.equal(launch({initial:{rev:0},storage:{'skylit.household':'{broken'}}).calls.length,0);
});
test('pairing overlay shows the code, counts down, expires and can be dismissed',()=>{
 const h=launch(),o=h.overlay(),pairing=h.window.SkylitPairing;
 assert.equal(o.hidden,true);assert.equal(pairing.isOpen(),false);
 pairing.show({code:'482913',expiresAt:h.now.value+120000});assert.equal(o.hidden,false);assert.equal(o.attrs.role,'dialog');assert.deepEqual(o.all('pairing-code')[0].children.map(c=>c.textContent),['482','913']);assert.match(o.textContent,/Expires in 2:00/);assert.equal(h.document.activeElement.textContent,'Dismiss');
 h.now.value+=61000;h.tick();assert.match(o.textContent,/Expires in 0:59/);
 h.now.value+=59000;h.tick();assert.equal(o.hidden,true);assert.equal(o.all('pairing-code')[0].textContent,'');
 pairing.show({code:'000042',expiresAt:new Date(h.now.value+30000).toISOString()});assert.equal(pairing.isOpen(),true);assert.match(o.textContent,/Expires in 0:30/);o.all('primary')[0].onclick();assert.equal(pairing.isOpen(),false);
 pairing.show({code:'123456',expiresAt:Math.floor(h.now.value/1000)+60});assert.match(o.textContent,/Expires in 1:00/);h.key('Escape');assert.equal(pairing.isOpen(),false);
 pairing.show({code:'123456'});assert.match(o.textContent,/Expires in 2:00/);pairing.hide();assert.equal(pairing.isOpen(),false);pairing.hide();
 for(const bad of [{code:'12345'},{code:'<b>1</b>'},{code:'123456',expiresAt:h.now.value-1},null,'x'])pairing.show(bad);assert.equal(pairing.isOpen(),false);
});
test('Phone app settings list devices and revoke through the bridge',()=>{
 const h=launch();assert.match(h.$('phone-status').textContent,/Ready to pair/);
 const rows=()=>h.$('phone-devices').all('preference-row');assert.equal(rows().length,2);assert.match(rows()[0].textContent,/Karan phone.*Paired Oct 8, 2026/);
 rows()[0].all('quiet')[0].onclick();assert.deepEqual(h.calls[0],{revoke:'d1'});assert.equal(rows().length,1);assert.equal(h.$('phone-revoke-all').hidden,false);
 h.$('phone-revoke-all').onclick();assert.equal(h.calls.length,1);h.$('phone-revoke-all').onclick();assert.deepEqual(h.calls[1],{revokeAll:true});assert.equal(rows().length,0);assert.match(h.$('phone-devices').textContent,/No phones are paired/);assert.equal(h.$('phone-revoke-all').hidden,true);
 h.window.Skylit.pairingStatus=()=>'{"devices":"bad"}';h.window.SkylitPairing.refresh();assert.equal(rows().length,0);assert.match(h.$('phone-status').textContent,/Not visible/);
});
test('remote settings reuse the frame setters, validate input and report back',()=>{
 const h=launch();assert.deepEqual(h.reports,[{location:null,appearance:{palette:'linen',mode:'auto'}}]);
 h.window.SkylitRemote.apply({location:{name:' Calgary ',latitude:51.05,longitude:-114.07,timezone:'America/Edmonton'},appearance:{palette:'ocean',mode:'dark'}});
 assert.deepEqual(JSON.parse(JSON.stringify(h.applied)),[['city',{name:'Calgary',admin1:'',country:'',latitude:51.05,longitude:-114.07,timezone:'America/Edmonton'}],['display',{theme:'ocean',mode:'dark'}]]);
 assert.deepEqual(h.reports.at(-1),{location:{name:'Calgary',latitude:51.05,longitude:-114.07,timezone:'America/Edmonton'},appearance:{palette:'ocean',mode:'dark'}});
 const before=h.reports.length;h.window.SkylitRemote.apply({});assert.equal(h.applied.length,2);assert.equal(h.reports.length,before+1);
 h.window.SkylitRemote.apply(JSON.stringify({location:{name:'Oslo',latitude:59.9,longitude:10.7,timezone:'Mars/Olympus'}}));assert.equal(h.applied[2][1].timezone,Intl.DateTimeFormat().resolvedOptions().timeZone||'UTC');
 for(const bad of [{location:{name:'',latitude:1,longitude:1}},{location:{name:'X',latitude:91,longitude:0}},{location:{name:'X',latitude:'1',longitude:0}},{location:{name:'n'.repeat(81),latitude:1,longitude:1}},{appearance:{palette:'neon',mode:'disco'}},{appearance:{palette:'constructor'}},null,'{{'])h.window.SkylitRemote.apply(bad);
 assert.equal(h.applied.length,3);
 h.window.SkylitRemote.apply({appearance:{mode:'light'}});assert.deepEqual(JSON.parse(JSON.stringify(h.applied[3])),['display',{mode:'light'}]);
});
test('settings changes on the frame are reported once per change',()=>{
 const h=launch(),count=h.reports.length;
 h.window.SkylitApp.setDisplayPreferences({theme:'sage'});assert.equal(h.reports.length,count+1);assert.equal(h.reports.at(-1).appearance.palette,'sage');
 h.window.SkylitApp.setDisplayPreferences({theme:'sage'});assert.equal(h.reports.length,count+1);
});
for(const bridge of ['none','old'])test('without the new bridge ('+bridge+') an in-memory store keeps everything usable',()=>{
 const h=launch({bridge});assert.equal(h.window.SkylitHousehold.connected,false);assert.match(h.$('chores-today').textContent,/No chores yet/);assert.match(h.$('phone-status').textContent,/Preview only/);assert.match(h.$('phone-devices').textContent,/No phones are paired/);
 h.$('chores-manage').onclick();h.$('person-name').value='Maya';h.$('person-form').onsubmit(submit);h.$('chore-title').value='Make bed';h.$('chore-form').onsubmit(submit);h.$('chores-manage').onclick();
 assert.equal(h.rows().length,1);h.rows()[0].onclick();assert.equal(h.rows()[0].attrs['aria-pressed'],'true');assert.equal(h.$('overview-chores-count').textContent,'1 of 1 done today');
 h.window.SkylitShopping.mount();h.$('shopping-input').value='Tea';h.$('shopping-add').onsubmit(submit);assert.match(h.$('shopping-items').textContent,/Tea/);
 h.window.SkylitRemote.apply({appearance:{palette:'plum',mode:'dark'}});assert.equal(h.settings.appearance.palette,'plum');
 h.window.SkylitPairing.show({code:'111222',expiresAt:h.now.value+5000});h.window.SkylitPairing.hide();assert.deepEqual(h.toasts,[]);
 const again=launch({bridge,storage:Object.fromEntries(h.values)});assert.equal(again.rows().length,1);assert.equal(again.rows()[0].attrs['aria-pressed'],'true');
});
