const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const frame=require('../web/frame-model.js');
const source=fs.readFileSync('web/icloud.js','utf8');
const sharedalbum='https:'+'//www.icloud.com/sharedalbum/#B0aGWZuqDGlLHQ6',share='https:'+'//share.icloud.com/photos/0a1B2c3D4e-5F_6g';
function launch({bridge='real',initial=null,refuse=null}={}){
 const elements=new Map(),values=new Map(),calls=[],events=[],timers=[];
 const $=id=>{if(!elements.has(id))elements.set(id,{textContent:'',value:'',hidden:false,disabled:false,attrs:{},setAttribute(k,v){this.attrs[k]=v}});return elements.get(id)};
 let status=initial;
 const real={icloudStatus:()=>JSON.stringify(status),icloudConnect:url=>{calls.push(['connect',url]);if(refuse)return JSON.stringify({ok:false,error:refuse});status={name:'Family',count:0,lastSync:null,syncing:true,error:null};return JSON.stringify({ok:true})},icloudDisconnect:()=>{calls.push(['disconnect']);status=null;return true},icloudSync:()=>{calls.push(['sync']);status={...status,syncing:true}}};
 const window={SkylitApp:{calendarPreferences:()=>({timezone:'UTC',clock:'24'})},dispatchEvent:e=>events.push(e.type)};
 if(bridge==='real')window.Skylit=real;if(bridge==='old')window.Skylit={configure(){},photoStatus:()=>'{}'};
 vm.runInNewContext(source,{window,document:{getElementById:$},localStorage:{getItem:k=>values.get(k)||null,setItem:(k,v)=>values.set(k,String(v))},Event:class{constructor(type){this.type=type}},Intl,Date,JSON,setTimeout:fn=>{timers.push(fn);return timers.length},clearTimeout(){}});
 const submit=link=>{$('icloud-link').value=link;$('icloud-form').onsubmit({preventDefault(){}})};
 return {$,window,calls,events,values,timers,submit,api:window.SkylitICloud,real,set:next=>{status=next}};
}

