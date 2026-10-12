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
function launch({bridge='real',initial=signedOut,clock='12',tab='',units='fahrenheit'}={}){
 const elements=new Map(),listeners={},documentListeners={},timers=[],calls=[],stored=[],opened=[],toasts=[];
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
 const window={SkylitApp:{calendarPreferences:()=>({timezone:'UTC',clock}),status:()=>({tab}),displayPreferences:()=>({units}),icon:name=>'<svg data-name="'+name+'"></svg>',notify:m=>toasts.push(m),openSettings:(...a)=>opened.push(a)},addEventListener:(name,fn)=>(listeners[name]=listeners[name]||[]).push(fn)};
 if(bridge==='real')window.Skylit=real;if(bridge==='old')window.Skylit={configure(){},photoStatus:()=>'{}'};
 const localStorage={getItem:()=>null,setItem:(k,v)=>stored.push([k,v])};
 vm.runInNewContext(source,{window,document,localStorage,Intl,Date,JSON,Number,Object,Array,String,Map,setTimeout:fn=>{timers.push(fn);return timers.length},clearTimeout(){}});
 const $=document.getElementById,tiles=()=>$('thermostat-tiles').all('thermostat-tile');
 const parts=index=>{const tile=tiles()[index],steps=tile.all('thermostat-step');return {tile,name:tile.all('thermostat-name')[0].children[0].textContent,state:tile.all('thermostat-state')[0].textContent,dot:tile.all('thermostat-dot')[0].dataset.mode,indoor:tile.all('thermostat-indoor')[0].textContent,setpoint:tile.all('thermostat-setpoint')[0].textContent,down:steps[0],up:steps[1],more:tile.all('thermostat-more')[0],menu:tile.all('thermostat-menu')[0]}};
 return {$,window,document,calls,stored,opened,timers,toasts,frame,tiles,parts,api:window.SkylitThermostat,push:next=>{snapshot=next;window.SkylitThermostat.receive(JSON.stringify(next))},tab:name=>listeners['skylit-tab'].forEach(fn=>fn({detail:name})),
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
 assert.deepEqual([second.name,second.state,second.dot,second.indoor,second.setpoint],['level-1','Cool · Hold until 6 PM','cool','74°','76°']);
 assert.deepEqual(first.tile.children.map(c=>c.className),['thermostat-name','thermostat-indoor','thermostat-step','thermostat-setpoint','thermostat-step','thermostat-more']);
 assert.deepEqual([first.down.attrs['aria-label'],first.up.attrs['aria-label'],first.more.attrs['aria-label'],first.more.attrs['aria-haspopup'],first.more.attrs['aria-expanded']],['Lower Level-0','Raise Level-0','Level-0 options','menu','false']);
 assert.equal(first.down.disabled||first.up.disabled,false);assert.equal(first.tile.className,'thermostat-tile');assert.equal(first.menu,undefined);
 h.push(signedIn({},{indoor:20.5,setpoint:21.5,units:'C',step:0.5,range:{min:4.5,max:32}}));assert.deepEqual([h.parts(0).indoor,h.parts(0).setpoint],['20.5°C','21.5°']);
});
test('minus and plus call thermostatStep, show the new number at once and stop at the device limits',()=>{
 const h=launch({initial:signedIn()});
 h.parts(0).up.onclick();assert.deepEqual(h.calls,[['step','t1',1]]);assert.equal(h.parts(0).setpoint,'71°');assert.match(h.parts(0).state,/Heat · Updating…/);assert.equal(h.document.activeElement,h.parts(0).up);
 h.frame.stepResult={ok:true,setpoint:72};h.parts(0).up.onclick();h.frame.stepResult={ok:true,setpoint:73};h.parts(0).up.onclick();assert.equal(h.parts(0).setpoint,'73°');assert.equal(h.calls.length,3);
 h.frame.stepResult=null;h.parts(1).down.onclick();assert.deepEqual(h.calls.at(-1),['step','t2',-1]);assert.equal(h.parts(1).setpoint,'75°');
 h.push(signedIn({},{setpoint:90},{setpoint:50}));assert.equal(h.parts(0).up.disabled,true);assert.equal(h.parts(0).down.disabled,false);assert.equal(h.parts(1).down.disabled,true);assert.equal(h.parts(1).up.disabled,false);
 h.push(signedIn({},{setpoint:40}));assert.equal(h.parts(0).down.disabled,true);
 h.push(signedIn({},{range:null},{setpoint:null}));assert.equal(h.parts(0).up.disabled&&h.parts(0).down.disabled&&h.parts(1).up.disabled&&h.parts(1).down.disabled,true);assert.equal(h.parts(1).setpoint,'—');
 h.push(signedIn());h.frame.stepResult={ok:false,error:'That temperature is outside this thermostat\'s range.'};h.parts(0).up.onclick();assert.equal(h.parts(0).setpoint,'70°');assert.match(h.parts(0).state,/Heat · Not changed/);
 h.window.Skylit.thermostatStep=()=>{throw Error('bridge gone')};h.parts(1).up.onclick();assert.match(h.parts(1).state,/Not changed/);assert.equal(h.parts(1).setpoint,'76°');
});
test('the hold shows on the tile, and the menu offers Resume only on hold and only the modes the device allows',()=>{
 const h=launch({initial:signedIn()});
 assert.equal(h.parts(0).state,'Heat');assert.equal(h.parts(1).state,'Cool · Hold until 6 PM');
 h.parts(0).more.onclick();let menu=h.parts(0).menu;assert.equal(h.parts(0).more.attrs['aria-expanded'],'true');assert.equal(menu.attrs.role,'menu');
 assert.deepEqual(menuText(menu),['Mode','Heat','Cool']);assert.deepEqual(menu.children.slice(1).map(c=>[c.attrs.role,c.attrs['aria-checked'],c.children[1].dataset.icon]),[['menuitemradio','true','tick'],['menuitemradio','false',undefined]]);
 h.parts(1).more.onclick();assert.equal(h.parts(0).menu,undefined);menu=h.parts(1).menu;assert.deepEqual(menuText(menu),['Resume schedule','Mode','Heat','Cool']);
 menu.children[0].onclick();assert.deepEqual(h.calls,[['resume','t2']]);assert.equal(h.parts(1).menu,undefined);assert.match(h.parts(1).state,/Updating…/);
 h.push(signedIn({},{hold:'permanent'},{heatAllowed:false}));assert.equal(h.parts(0).state,'Heat · Permanent hold');h.parts(0).more.onclick();assert.deepEqual(menuText(h.parts(0).menu),['Resume schedule','Mode','Heat','Cool']);
 h.parts(0).menu.children[3].onclick();assert.deepEqual(h.calls.at(-1),['mode','t1','cool']);assert.equal(h.parts(0).menu,undefined);
 h.parts(1).more.onclick();assert.deepEqual(menuText(h.parts(1).menu),['Resume schedule','Mode','Cool']);
 const before=h.calls.length;h.parts(1).menu.children[2].onclick();assert.equal(h.calls.length,before);assert.equal(h.parts(1).menu,undefined);
 h.push(signedIn({},{mode:'off',heatAllowed:false,coolAllowed:false,hold:null,setpoint:null,range:null}));h.parts(0).more.onclick();assert.deepEqual(menuText(h.parts(0).menu),['Nothing to change here.']);assert.match(h.parts(0).state,/^Off/);assert.equal(h.parts(0).dot,'off');
 assert.equal(launch({initial:signedIn(),clock:'24'}).parts(1).state,'Cool · Hold until 18:00');
 assert.equal(launch({initial:signedIn({},{},{holdUntil:'00:15'})}).parts(1).state,'Cool · Hold until 12:15 AM');
 assert.equal(launch({initial:signedIn({},{},{holdUntil:null})}).parts(1).state,'Cool · Temporary hold');
});
test('a thermostat that is Off or Auto shows its setpoint but cannot be stepped',()=>{
 const h=launch({initial:signedIn({},{mode:'off'},{mode:'auto'})});
 for(const index of [0,1])assert.equal(h.parts(index).up.disabled&&h.parts(index).down.disabled,true);
 h.push(signedIn({},{mode:'emheat'}));assert.equal(h.parts(0).up.disabled||h.parts(0).down.disabled,false);
});
test('controls are drawn icons, not text glyphs the frame font may lack',()=>{
 const h=launch({initial:signedIn()}),first=h.parts(0);
 assert.deepEqual([first.down,first.up,first.more].map(control=>[control.children[0].dataset.icon,control.children[0].textContent,control.children[0].attrs['aria-hidden']]),[['minus','','true'],['plus','','true'],['chevron','','true']]);
 assert.doesNotMatch(source,/[⌄−✓✦☷]/);
});
test('values carry their unit only when it differs from the weather unit',()=>{
 assert.deepEqual([launch({initial:signedIn()}).parts(0).indoor,launch({initial:signedIn()}).parts(0).setpoint],['69°','70°']);
 const mixed=launch({initial:signedIn(),units:'celsius'});assert.deepEqual([mixed.parts(0).indoor,mixed.parts(0).setpoint,mixed.parts(0).tile.all('thermostat-setpoint')[0].attrs['aria-label']],['69°F','70°','Set to 70°F']);
 const metric=launch({initial:signedIn({},{units:'C',indoor:20.5,setpoint:21}),units:'celsius'});assert.deepEqual([metric.parts(0).indoor,metric.parts(0).setpoint],['20.5°','21°']);
 assert.equal(launch({initial:signedIn({},{units:'C',indoor:20.5})}).parts(0).indoor,'20.5°C');
});
test('one thermostat is marked so it does not stretch across the screen',()=>{
 assert.equal(launch({initial:signedIn({thermostats:[thermostat('t1')]})}).$('thermostat-tiles').className,'thermostat-tiles is-single');
 assert.equal(launch({initial:signedIn()}).$('thermostat-tiles').className,'thermostat-tiles');
 assert.equal(launch({initial:signedIn()}).parts(0).tile.all('thermostat-name')[0].children[0].title,'Level-0');
});
test('the menu closes on an outside tap, Escape or a selection, and survives a refresh',()=>{
 const h=launch({initial:signedIn()});
 h.parts(0).more.onclick();h.click(h.parts(0).more);assert.notEqual(h.parts(0).menu,undefined);
 h.push(signedIn({},{indoor:70}));assert.notEqual(h.parts(0).menu,undefined);assert.equal(h.parts(0).indoor,'70°');
 h.click(h.$('somewhere-else'));assert.equal(h.parts(0).menu,undefined);
 h.parts(0).more.onclick();h.key('a');assert.notEqual(h.parts(0).menu,undefined);h.key('Escape');assert.equal(h.parts(0).menu,undefined);assert.equal(h.document.activeElement,h.parts(0).more);
 h.parts(0).more.onclick();h.parts(0).more.onclick();assert.equal(h.parts(0).menu,undefined);
 h.parts(0).more.onclick();h.push(signedIn({thermostats:[thermostat('t2')]}));assert.equal(h.tiles().length,1);assert.equal(h.parts(0).menu,undefined);
 h.frame.refuse=true;h.push(signedIn());h.parts(0).more.onclick();h.parts(0).menu.children[2].onclick();assert.match(h.parts(0).state,/Not changed/);assert.deepEqual(h.toasts,['Could not reach the frame. Try again.']);
});
test('a pending change tints only the setpoint; stale readings are not dimmed; offline and locked ones are',()=>{
 const h=launch({initial:signedIn({},{changing:true},{online:false})});
 assert.equal(h.parts(0).state,'Heat · Updating…');assert.equal(h.parts(0).tile.className,'thermostat-tile');assert.equal(h.parts(0).tile.all('thermostat-setpoint')[0].className,'thermostat-setpoint is-pending');assert.equal(h.parts(0).tile.all('thermostat-indoor')[0].className,'thermostat-indoor');assert.equal(h.parts(0).up.disabled,false);
 assert.equal(h.parts(1).state,'Cool · Offline');assert.equal(h.parts(1).tile.className,'thermostat-tile is-quiet');assert.equal(h.parts(1).up.disabled&&h.parts(1).down.disabled,true);
 h.parts(1).more.onclick();assert.equal(h.parts(1).menu.children.every(c=>c.tag==='p'||c.disabled),true);
 for(const [extra,word,quiet] of [[{status:'stale'},'Last update 8:55',false],[{status:'stale',polledAt:null},'Not updated',false],[{status:'unavailable'},'Offline',true],[{status:'locked_out',retryAt:'2026-10-12T09:30:00Z'},'Try again at 9:30',true],[{status:'locked_out'},'Try again later',true]]){
  h.push(signedIn({...extra,controllable:false}));assert.equal(h.parts(0).state,'Heat · '+word);assert.equal(h.parts(0).tile.className,'thermostat-tile'+(quiet?' is-quiet':''));assert.equal(h.parts(0).up.disabled&&h.parts(0).down.disabled,true);assert.equal(h.parts(0).indoor,'69°');}
 assert.equal(launch({initial:signedIn({status:'stale',controllable:false}),clock:'24'}).parts(0).state,'Heat · Last update 08:55');
});
test('a failed change says Not changed on the tile and explains itself once in a toast',()=>{
 const h=launch({initial:signedIn()});
 h.push(signedIn({},{error:'rejected',message:'The thermostat did not accept the change.'}));assert.equal(h.parts(0).state,'Heat · Not changed');assert.equal(h.parts(0).tile.className,'thermostat-tile');assert.deepEqual(h.toasts,['The thermostat did not accept the change.']);
 h.push(signedIn({},{error:'rejected',message:'The thermostat did not accept the change.'}));assert.equal(h.toasts.length,1);
 h.parts(0).more.onclick();assert.deepEqual(menuText(h.parts(0).menu),['Mode','Heat','Cool']);
 h.push(signedIn());h.frame.stepResult={ok:false,error:'Honeywell could not be reached. Check Wi-Fi and try again.'};h.parts(0).up.onclick();assert.equal(h.parts(0).state,'Heat · Not changed');assert.equal(h.toasts.at(-1),'Honeywell could not be reached. Check Wi-Fi and try again.');assert.equal(h.toasts.length,2);
 const loaded=launch({initial:signedIn({},{error:'rejected',message:'Old failure.'})});assert.deepEqual(loaded.toasts,[]);
});
test('with no tiles to show, signed out is one notice with a Sign in button and loading shows nothing',()=>{
 const h=launch({initial:{...signedOut,status:'signed_out'}});
 assert.equal(h.tiles().length,1);assert.equal(h.tiles()[0].className,'thermostat-tile thermostat-notice');assert.equal(h.tiles()[0].all('thermostat-note')[0].textContent,'Thermostats signed out');
 const open=h.tiles()[0].all('secondary')[0];assert.equal(open.textContent,'Sign in');open.onclick();assert.deepEqual(h.opened,[['thermostats','overview']]);
 h.push(signedIn({status:'loading',controllable:false,polledAt:null,thermostats:[]}));assert.equal(h.tiles().length,0);assert.equal(h.$('thermostat-tiles').hidden,true);
 h.push(signedIn({thermostats:[]}));assert.equal(h.$('thermostat-tiles').hidden,true);
 h.push(signedIn({status:'unavailable',controllable:false,thermostats:[]}));assert.equal(h.tiles()[0].all('thermostat-note')[0].textContent,'Thermostats offline');assert.equal(h.tiles()[0].all('secondary')[0].textContent,'Settings');
 h.push(signedIn({status:'locked_out',controllable:false,retryAt:'2026-10-12T09:30:00Z',thermostats:[]}));assert.equal(h.tiles()[0].all('thermostat-note')[0].textContent,'Thermostats · Try again at 9:30');
 h.push(signedOut);assert.equal(h.$('thermostat-tiles').hidden,true);assert.equal(h.tiles().length,0);
});
test('names and messages from Honeywell are shown as text and malformed snapshots are harmless',()=>{
 const h=launch({initial:signedIn({account:'<b>x</b>@example.com'},{name:'<img src=x onerror=alert(1)>',message:'<script>1</script>',error:'x'})});
 assert.equal(h.parts(0).name,'<img src=x onerror=alert(1)>');assert.equal(h.$('thermostat-account-email').textContent,'<b>x</b>@example.com');
 assert.deepEqual([...new Set(h.$('thermostat-tiles').tags().concat(h.$('thermostat-list').tags()))].sort(),['button','div','span','strong']);
 h.push(signedIn({thermostats:[null,7,{id:'../x'},{id:'t3',name:'n'.repeat(90),indoor:'hot',setpoint:{},mode:'constructor',hold:'__proto__',holdUntil:'<b>',range:'x'}]}));
 assert.equal(h.tiles().length,1);assert.deepEqual([h.parts(0).name.length,h.parts(0).indoor,h.parts(0).setpoint,h.parts(0).state,h.parts(0).up.disabled],[40,'—','—','Mode unknown · Offline',true]);
 for(const bad of [null,'garbage','[]',42,'{"thermostats":"x"}'])h.api.receive(bad);assert.equal(h.tiles().length,0);assert.equal(h.$('thermostat-tiles').hidden,true);
});
test('sign-in sends the credentials once, clears the password and never stores it',()=>{
 const h=launch();h.submit('  frame@example.com ','hunter2!');
 assert.deepEqual(h.calls,[['signIn','frame@example.com','hunter2!']]);assert.equal(h.$('thermostat-password').value,'');assert.equal(h.$('thermostat-email').value,'  frame@example.com ');assert.equal(h.$('thermostat-status').textContent,'');assert.equal(h.$('thermostat-sign-in').textContent,'Signing in…');assert.equal(h.$('thermostat-sign-in').disabled,true);
 assert.deepEqual(h.stored,[]);assert.doesNotMatch(source,/localStorage|sessionStorage|indexedDB|document\.cookie|console\./);assert.doesNotMatch(JSON.stringify(h.api.status()),/hunter2/);
 h.push({...signedOut,signIn:{pending:true}});assert.equal(h.$('thermostat-sign-in').disabled,true);assert.equal(h.$('thermostat-sign-in').textContent,'Signing in…');assert.equal(h.$('thermostat-status').textContent,'');
 h.push({...signedOut,signIn:{ok:false,code:'bad_credentials',error:'That email or password was not accepted.',retryAt:null}});assert.equal(h.$('thermostat-email').value,'  frame@example.com ');assert.equal(h.$('thermostat-sign-in').textContent,'Sign in');
 h.push(signedIn());assert.equal(h.$('thermostat-form').hidden,true);assert.equal(h.$('thermostat-account').hidden,false);assert.equal(h.$('thermostat-account-email').textContent,'frame@example.com');assert.equal(h.$('thermostat-email').value,'');
 assert.deepEqual(h.$('thermostat-list').all('preference-row').map(r=>r.textContent),['Level-0Heat · 69° indoors','level-1Cool · 74° indoors']);assert.equal(h.$('thermostat-account-status').textContent,'Connected · Updated 8:55 a.m.');assert.equal(h.$('thermostat-status').textContent,'');
 h.submit('','x');h.submit('a@b','');assert.equal(h.calls.length,1);assert.equal(h.$('thermostat-password').value,'');
});
test('every sign-in failure and account status becomes a plain sentence',()=>{
 const h=launch();
 h.frame.signInResult={ok:false,error:'Enter the account email and password.'};h.submit('a@b','x');assert.equal(h.$('thermostat-status').textContent,'Enter the account email and password.');assert.equal(h.$('thermostat-password').value,'');
 h.window.Skylit.thermostatSignIn=()=>{throw Error('bridge gone')};h.submit('a@b','x');assert.equal(h.$('thermostat-status').textContent,'Could not start signing in. Try again.');
 h.push({...signedOut,signIn:{ok:false,code:'bad_credentials',error:'That email or password was not accepted.',retryAt:null}});assert.equal(h.$('thermostat-status').textContent,'That email or password was not accepted.');assert.equal(h.$('thermostat-sign-in').disabled,false);assert.equal(h.$('thermostat-form').hidden,false);
 h.push({...signedOut,signIn:{ok:false,code:'locked',error:'Too many attempts. Try again later.',retryAt:'2026-10-12T09:40:00Z'}});assert.equal(h.$('thermostat-status').textContent,'Too many sign-in attempts. Try again at 9:40 a.m.');
 h.push({...signedOut,signIn:{ok:false}});assert.equal(h.$('thermostat-status').textContent,'Could not sign in. Try again.');
 h.push({...signedOut,status:'signed_out'});assert.equal(h.$('thermostat-status').textContent,'Honeywell signed this frame out. Sign in again.');assert.equal(h.$('thermostat-form').hidden,false);
 for(const [extra,expected] of [[{status:'loading',controllable:false,polledAt:null,thermostats:[]},'Connected · Loading thermostats…'],[{status:'stale',controllable:false},'Trying again · Last updated 8:55 a.m.'],[{status:'unavailable',controllable:false},'Honeywell unavailable. Trying again.'],[{status:'locked_out',controllable:false,retryAt:'2026-10-12T10:05:00Z'},'Too many sign-in attempts. Try again at 10:05 a.m.'],[{status:'locked_out',controllable:false},'Too many sign-in attempts. Try again later.'],[{thermostats:[]},'Connected · Updated 8:55 a.m.']]){h.push(signedIn(extra));assert.equal(h.$('thermostat-account-status').textContent,expected);}
 assert.match(h.$('thermostat-list').textContent,/No thermostats were found/);
 const day=launch({initial:signedIn(),clock:'24'});assert.equal(day.$('thermostat-account-status').textContent,'Connected · Updated 08:55');
});
test('sign out takes two taps and reports a failure',()=>{
 const h=launch({initial:signedIn()}),out=h.$('thermostat-sign-out');
 out.onclick();assert.equal(h.calls.length,0);assert.equal(out.textContent,'Tap again to sign out');h.timers.at(-1)();assert.equal(out.textContent,'Sign out');
 out.onclick();out.onclick();assert.deepEqual(h.calls,[['signOut']]);assert.equal(out.textContent,'Sign out');
 h.push(signedOut);assert.equal(h.$('thermostat-form').hidden,false);assert.equal(h.tiles().length,0);
 h.push(signedIn());h.frame.refuse=true;out.onclick();out.onclick();assert.equal(h.$('thermostat-account-status').textContent,'Could not sign out. Try again.');
});
test('the frame polls faster only while the Overview is showing',()=>{
 const h=launch({initial:signedIn()});h.tab('overview');h.tab('calendar');h.tab('overview');
 assert.deepEqual(h.calls,[['watch',true],['watch',false],['watch',true]]);
});
for(const bridge of ['none','old'])test('without the thermostat bridge ('+bridge+') nothing is shown and sign-in is switched off',()=>{
 const h=launch({bridge});assert.equal(h.api.supported,false);assert.equal(h.$('thermostat-tiles').hidden,true);assert.equal(h.$('thermostat-sign-in').disabled,true);
 assert.match(h.$('thermostat-status').textContent,bridge==='old'?/Update the Skylit app/:/does not contact Honeywell/);
 h.submit('a@b','secret');assert.equal(h.$('thermostat-password').value,'');h.tab('overview');h.api.receive(signedIn());assert.equal(h.tiles().length,2);h.parts(0).up.onclick();assert.match(h.parts(0).state,/Not changed/);
});
test('a frame that starts on the Overview is polled at the watched pace from the first moment',()=>{
 assert.deepEqual(launch({initial:signedIn(),tab:'overview'}).calls,[['watch',true]]);
 assert.deepEqual(launch({initial:signedIn(),tab:'setup'}).calls,[]);
 assert.doesNotThrow(()=>launch({bridge:'old',tab:'overview'}));
});
