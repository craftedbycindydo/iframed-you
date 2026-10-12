const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const source=fs.readFileSync('web/thermostat.js','utf8');
class Element{
 constructor(tag='div'){this.tag=tag;this.children=[];this.dataset={};this.attrs={};this._text='';this.value='';this.hidden=false;this.disabled=false;this.className='';this.parent=null;}
 set textContent(v){this._text=String(v);this.children=[]}get textContent(){return this._text+this.children.map(c=>c.textContent).join('')}
 append(...c){for(const child of c){child.parent=this;this.children.push(child)}}replaceChildren(...c){this._text='';this.children=[];this.append(...c)}setAttribute(k,v){this.attrs[k]=v}
 focus(){this.doc.activeElement=this}
 closest(selector){for(let node=this;node;node=node.parent)if((node.className||'').split(' ').includes(selector.slice(1)))return node;return null}
 all(cls){return this.children.flatMap(c=>((c.className||'').split(' ').includes(cls)?[c]:[]).concat(c.all(cls)))}
 tags(){return [this.tag,...this.children.flatMap(c=>c.tags())]}
}
const thermostat=(id,extra={})=>({id,name:id==='t1'?'Level-0':'level-1',online:true,units:'F',indoor:id==='t1'?69:74,humidity:41,mode:id==='t1'?'heat':'cool',heatAllowed:true,coolAllowed:true,setpoint:id==='t1'?70:76,changing:false,error:null,message:null,heatSetpoint:70,coolSetpoint:76,range:id==='t1'?{min:40,max:90}:{min:50,max:99},step:1,hold:id==='t1'?'schedule':'temporary',holdUntil:id==='t1'?null:'18:00',running:'idle',...extra});
const signedIn=(extra={},first={},second={})=>({configured:true,status:'ok',controllable:true,polledAt:'2026-10-12T08:55:00Z',retryAt:null,units:'F',account:'frame@example.com',message:null,signIn:null,thermostats:[thermostat('t1',first),thermostat('t2',second)],...extra});
const signedOut={configured:false,status:'unconfigured',controllable:false,polledAt:null,retryAt:null,account:null,message:null,signIn:null,thermostats:[]};
function launch({bridge='real',initial=signedOut,clock='12'}={}){
 const elements=new Map(),listeners={},documentListeners={},timers=[],calls=[],stored=[],opened=[];
 const document={activeElement:null,createElement:tag=>{const e=new Element(tag);e.doc=document;return e},getElementById:id=>{if(!elements.has(id)){const e=document.createElement('div');e.id=id;elements.set(id,e)}return elements.get(id)},addEventListener:(name,fn)=>(documentListeners[name]=documentListeners[name]||[]).push(fn)};
 let snapshot=initial;
 const frame={stepResult:null,signInResult:{ok:true,pending:true},refuse:false};
 const real={thermostatSnapshot:()=>JSON.stringify(snapshot),
  thermostatSignIn:(email,password)=>{calls.push(['signIn',email,password]);return JSON.stringify(frame.signInResult)},
  thermostatSignOut:()=>{calls.push(['signOut']);return !frame.refuse},
  thermostatStep:(id,delta)=>{calls.push(['step',id,delta]);if(frame.stepResult)return JSON.stringify(frame.stepResult);const row=snapshot.thermostats.find(t=>t.id===id);return JSON.stringify({ok:true,setpoint:row.setpoint+delta})},
  thermostatMode:(id,mode)=>{calls.push(['mode',id,mode]);return !frame.refuse},
  thermostatResume:id=>{calls.push(['resume',id]);return !frame.refuse},
  thermostatWatch:visible=>{calls.push(['watch',visible])}};
 const window={SkylitApp:{calendarPreferences:()=>({timezone:'UTC',clock}),openSettings:(...a)=>opened.push(a)},addEventListener:(name,fn)=>(listeners[name]=listeners[name]||[]).push(fn)};
 if(bridge==='real')window.Skylit=real;if(bridge==='old')window.Skylit={configure(){},photoStatus:()=>'{}'};
 const localStorage={getItem:()=>null,setItem:(k,v)=>stored.push([k,v])};
 vm.runInNewContext(source,{window,document,localStorage,Intl,Date,JSON,Number,Object,Array,String,Map,setTimeout:fn=>{timers.push(fn);return timers.length},clearTimeout(){}});
 const $=document.getElementById,tiles=()=>$('thermostat-tiles').all('thermostat-tile');
 const parts=index=>{const tile=tiles()[index],steps=tile.all('thermostat-step');return {tile,name:tile.all('thermostat-name')[0].children[0].textContent,state:tile.all('thermostat-state')[0].textContent,dot:tile.all('thermostat-dot')[0].dataset.mode,indoor:tile.all('thermostat-indoor')[0].textContent,setpoint:tile.all('thermostat-setpoint')[0].textContent,down:steps[0],up:steps[1],more:tile.all('thermostat-more')[0],menu:tile.all('thermostat-menu')[0]}};
 return {$,window,document,calls,stored,opened,timers,frame,tiles,parts,api:window.SkylitThermostat,push:next=>{snapshot=next;window.SkylitThermostat.receive(JSON.stringify(next))},tab:name=>listeners['skylit-tab'].forEach(fn=>fn({detail:name})),
  click:target=>documentListeners.click.forEach(fn=>fn({target})),key:key=>documentListeners.keydown.forEach(fn=>fn({key})),submit:(email,password)=>{$('thermostat-email').value=email;$('thermostat-password').value=password;$('thermostat-form').onsubmit({preventDefault(){}})}};
}
const menuText=menu=>menu.children.map(c=>c.textContent);

