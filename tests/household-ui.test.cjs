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
function launch({bridge='real',initial=snapshot(),storage={},fail=null,pairing={phase:'idle'}}={}){
 const now={value:Date.parse('2026-10-12T09:00:00Z')},elements=new Map(),listeners={},keys=[],timers=[],waits=[],events=[],toasts=[],calls=[],reports=[],values=new Map(Object.entries(storage));
 class FixedDate extends Date{constructor(...a){super(...(a.length?a:[now.value]))}static now(){return now.value}}
 const document={activeElement:null,body:new Element('body'),createElement:tag=>{const e=new Element(tag);e.doc=document;return e},getElementById:id=>{if(!elements.has(id)){const e=document.createElement('div');e.id=id;elements.set(id,e)}return elements.get(id)},addEventListener:(name,fn)=>{if(name==='keydown')keys.push(fn)}};
 let store=model.normalize(initial),n=0,devices=[{id:'d1',name:'Karan phone',pairedAt:'2026-10-08T17:30:00Z',lastSeen:'2026-10-11T08:00:00Z'},{id:'d2',name:'Tablet',pairedAt:'2026-10-09T10:00:00Z',lastSeen:'2026-10-09T10:00:00Z'}];
 const frame={pairing,pick:'64',address:'192.168.0.12',openError:null},busy=()=>['waiting','code'].includes(frame.pairing.phase);
 const settings={location:null,appearance:{palette:'linen',mode:'auto'}},applied=[];
 const app={notify:m=>toasts.push(m),icon:name=>'<svg data-name="'+name+'"></svg>',calendarPreferences:()=>({timezone:'UTC',clock:'24'}),sharedSettings:()=>JSON.parse(JSON.stringify(settings)),
  setCity:c=>{applied.push(['city',c]);settings.location={name:c.name,latitude:c.latitude,longitude:c.longitude,timezone:c.timezone};listeners['skylit-settings'].forEach(f=>f())},
  setDisplayPreferences:d=>{applied.push(['display',d]);if(d.theme)settings.appearance.palette=d.theme;if(d.mode)settings.appearance.mode=d.mode;listeners['skylit-settings'].forEach(f=>f())}};
 const real={householdSnapshot:()=>JSON.stringify(store),householdMutate:json=>{const op=JSON.parse(json);calls.push(op);if(fail&&fail(op))return JSON.stringify({ok:false,error:'The frame refused this change.'});const r=model.apply(store,op,{id:()=>'n'+(++n),today:'2026-10-12'});if(r.ok)store=r.snapshot;return JSON.stringify(r)},reportSettings:json=>reports.push(JSON.parse(json)),pairingStatus:()=>JSON.stringify({devices,port:8765,advertised:true,address:frame.address,pairing:frame.pairing}),
  pairingOpen:()=>{calls.push({open:true});if(frame.openError)return JSON.stringify({ok:false,error:frame.openError});frame.pairing={phase:'waiting',remaining:120000};return JSON.stringify({ok:true,pairing:frame.pairing})},
  pairingTap:number=>{calls.push({tap:number});if(frame.pairing.phase!=='code')return false;const right=number===frame.pick;if(right)devices.push({id:'d9',name:frame.name,pairedAt:'2026-10-12T09:00:00Z',lastSeen:'2026-10-12T09:00:00Z'});frame.pairing=right?{phase:'paired',name:frame.name}:{phase:'cancelled',reason:'decoy'};return right},
  pairingCancel:()=>{calls.push({cancel:true});frame.pairing=busy()?{phase:'cancelled',reason:'frame'}:{phase:'idle'};return true},pairingRevoke:id=>{calls.push({revoke:id});devices=devices.filter(d=>d.id!==id);return true},pairingRevokeAll:()=>{calls.push({revokeAll:true});devices=[];return true}};
 const window={SkylitApp:app,SkylitHouseholdModel:model,SkylitAppearance:appearance,addEventListener:(name,fn)=>(listeners[name]=listeners[name]||[]).push(fn),dispatchEvent:event=>{events.push(event.type);(listeners[event.type]||[]).forEach(fn=>fn(event))}};
 if(bridge==='real')window.Skylit=real;if(bridge==='old')window.Skylit={configure(){},calendarList:()=>'[]'};
 const localStorage={getItem:k=>values.has(k)?values.get(k):null,setItem:(k,v)=>values.set(k,String(v))};
 vm.runInNewContext(source,{window,document,localStorage,Date:FixedDate,Intl,JSON,Math,Number,Object,Array,String,Set,Map,Event:class{constructor(type){this.type=type}},setTimeout:(fn,ms)=>{waits.push([fn,ms]);return waits.length},clearTimeout:id=>{if(id)waits[id-1]=null},setInterval:fn=>{timers.push(fn);return timers.length},clearInterval:id=>{timers[id-1]=null}});
 const $=document.getElementById,rows=()=>$('chores-today').all('chore-row');
 return {frame,window,$,rows,calls,toasts,reports,events,waits,tab:name=>(listeners['skylit-tab']||[]).forEach(f=>f({detail:name})),values,now,applied,settings,overlay:()=>document.body.children[0],tick:()=>timers.filter(Boolean).forEach(f=>f()),key:key=>{const e={key,preventDefault(){},stopImmediatePropagation(){}};keys.forEach(f=>f(e))},setStore:s=>{store=model.normalize(s)},store:()=>store,document};
}
const submit={preventDefault(){}};