test('only the two public album link forms are accepted',()=>{
 const {api}=launch();
 for(const good of [sharedalbum,share,'  '+sharedalbum+'  '])assert.equal(api.validLink(good),true,good);
 for(const bad of ['','http:'+'//www.icloud.com/sharedalbum/#B0aGWZuq','https:'+'//www.icloud.com/sharedalbum/','https:'+'//www.icloud.com/sharedalbum/#','https:'+'//www.icloud.com/sharedalbum/#abc def','https:'+'//www.icloud.com/photos/#B0aGWZuq','https:'+'//icloud.com/sharedalbum/#B0aGWZuq','https:'+'//www.icloud.com.evil.test/sharedalbum/#B0aGWZuq','https:'+'//evil.test/?https:'+'//www.icloud.com/sharedalbum/#B0aGWZuq','https:'+'//user@www.icloud.com/sharedalbum/#B0aGWZuq','https:'+'//share.icloud.com/photos/','https:'+'//share.icloud.com/photos/abc/def','https:'+'//share.icloud.com/photos/abc?x=1','https:'+'//photos.app.goo.gl/abc','javascript:alert(1)',null,42])assert.equal(api.validLink(bad),false,String(bad));
});
test('nothing connected shows the link form and a not-set-up health row',()=>{
 const h=launch();
 assert.equal(h.$('icloud-entry').hidden,false);assert.equal(h.$('icloud-connected').hidden,true);assert.equal(h.$('icloud-connect').disabled,false);assert.equal(h.$('icloud-status').textContent,'');
 assert.equal(h.api.status(),null);assert.deepEqual({...h.api.health()},{configured:false,updated:0,busy:false,error:false,count:0});assert.equal(h.api.describe(null),'Not set up');
});
test('connecting sends the link once, clears the field and shows the syncing state',()=>{
 const h=launch();h.submit('  '+sharedalbum+' ');
 assert.deepEqual(h.calls,[['connect',sharedalbum]]);assert.equal(h.$('icloud-link').value,'');
 assert.equal(h.$('icloud-entry').hidden,true);assert.equal(h.$('icloud-connected').hidden,false);assert.equal(h.$('icloud-name').textContent,'Family');assert.match(h.$('icloud-detail').textContent,/Syncing album… · 0 pictures/);
 assert.equal(h.$('icloud-sync').disabled,true);assert.equal(h.$('icloud-sync').textContent,'Syncing…');assert.equal(h.$('icloud-connected').attrs['aria-busy'],'true');assert.match(h.$('icloud-status').textContent,/Album connected/);
 assert.equal(h.api.health().configured,true);assert.equal(h.api.health().busy,true);
});
test('an invalid link is rejected locally and a native refusal is surfaced',()=>{
 const h=launch();h.submit('https:'+'//photos.app.goo.gl/abc');
 assert.equal(h.calls.length,0);assert.equal(h.$('icloud-link').value,'');assert.match(h.$('icloud-status').textContent,/public link/);assert.equal(h.$('icloud-entry').hidden,false);
 const refused=launch({refuse:'This album is not public.'});refused.submit(share);
 assert.deepEqual(refused.calls,[['connect',share]]);assert.equal(refused.$('icloud-status').textContent,'This album is not public.');assert.equal(refused.$('icloud-entry').hidden,false);assert.equal(refused.$('icloud-link').value,'');assert.equal(refused.api.status(),null);
 const broken=launch();broken.real.icloudConnect=()=>{throw Error('gone')};broken.submit(share);assert.match(broken.$('icloud-status').textContent,/Could not connect/);
 broken.real.icloudConnect=()=>'not json';broken.submit(share);assert.match(broken.$('icloud-status').textContent,/Could not connect/);
});
test('receive updates the status block live for synced, error and removed states',()=>{
 const h=launch({initial:{name:'Family',count:0,lastSync:null,syncing:true,error:null}}),before=h.events.length;
 assert.match(h.$('icloud-detail').textContent,/Syncing/);
 h.api.receive({name:'Family',count:24,lastSync:'2026-10-10T08:15:00Z',syncing:false,error:null});
 assert.equal(h.$('icloud-detail').textContent,'24 pictures · Synced Oct 10, 08:15');assert.equal(h.$('icloud-sync').disabled,false);assert.equal(h.$('icloud-sync').textContent,'Sync now');assert.equal(h.$('icloud-error').hidden,true);assert.equal(h.$('icloud-connected').attrs['aria-busy'],'false');
 assert.deepEqual({...h.api.health()},{configured:true,updated:Date.parse('2026-10-10T08:15:00Z'),busy:false,error:false,count:24});assert.ok(h.events.length>before);assert.ok(h.events.every(e=>e==='skylit-service-status'));
 h.api.receive(JSON.stringify({name:'<b>Family</b>',count:1,lastSync:1760084100000,syncing:false,error:'Apple did not respond. Saved pictures kept.'}));
 assert.equal(h.$('icloud-name').textContent,'<b>Family</b>');assert.equal(h.$('icloud-detail').textContent,'Needs attention · 1 picture saved');assert.equal(h.$('icloud-error').hidden,false);assert.equal(h.$('icloud-error').textContent,'Apple did not respond. Saved pictures kept.');assert.equal(h.api.health().error,true);
 h.api.receive({name:'',count:-4,lastSync:'never',syncing:'yes',error:7});assert.equal(h.$('icloud-name').textContent,'Shared album');assert.equal(h.$('icloud-detail').textContent,'Connected · Waiting for the first sync');
 for(const gone of [null,'null','garbage',[]]){h.api.receive({name:'x'});h.api.receive(gone);assert.equal(h.api.status(),null);assert.equal(h.$('icloud-entry').hidden,false);assert.equal(h.$('icloud-connected').hidden,true);}
});
test('Sync now asks the frame and reflects the syncing state',()=>{
 const h=launch({initial:{name:'Family',count:3,lastSync:'2026-10-10T08:15:00Z',syncing:false,error:null}});
 h.$('icloud-sync').onclick();assert.deepEqual(h.calls,[['sync']]);assert.equal(h.$('icloud-sync').disabled,true);assert.match(h.$('icloud-detail').textContent,/Syncing album… · 3 pictures/);
 h.$('icloud-sync').onclick();h.api.sync();assert.equal(h.calls.length,1);
});
test('disconnect needs a second tap and says what is removed',()=>{
 const h=launch({initial:{name:'Family',count:3,lastSync:'2026-10-10T08:15:00Z',syncing:false,error:null}});
 h.$('icloud-disconnect').onclick();assert.equal(h.calls.length,0);assert.match(h.$('icloud-disconnect').textContent,/Tap again to remove album pictures/);
 h.timers.at(-1)();assert.equal(h.$('icloud-disconnect').textContent,'Disconnect album');
 h.$('icloud-disconnect').onclick();h.$('icloud-disconnect').onclick();assert.deepEqual(h.calls,[['disconnect']]);
 assert.equal(h.api.status(),null);assert.equal(h.$('icloud-entry').hidden,false);assert.match(h.$('icloud-status').textContent,/pictures were removed/);assert.equal(h.$('icloud-disconnect').textContent,'Disconnect album');
 const stuck=launch({initial:{name:'Family',count:3,lastSync:null,syncing:false,error:null}});stuck.real.icloudDisconnect=()=>false;stuck.$('icloud-disconnect').onclick();stuck.$('icloud-disconnect').onclick();
 assert.match(stuck.$('icloud-status').textContent,/Could not disconnect/);assert.equal(stuck.$('icloud-connected').hidden,false);
});
test('the album link never reaches localStorage, the page or the preferences export',()=>{
 const h=launch();h.submit(sharedalbum);h.api.receive({name:'Family',count:2,lastSync:'2026-10-10T08:15:00Z',syncing:false,error:null});
 assert.equal(h.values.size,0);
 const shown=['icloud-link','icloud-name','icloud-detail','icloud-error','icloud-status','icloud-sync','icloud-disconnect'].map(id=>h.$(id).textContent+h.$(id).value).join(' ')+JSON.stringify(h.api.status())+JSON.stringify(h.api.health());
 assert.doesNotMatch(shown,/B0aGWZuqDGlLHQ6|sharedalbum/);
 assert.doesNotMatch(JSON.stringify(frame.exportPreferences({icloud:sharedalbum,text:'large'},{icloudAlbum:sharedalbum,theme:'sage'})),/icloud|B0aGWZuqDGlLHQ6/i);
 assert.throws(()=>frame.importPreferences({format:'skylit-display',version:1,display:{theme:'sage',icloud:sharedalbum}}));
 assert.doesNotMatch(source,/localStorage|console\./);
 const page=fs.readFileSync('web/index.html','utf8');assert.match(page,/<input id="icloud-link" type="password"[^>]*autocomplete="off"/);
});
for(const bridge of ['none','old'])test('without the iCloud bridge ('+bridge+') the section explains itself and does nothing',()=>{
 const h=launch({bridge});
 assert.equal(h.api.supported,false);assert.equal(h.$('icloud-connect').disabled,true);assert.equal(h.$('icloud-entry').hidden,false);assert.equal(h.$('icloud-connected').hidden,true);
 assert.match(h.$('icloud-status').textContent,bridge==='old'?/Update the Skylit app/:/browser preview does not store private links/);
 h.submit(sharedalbum);assert.equal(h.$('icloud-link').value,'');assert.equal(h.api.status(),null);assert.equal(h.api.health().configured,false);h.api.sync();
 h.api.receive({name:'Family',count:1,lastSync:null,syncing:false,error:null});assert.equal(h.$('icloud-name').textContent,'Family');
});