test('nothing appears on the Overview until an account is signed in',()=>{
 const h=launch();
 assert.equal(h.$('thermostat-tiles').hidden,true);assert.equal(h.tiles().length,0);assert.equal(h.$('thermostat-form').hidden,false);assert.equal(h.$('thermostat-account').hidden,true);assert.equal(h.$('thermostat-status').textContent,'');assert.equal(h.$('thermostat-sign-in').disabled,false);
});
test('each thermostat is one row: name, mode dot and word, indoor temperature, minus, setpoint, plus, menu',()=>{
 const h=launch({initial:signedIn()});
 assert.equal(h.$('thermostat-tiles').hidden,false);assert.equal(h.tiles().length,2);
 const first=h.parts(0),second=h.parts(1);
 assert.deepEqual([first.name,first.state,first.dot,first.indoor,first.setpoint],['Level-0','Heat','heat','69°','70°']);
 assert.deepEqual([second.name,second.state,second.dot,second.indoor,second.setpoint],['level-1','Cool','cool','74°','76°']);
 assert.deepEqual(first.tile.children.map(c=>c.className),['thermostat-name','thermostat-indoor','thermostat-step','thermostat-setpoint','thermostat-step','thermostat-more']);
 assert.deepEqual([first.down.attrs['aria-label'],first.up.attrs['aria-label'],first.more.attrs['aria-label'],first.more.attrs['aria-haspopup'],first.more.attrs['aria-expanded']],['Lower Level-0','Raise Level-0','Level-0 options','menu','false']);
 assert.equal(first.down.disabled||first.up.disabled,false);assert.equal(first.tile.className,'thermostat-tile');assert.equal(first.menu,undefined);
 h.push(signedIn({},{indoor:20.5,setpoint:21.5,units:'C',step:0.5,range:{min:4.5,max:32}}));assert.deepEqual([h.parts(0).indoor,h.parts(0).setpoint],['20.5°','21.5°']);
});
test('minus and plus call thermostatStep, show the new number at once and stop at the device limits',()=>{
 const h=launch({initial:signedIn()});
 h.parts(0).up.onclick();assert.deepEqual(h.calls,[['step','t1',1]]);assert.equal(h.parts(0).setpoint,'71°');assert.match(h.parts(0).state,/Heat · Updating…/);assert.equal(h.document.activeElement,h.parts(0).up);
 h.frame.stepResult={ok:true,setpoint:72};h.parts(0).up.onclick();h.frame.stepResult={ok:true,setpoint:73};h.parts(0).up.onclick();assert.equal(h.parts(0).setpoint,'73°');assert.equal(h.calls.length,3);
 h.frame.stepResult=null;h.parts(1).down.onclick();assert.deepEqual(h.calls.at(-1),['step','t2',-1]);assert.equal(h.parts(1).setpoint,'75°');
 h.push(signedIn({},{setpoint:90},{setpoint:50}));assert.equal(h.parts(0).up.disabled,true);assert.equal(h.parts(0).down.disabled,false);assert.equal(h.parts(1).down.disabled,true);assert.equal(h.parts(1).up.disabled,false);
 h.push(signedIn({},{setpoint:40}));assert.equal(h.parts(0).down.disabled,true);
 h.push(signedIn({},{range:null},{setpoint:null}));assert.equal(h.parts(0).up.disabled&&h.parts(0).down.disabled&&h.parts(1).up.disabled&&h.parts(1).down.disabled,true);assert.equal(h.parts(1).setpoint,'—');
 h.push(signedIn());h.frame.stepResult={ok:false,error:'That temperature is outside this thermostat\'s range.'};h.parts(0).up.onclick();assert.equal(h.parts(0).setpoint,'70°');assert.match(h.parts(0).state,/Heat · Not saved/);
 h.window.Skylit.thermostatStep=()=>{throw Error('bridge gone')};h.parts(1).up.onclick();assert.match(h.parts(1).state,/Not saved/);assert.equal(h.parts(1).setpoint,'76°');
});
test('the menu shows the hold line, Resume only on hold, and only the modes the device allows',()=>{
 const h=launch({initial:signedIn()});
 h.parts(0).more.onclick();let menu=h.parts(0).menu;assert.equal(h.parts(0).more.attrs['aria-expanded'],'true');assert.equal(menu.attrs.role,'menu');
 assert.deepEqual(menuText(menu),['Following schedule','Mode: Heat✓','Mode: Cool']);assert.deepEqual(menu.children.slice(1).map(c=>[c.attrs.role,c.attrs['aria-checked']]),[['menuitemradio','true'],['menuitemradio','false']]);
 h.parts(1).more.onclick();assert.equal(h.parts(0).menu,undefined);menu=h.parts(1).menu;assert.deepEqual(menuText(menu),['Hold until 6:00 PM','Resume schedule','Mode: Heat','Mode: Cool✓']);
 menu.children[1].onclick();assert.deepEqual(h.calls,[['resume','t2']]);assert.equal(h.parts(1).menu,undefined);assert.match(h.parts(1).state,/Updating…/);
 h.push(signedIn({},{hold:'permanent'},{heatAllowed:false}));h.parts(0).more.onclick();assert.deepEqual(menuText(h.parts(0).menu),['Permanent hold','Resume schedule','Mode: Heat✓','Mode: Cool']);
 h.parts(0).menu.children[3].onclick();assert.deepEqual(h.calls.at(-1),['mode','t1','cool']);assert.equal(h.parts(0).menu,undefined);
 h.parts(1).more.onclick();assert.deepEqual(menuText(h.parts(1).menu),['Hold until 6:00 PM','Resume schedule','Mode: Cool✓']);
 const before=h.calls.length;h.parts(1).menu.children[2].onclick();assert.equal(h.calls.length,before);assert.equal(h.parts(1).menu,undefined);
 h.push(signedIn({},{mode:'off',heatAllowed:false,coolAllowed:false,hold:null,setpoint:null,range:null}));h.parts(0).more.onclick();assert.deepEqual(menuText(h.parts(0).menu),['Nothing to change here.']);assert.match(h.parts(0).state,/^Off/);assert.equal(h.parts(0).dot,'off');
 const twentyFour=launch({initial:signedIn(),clock:'24'});twentyFour.parts(1).more.onclick();assert.equal(menuText(twentyFour.parts(1).menu)[0],'Hold until 18:00');
 const noon=launch({initial:signedIn({},{},{holdUntil:'00:15'})});noon.parts(1).more.onclick();assert.equal(menuText(noon.parts(1).menu)[0],'Hold until 12:15 AM');
});
test('the menu closes on an outside tap, Escape or a selection, and survives a refresh',()=>{
 const h=launch({initial:signedIn()});
 h.parts(0).more.onclick();h.click(h.parts(0).more);assert.notEqual(h.parts(0).menu,undefined);
 h.push(signedIn({},{indoor:70}));assert.notEqual(h.parts(0).menu,undefined);assert.equal(h.parts(0).indoor,'70°');
 h.click(h.$('somewhere-else'));assert.equal(h.parts(0).menu,undefined);
 h.parts(0).more.onclick();h.key('a');assert.notEqual(h.parts(0).menu,undefined);h.key('Escape');assert.equal(h.parts(0).menu,undefined);assert.equal(h.document.activeElement,h.parts(0).more);
 h.parts(0).more.onclick();h.parts(0).more.onclick();assert.equal(h.parts(0).menu,undefined);
 h.parts(0).more.onclick();h.push(signedIn({thermostats:[thermostat('t2')]}));assert.equal(h.tiles().length,1);assert.equal(h.parts(0).menu,undefined);
 h.frame.refuse=true;h.push(signedIn());h.parts(0).more.onclick();h.parts(0).menu.children[2].onclick();assert.match(h.parts(0).state,/Not saved/);
});
test('changing, stale, offline, locked and unreachable states dim the tile and add one short word',()=>{
 const h=launch({initial:signedIn({},{changing:true},{online:false})});
 assert.match(h.parts(0).state,/^Heat · Updating…$/);assert.equal(h.parts(0).tile.className,'thermostat-tile is-quiet');assert.equal(h.parts(0).up.disabled,false);
 assert.match(h.parts(1).state,/^Cool · Offline$/);assert.equal(h.parts(1).up.disabled&&h.parts(1).down.disabled,true);
 h.parts(1).more.onclick();assert.deepEqual(menuText(h.parts(1).menu).slice(0,1),['Hold until 6:00 PM']);assert.equal(h.parts(1).menu.children.every(c=>c.tag==='p'||c.disabled),true);
 for(const [status,word] of [['stale','Not current'],['unavailable','Unreachable'],['locked_out','Paused'],['loading','Loading']]){
  h.push(signedIn({status,controllable:false}));assert.equal(h.parts(0).state,'Heat · '+word);assert.equal(h.parts(0).tile.className,'thermostat-tile is-quiet');assert.equal(h.parts(0).up.disabled&&h.parts(0).down.disabled,true);assert.equal(h.parts(0).indoor,'69°');}
 h.push(signedIn({},{error:'rejected',message:'The thermostat did not accept the change.'}));assert.equal(h.parts(0).state,'Heat · Not saved');h.parts(0).more.onclick();assert.deepEqual(menuText(h.parts(0).menu).slice(0,2),['Following schedule','The thermostat did not accept the change.']);
 h.push({...signedOut,status:'signed_out'});assert.equal(h.tiles().length,1);assert.match(h.tiles()[0].textContent,/Thermostats · Signed out/);h.tiles()[0].all('quiet')[0].onclick();assert.deepEqual(h.opened,[['thermostats','overview']]);
 h.push(signedIn({status:'unavailable',controllable:false,thermostats:[]}));assert.match(h.tiles()[0].textContent,/Thermostats · Unreachable/);
 h.push(signedOut);assert.equal(h.$('thermostat-tiles').hidden,true);assert.equal(h.tiles().length,0);
});
test('names and messages from Honeywell are shown as text and malformed snapshots are harmless',()=>{
 const h=launch({initial:signedIn({account:'<b>x</b>@example.com'},{name:'<img src=x onerror=alert(1)>',message:'<script>1</script>',error:'x'})});
 assert.equal(h.parts(0).name,'<img src=x onerror=alert(1)>');h.parts(0).more.onclick();assert.equal(menuText(h.parts(0).menu)[1],'<script>1</script>');assert.equal(h.$('thermostat-account-email').textContent,'<b>x</b>@example.com');
 assert.deepEqual([...new Set(h.$('thermostat-tiles').tags().concat(h.$('thermostat-list').tags()))].sort(),['button','div','p','span','strong']);
 h.push(signedIn({thermostats:[null,7,{id:'../x'},{id:'t3',name:'n'.repeat(90),indoor:'hot',setpoint:{},mode:'constructor',hold:'__proto__',holdUntil:'<b>',range:'x'}]}));
 assert.equal(h.tiles().length,1);assert.deepEqual([h.parts(0).name.length,h.parts(0).indoor,h.parts(0).setpoint,h.parts(0).state,h.parts(0).up.disabled],[40,'—','—','Mode unknown · Offline',true]);
 for(const bad of [null,'garbage','[]',42,'{"thermostats":"x"}'])h.api.receive(bad);assert.equal(h.tiles().length,0);assert.equal(h.$('thermostat-tiles').hidden,true);
});
test('sign-in sends the credentials once, clears the password and never stores it',()=>{
 const h=launch();h.submit('  frame@example.com ','hunter2!');
 assert.deepEqual(h.calls,[['signIn','frame@example.com','hunter2!']]);assert.equal(h.$('thermostat-password').value,'');assert.equal(h.$('thermostat-email').value,'');assert.equal(h.$('thermostat-status').textContent,'Signing in…');
 assert.deepEqual(h.stored,[]);assert.doesNotMatch(source,/localStorage|sessionStorage|indexedDB|document\.cookie|console\./);assert.doesNotMatch(JSON.stringify(h.api.status()),/hunter2/);
 h.push({...signedOut,signIn:{pending:true}});assert.equal(h.$('thermostat-sign-in').disabled,true);assert.equal(h.$('thermostat-sign-in').textContent,'Signing in…');
 h.push(signedIn());assert.equal(h.$('thermostat-form').hidden,true);assert.equal(h.$('thermostat-account').hidden,false);assert.equal(h.$('thermostat-account-email').textContent,'frame@example.com');
 assert.deepEqual(h.$('thermostat-list').all('preference-row').map(r=>r.textContent),['Level-0Heat · 69° indoors','level-1Cool · 74° indoors']);assert.equal(h.$('thermostat-status').textContent,'Connected · Updated 8:55 a.m.');
 h.submit('','x');h.submit('a@b','');assert.equal(h.calls.length,1);assert.equal(h.$('thermostat-password').value,'');
});
test('every sign-in failure and account status becomes a plain sentence',()=>{
 const h=launch();
 h.frame.signInResult={ok:false,error:'Enter the account email and password.'};h.submit('a@b','x');assert.equal(h.$('thermostat-status').textContent,'Enter the account email and password.');assert.equal(h.$('thermostat-password').value,'');
 h.window.Skylit.thermostatSignIn=()=>{throw Error('bridge gone')};h.submit('a@b','x');assert.equal(h.$('thermostat-status').textContent,'Could not start signing in. Try again.');
 h.push({...signedOut,signIn:{ok:false,code:'bad_credentials',error:'That email or password was not accepted.',retryAt:null}});assert.equal(h.$('thermostat-status').textContent,'That email or password was not accepted.');assert.equal(h.$('thermostat-sign-in').disabled,false);assert.equal(h.$('thermostat-form').hidden,false);
 h.push({...signedOut,signIn:{ok:false,code:'locked',error:'Too many attempts. Try again later.',retryAt:'2026-10-12T09:40:00Z'}});assert.equal(h.$('thermostat-status').textContent,'Too many attempts — try again at 9:40 a.m.');
 h.push({...signedOut,signIn:{ok:false}});assert.equal(h.$('thermostat-status').textContent,'Could not sign in. Try again.');
 h.push({...signedOut,status:'signed_out'});assert.equal(h.$('thermostat-status').textContent,'Honeywell signed this frame out. Sign in again.');assert.equal(h.$('thermostat-form').hidden,false);
 for(const [extra,expected] of [[{status:'loading',controllable:false,polledAt:null,thermostats:[]},'Connected · Loading thermostats…'],[{status:'stale',controllable:false},'Trying again · Last updated 8:55 a.m.'],[{status:'unavailable',controllable:false},'Honeywell unavailable. Trying again.'],[{status:'locked_out',controllable:false,retryAt:'2026-10-12T10:05:00Z'},'Too many attempts — try again at 10:05 a.m.'],[{status:'locked_out',controllable:false},'Too many attempts. Try again later.'],[{thermostats:[]},'Connected · Updated 8:55 a.m.']]){h.push(signedIn(extra));assert.equal(h.$('thermostat-status').textContent,expected);}
 assert.match(h.$('thermostat-list').textContent,/No thermostats were found/);
 const day=launch({initial:signedIn(),clock:'24'});assert.equal(day.$('thermostat-status').textContent,'Connected · Updated 08:55');
});
test('sign out takes two taps and reports a failure',()=>{
 const h=launch({initial:signedIn()}),out=h.$('thermostat-sign-out');
 out.onclick();assert.equal(h.calls.length,0);assert.equal(out.textContent,'Tap again to sign out');h.timers.at(-1)();assert.equal(out.textContent,'Sign out');
 out.onclick();out.onclick();assert.deepEqual(h.calls,[['signOut']]);assert.equal(out.textContent,'Sign out');
 h.push(signedOut);assert.equal(h.$('thermostat-form').hidden,false);assert.equal(h.tiles().length,0);
 h.push(signedIn());h.frame.refuse=true;out.onclick();out.onclick();assert.equal(h.$('thermostat-status').textContent,'Could not sign out. Try again.');
});
test('the frame polls faster only while the Overview is showing',()=>{
 const h=launch({initial:signedIn()});h.tab('overview');h.tab('calendar');h.tab('overview');
 assert.deepEqual(h.calls,[['watch',true],['watch',false],['watch',true]]);
});
for(const bridge of ['none','old'])test('without the thermostat bridge ('+bridge+') nothing is shown and sign-in is switched off',()=>{
 const h=launch({bridge});assert.equal(h.api.supported,false);assert.equal(h.$('thermostat-tiles').hidden,true);assert.equal(h.$('thermostat-sign-in').disabled,true);
 assert.match(h.$('thermostat-status').textContent,bridge==='old'?/Update the Skylit app/:/does not contact Honeywell/);
 h.submit('a@b','secret');assert.equal(h.$('thermostat-password').value,'');h.tab('overview');h.api.receive(signedIn());assert.equal(h.tiles().length,2);h.parts(0).up.onclick();assert.match(h.parts(0).state,/Not saved/);
});