test('chores render from the snapshot grouped by person, with overview summary',()=>{
 const h=launch(),groups=h.$('chores-today').children;
 assert.equal(groups.length,2);assert.match(groups[0].textContent,/Maya/);assert.match(groups[0].textContent,/0 of 1 done/);assert.match(groups[1].textContent,/Anyone/);assert.match(groups[1].textContent,/All done/);
 assert.deepEqual(h.rows().map(r=>[r.all('chore-title')[0].textContent,r.attrs['aria-pressed']]),[['Make bed','false'],['Recycling','true']]);
 assert.doesNotMatch(h.$('chores-today').textContent,/Sunday only/);
 assert.equal(h.$('chores-progress').textContent,'1 of 2 done today');assert.equal(h.$('overview-chores').hidden,false);assert.equal(h.$('overview-chores-count').textContent,'1 of 2 done today');assert.equal(h.$('overview-shopping').hidden,false);assert.equal(h.$('overview-shopping-count').textContent,'1 to buy');assert.equal(h.$('overview-today').hidden,false);
 assert.equal(h.$('chores-editor').hidden,true);assert.equal(h.calls.length,0);
});
test('overview summary stays hidden and an empty state appears when there are no chores',()=>{
 const h=launch({initial:{rev:1}});
 assert.equal(h.$('overview-chores').hidden,true);assert.equal(h.$('overview-shopping').hidden,true);assert.equal(h.$('overview-today').hidden,true);assert.equal(h.$('chores-progress').hidden,true);assert.match(h.$('chores-today').textContent,/No chores yet/);
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
 assert.match(h.$('shopping-items').textContent,/Milk × 2/);assert.equal(h.$('shopping-completed-block').hidden,true);
 h.$('shopping-input').value=' Eggs ';h.$('shopping-add').onsubmit(submit);assert.deepEqual(h.calls[0],{op:'item.add',name:'Eggs'});assert.equal(h.$('shopping-input').value,'');assert.equal(h.$('shopping-undo').hidden,false);
 h.$('shopping-undo').onclick();assert.equal(h.calls[1].op,'item.remove');assert.deepEqual(h.store().shopping.map(x=>x.name),['Milk']);assert.equal(h.$('shopping-undo').hidden,true);
 h.$('shopping-items').children[0].onclick();assert.deepEqual(h.calls[2],{op:'item.update',id:'s1',done:true});
 h.$('shopping-undo').onclick();assert.deepEqual(h.calls[3],{op:'item.update',id:'s1',done:false});
 h.$('shopping-items').children[0].onclick();h.$('shopping-clear').onclick();assert.deepEqual(h.calls[5],{op:'items.clearDone'});assert.equal(h.store().shopping.length,0);assert.match(h.$('shopping-items').textContent,/clear/);
 h.$('shopping-undo').onclick();assert.deepEqual(h.store().shopping.map(x=>[x.name,x.qty,x.done]),[['Milk',2,true]]);
 h.window.SkylitHousehold.receive({...h.store(),rev:99,shopping:[{id:'s7',name:'From phone',qty:1,note:'aisle 3',done:false}]});assert.match(h.$('shopping-items').textContent,/From phone.*aisle 3/);
 assert.equal(h.values.has('skylit.household'),false);
});
test('a ticked item stays in place struck through until the next visit, and Completed hides when empty',()=>{
 const h=launch({initial:{...snapshot(),shopping:[{id:'s1',name:'Milk',qty:1,note:'',done:false},{id:'s2',name:'Tea',qty:1,note:'',done:false},{id:'s3',name:'Old',qty:1,note:'',done:true}]}});h.window.SkylitShopping.mount();
 const listed=()=>h.$('shopping-items').all('shopping-item').map(b=>[b.all('shopping-copy')[0].textContent,b.attrs['aria-pressed'],b.all('shopping-mark')[0].dataset.icon]);
 assert.deepEqual(listed(),[['Milk','false',undefined],['Tea','false',undefined]]);assert.equal(h.$('shopping-completed-block').hidden,false);assert.equal(h.$('shopping-completed-label').textContent,'Completed · 1');assert.match(h.$('shopping-completed').textContent,/Old/);
 h.$('shopping-items').all('shopping-item')[0].onclick();
 assert.deepEqual(listed(),[['Milk','true','tick'],['Tea','false',undefined]]);assert.doesNotMatch(h.$('shopping-completed').textContent,/Milk/);assert.equal(h.$('shopping-completed-label').textContent,'Completed · 2');
 h.$('shopping-items').all('shopping-item')[0].onclick();assert.deepEqual(listed()[0],['Milk','false',undefined]);
 h.$('shopping-items').all('shopping-item')[0].onclick();h.tab('household');assert.deepEqual(listed(),[['Tea','false',undefined]]);assert.match(h.$('shopping-completed').textContent,/Milk/);
 h.$('shopping-clear').onclick();assert.equal(h.$('shopping-completed-block').hidden,true);
 assert.doesNotMatch(source,/[✓○✦☷⌄]/);
});
test('every change to the household tells the rest of the dashboard',()=>{
 const h=launch(),before=h.events.filter(e=>e==='skylit-household').length;assert.ok(before>=1);
 h.rows()[0].onclick();assert.equal(h.events.filter(e=>e==='skylit-household').length,before+1);
});
test('chores draw their marks, leave Anyone without a glyph, and mark the row being edited',()=>{
 const h=launch(),groups=h.$('chores-today').children;
 assert.deepEqual(h.rows().map(r=>r.all('chore-mark')[0].dataset.icon),[undefined,'tick']);
 assert.equal(groups[1].all('chore-avatar')[0].textContent,'');assert.equal(groups[0].all('chore-avatar')[0].textContent,'M');
 assert.equal(groups[0].all('chore-group-head')[0].children[1].children[0].title,'Maya');
 h.$('chores-manage').onclick();const people=()=>h.$('people-list').all('chore-edit-row'),chores=()=>h.$('chore-list').all('chore-edit-row');
 assert.equal(people()[0].attrs['aria-current'],undefined);people()[0].all('quiet')[0].onclick();assert.equal(people()[0].attrs['aria-current'],'true');assert.match(people()[0].className,/is-editing/);
 chores()[1].all('quiet')[0].onclick();assert.deepEqual(chores().map(r=>r.attrs['aria-current']),[undefined,'true',undefined]);
 h.$('chore-cancel').onclick();assert.deepEqual(chores().map(r=>r.attrs['aria-current']),[undefined,undefined,undefined]);
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
const instruction='Enter this code on your phone, then tap the number your phone shows.';
const tags=node=>[node.tag,...node.children.flatMap(tags)];
const reveal=(h,name="Karan's iPhone")=>{h.frame.name=name;h.frame.pairing={phase:'code',remaining:90000,code:'299871',numbers:['07','64','91']};h.window.SkylitPairing.update(h.frame.pairing)};
test('Pair a phone opens the window and waits with the time left',()=>{
 const h=launch(),o=h.overlay(),pairing=h.window.SkylitPairing;
 assert.equal(o.hidden,true);assert.equal(pairing.isOpen(),false);assert.equal(h.$('phone-pair').onclick===undefined,false);
 h.$('phone-pair').onclick();assert.deepEqual(h.calls,[{open:true}]);assert.equal(pairing.isOpen(),true);assert.equal(o.attrs.role,'dialog');assert.equal(o.attrs['aria-modal'],'true');
 assert.match(o.textContent,/Waiting for your phone…/);assert.match(o.textContent,/Time left 2:00/);assert.equal(o.all('pairing-pick').length,0);assert.equal(o.all('pairing-code')[0].hidden,true);assert.equal(o.all('pairing-countdown')[0].hidden,false);
 assert.equal(h.document.activeElement.textContent,'Cancel');
 h.now.value+=61000;h.tick();assert.match(o.textContent,/Time left 0:59/);
 assert.doesNotMatch(o.textContent,/PAIR A PHONE/);assert.equal(o.all('pairing-hint')[0].hidden,true);
 o.all('secondary')[0].onclick();assert.deepEqual(h.calls[1],{cancel:true});assert.match(o.textContent,/Pairing cancelled/);assert.equal(o.all('pairing-countdown')[0].hidden,true);assert.equal(o.all('secondary')[0].textContent,'Close');
 o.all('secondary')[0].onclick();assert.equal(pairing.isOpen(),false);assert.equal(h.toasts.length,0);
 h.frame.openError='Too many paired devices. Remove one on the frame.';h.$('phone-pair').onclick();assert.equal(pairing.isOpen(),false);assert.deepEqual(h.toasts,['Too many paired devices. Remove one on the frame.']);
 h.window.Skylit.pairingOpen=()=>{throw Error('bridge gone')};h.$('phone-pair').onclick();assert.equal(h.toasts[1],'Could not start pairing. Try again.');
});
test('the code screen shows six digits, three numbers, Cancel and the exact instruction, then success',()=>{
 const h=launch(),o=h.overlay();h.$('phone-pair').onclick();reveal(h);
 assert.match(o.textContent,/Pairing code/);assert.deepEqual(o.all('pairing-code')[0].children.map(c=>c.textContent),['299','871']);assert.equal(o.all('pairing-code')[0].attrs['aria-label'],'2 9 9 8 7 1');
 assert.equal(o.all('pairing-text')[0].textContent,instruction);assert.equal(o.all('pairing-hint')[0].hidden,false);assert.equal(o.all('pairing-hint')[0].textContent,'No number on your phone? Tap Cancel.');assert.deepEqual(o.all('pairing-pick').map(b=>b.textContent),['07','64','91']);assert.equal(o.all('secondary')[0].textContent,'Cancel');assert.match(o.textContent,/Time left 1:30/);
 h.key('Tab');assert.equal(h.document.activeElement.textContent,'07');h.key('Tab');h.key('Tab');h.key('Tab');assert.equal(h.document.activeElement.textContent,'Cancel');
 o.all('pairing-pick')[1].onclick();assert.deepEqual(h.calls.at(-1),{tap:'64'});
 assert.match(o.textContent,/Phone paired/);assert.equal(o.all('pairing-text')[0].textContent,"Karan's iPhone can now use this frame.");assert.equal(o.all('pairing-pick').length,0);assert.equal(o.all('pairing-code')[0].textContent,'');assert.equal(o.all('pairing-countdown')[0].hidden,true);
 assert.match(h.$('phone-devices').textContent,/Karan's iPhone/);assert.equal(h.$('phone-note').textContent,"Karan's iPhone paired just now.");assert.equal(o.all('pairing-hint')[0].hidden,true);
 assert.equal(o.all('secondary')[0].textContent,'Done');o.all('secondary')[0].onclick();assert.equal(h.window.SkylitPairing.isOpen(),false);
});
test('each ending has its own calm wording, and a window that just ran out is a timeout, not a cancellation',()=>{
 const h=launch(),o=h.overlay(),pairing=h.window.SkylitPairing,ending=()=>o.all('pairing-text')[0].textContent,title=()=>o.children[0].children[0].textContent;
 h.$('phone-pair').onclick();assert.equal(h.$('phone-note').textContent,'');reveal(h);o.all('pairing-pick')[0].onclick();assert.deepEqual(h.calls.at(-1),{tap:'07'});assert.equal(title(),'Pairing cancelled');assert.match(ending(),/not the number on the phone/);assert.equal(o.all('pairing-pick').length,0);assert.equal(h.$('phone-devices').all('preference-row').length,2);
 assert.equal(h.$('phone-note').textContent,'Pairing cancelled. Nothing was paired.');
 h.key('Escape');assert.equal(pairing.isOpen(),false);
 h.$('phone-pair').onclick();assert.equal(h.$('phone-note').textContent,'');reveal(h);h.key('Escape');assert.deepEqual(h.calls.at(-1),{cancel:true});assert.equal(title(),'Pairing cancelled');assert.equal(ending(),'Nothing was paired.');o.all('secondary')[0].onclick();
 h.$('phone-pair').onclick();pairing.update(JSON.stringify({phase:'cancelled',reason:'phone'}));assert.match(ending(),/phone stopped pairing/);pairing.update({phase:'idle'});assert.equal(pairing.isOpen(),false);
 h.$('phone-pair').onclick();pairing.update({phase:'cancelled',reason:'refused'});assert.equal(title(),'Pairing cancelled');assert.match(ending(),/did not answer correctly.*Nothing was paired/);pairing.update({phase:'idle'});
 h.$('phone-pair').onclick();reveal(h);h.now.value+=89000;h.tick();assert.match(o.textContent,/Time left 0:01/);
 h.frame.pairing={phase:'cancelled',reason:'expired'};h.now.value+=1000;h.tick();assert.equal(title(),'Pairing timed out');assert.equal(ending(),'No phone was paired. Open Pair a phone to try again.');assert.doesNotMatch(o.textContent,/cancelled|another device/i);assert.equal(o.all('pairing-pick').length,0);
 assert.equal(h.$('phone-note').textContent,'Pairing timed out. No phone was paired.');
 h.frame.pairing={phase:'idle'};pairing.update(h.frame.pairing);assert.equal(pairing.isOpen(),false);assert.equal(h.$('phone-note').textContent,'Pairing timed out. No phone was paired.');
 h.$('phone-pair').onclick();pairing.update({phase:'cancelled',reason:'expired'});assert.equal(title(),'Pairing timed out');pairing.update({phase:'idle'});
});
test('endings close by themselves after about six seconds; waiting and code screens never do',()=>{
 const h=launch(),o=h.overlay(),pairing=h.window.SkylitPairing,pending=()=>h.waits.filter(Boolean);
 h.$('phone-pair').onclick();assert.equal(pending().length,0);reveal(h);assert.equal(pending().length,0);
 o.all('pairing-pick')[1].onclick();assert.equal(pending().length,1);assert.equal(pending()[0][1],6000);
 pending()[0][0]();assert.deepEqual(h.calls.at(-1),{cancel:true});assert.equal(pairing.isOpen(),false);
 h.$('phone-pair').onclick();h.frame.pairing={phase:'cancelled',reason:'expired'};pairing.update(h.frame.pairing);const stale=pending().at(-1)[0];
 o.all('secondary')[0].onclick();assert.equal(pairing.isOpen(),false);
 h.$('phone-pair').onclick();const before=h.calls.length;assert.equal(pending().length,0);stale();assert.equal(pairing.isOpen(),true);assert.equal(h.calls.length,before);
});
test('pairing text from the phone is shown as text and malformed states are ignored',()=>{
 const h=launch(),o=h.overlay(),pairing=h.window.SkylitPairing;
 h.$('phone-pair').onclick();reveal(h,'<img src=x onerror=alert(1)>');o.all('pairing-pick')[1].onclick();
 assert.equal(o.all('pairing-text')[0].textContent,'<img src=x onerror=alert(1)> can now use this frame.');assert.match(h.$('phone-devices').textContent,/<img src=x onerror=alert\(1\)>/);
 assert.deepEqual([...new Set(tags(o).concat(tags(h.$('phone-devices'))))].sort(),['button','div','h2','p','span','strong']);assert.equal(h.$('phone-note').textContent,'<img src=x onerror=alert(1)> paired just now.');
 pairing.update({phase:'paired',name:'n'.repeat(90)});assert.equal(o.all('pairing-text')[0].textContent,'n'.repeat(40)+' can now use this frame.');pairing.update({phase:'paired',name:7});assert.match(o.all('pairing-text')[0].textContent,/^This phone can/);
 pairing.update({phase:'idle'});
 for(const bad of [{phase:'code',code:'12345',numbers:['01','02','03']},{phase:'code',code:'123456',numbers:['01','02']},{phase:'code',code:'123456',numbers:['1','02','<b>']},{phase:'code',code:123456,numbers:['01','02','03']},{phase:'constructor'},{phase:'nonsense'},null,'x',42])pairing.update(bad);
 assert.equal(pairing.isOpen(),false);
 pairing.update({phase:'waiting'});assert.match(o.textContent,/Time left 2:00/);pairing.update({phase:'waiting',remaining:-5});assert.match(o.textContent,/Time left 2:00/);pairing.update({phase:'idle'});
});
test('a pairing already under way is shown when the dashboard loads',()=>{
 const h=launch({pairing:{phase:'waiting',remaining:45000}});assert.equal(h.window.SkylitPairing.isOpen(),true);assert.match(h.overlay().textContent,/Waiting for your phone….*Time left 0:45/);
});
test('Phone app settings show the address and list devices with paired and last-seen dates',()=>{
 const h=launch();assert.match(h.$('phone-status').textContent,/Ready to pair/);assert.equal(h.$('phone-address').textContent,'Address for manual entry: 192.168.0.12:8765');assert.equal(h.$('phone-address').hidden,false);
 const rows=()=>h.$('phone-devices').all('preference-row');assert.equal(rows().length,2);assert.match(rows()[0].textContent,/Karan phone.*Paired Oct 8, 2026 · Last seen Oct 11, 2026/);assert.match(rows()[1].textContent,/Tablet.*Paired Oct 9, 2026 · Last seen Oct 9, 2026/);
 const remove=rows()[0].all('quiet')[0];assert.equal(remove.textContent,'Remove');remove.onclick();assert.equal(h.calls.length,0);assert.match(remove.textContent,/again/);remove.onclick();assert.deepEqual(h.calls[0],{revoke:'d1'});assert.equal(rows().length,1);assert.equal(h.$('phone-revoke-all').hidden,false);
 assert.equal(h.$('phone-revoke-all').textContent,'Remove all phones');h.$('phone-revoke-all').onclick();assert.equal(h.calls.length,1);h.$('phone-revoke-all').onclick();assert.deepEqual(h.calls[1],{revokeAll:true});assert.equal(rows().length,0);assert.match(h.$('phone-devices').textContent,/No phones are paired/);assert.equal(h.$('phone-revoke-all').hidden,true);
 h.frame.address='';h.window.SkylitPairing.refresh();assert.equal(h.$('phone-address').hidden,true);assert.equal(h.$('phone-address').textContent,'');
 h.frame.address='192.168.0.12<script>';h.window.SkylitPairing.refresh();assert.equal(h.$('phone-address').hidden,true);
 h.window.Skylit.pairingStatus=()=>JSON.stringify({devices:[{id:'d5',name:'Old',pairedAt:'2026-10-08T17:30:00Z'}],port:8765,advertised:true});h.window.SkylitPairing.refresh();assert.match(rows()[0].textContent,/^OldPaired Oct 8, 2026Remove$/);
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
 assert.equal(h.$('phone-address').textContent,'');h.window.SkylitPairing.update({phase:'idle'});assert.deepEqual(h.toasts,[]);h.$('phone-pair').onclick();assert.deepEqual(h.toasts.splice(0),['Pairing works on the Android frame.']);assert.equal(h.window.SkylitPairing.isOpen(),false);
 const again=launch({bridge,storage:Object.fromEntries(h.values)});assert.equal(again.rows().length,1);assert.equal(again.rows()[0].attrs['aria-pressed'],'true');
});
