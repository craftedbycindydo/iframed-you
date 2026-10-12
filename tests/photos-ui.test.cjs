const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const model=require('../web/photos-model.js'),playback=require('../web/photo-playback.js'),frame=require('../web/frame-model.js');
const source=fs.readFileSync('web/photos.js','utf8');
class Element{
 constructor(tag='div'){this.tag=tag;this.children=[];this.childNodes=[];this.options=[];this.dataset={};this.attrs={};this.found=new Map();this.lists=new Map();this.value='';this.hidden=false;this.disabled=false;this.isConnected=true;this._text='';this.className='';
  this.style={setProperty(){}};this.classList={toggle(){},add(){},remove(){},contains:()=>false};}
 set textContent(v){this._text=String(v);this.children=[]}get textContent(){return this._text+this.children.map(c=>c.textContent||'').join('')}
 set innerHTML(v){}
 append(...c){this.children.push(...c)}replaceChildren(...c){this._text='';this.children=c}after(){}insertBefore(){}remove(){}
 setAttribute(k,v){this.attrs[k]=v}removeAttribute(k){delete this.attrs[k]}addEventListener(){}focus(){}getClientRects(){return []}click(){if(this.onclick)this.onclick()}
 querySelector(s){if(!this.found.has(s))this.found.set(s,new Element());return this.found.get(s)}
 querySelectorAll(s){if(!this.lists.has(s))this.lists.set(s,[0,1,2,3].map(()=>new Element()));return this.lists.get(s)}
}
const url=n=>'https://appassets.androidplatform.net/private-photos/'+String(n).padStart(64,'0')+'.jpg';
const library=n=>Array.from({length:n},(_,i)=>({url:url(i+1),at:1760000000000+i}));
function launch({connected=false,photos=0,saved=null,album='',bridge=true}={}){
 const elements=new Map(),created=[],calls=[],values=new Map(),routes=[];if(saved)values.set('skylit.photoSource',saved);
 const document={hidden:false,activeElement:null,body:new Element('body'),found:new Map(),createElement:tag=>{const e=new Element(tag);created.push(e);return e},createTextNode:text=>({nodeType:3,textContent:text}),getElementById:id=>{if(!elements.has(id))elements.set(id,new Element());return elements.get(id)},querySelector(s){if(!this.found.has(s))this.found.set(s,new Element());return this.found.get(s)},addEventListener(){}};
 const $=document.getElementById;$('album-url').value=album;
 let status={connected,email:'',days:30,maximum:30,lastSync:connected?1760000000000:0,busy:false,epoch:'e',interval:86400,imported:0,visited:0,skipped:0,trusted:false,error:'',photos:library(photos),excluded:[]};
 const native={photoStatus:()=>JSON.stringify(status),photoSource:value=>calls.push(['source',value]),photoOpen:idle=>calls.push(['open',idle]),photoBrowse:index=>calls.push(['browse',index]),photoRefresh:()=>calls.push(['refresh']),openPhotos:(link,idle)=>calls.push(['album',link,idle]),localPhotoClosed(){}};
 const window={SkylitPhotoModel:model,SkylitPhotoPlayback:playback,SkylitFrameModel:frame,SkylitApp:{calendarPreferences:()=>({timezone:'UTC',clock:'24'}),notify(){},go:tab=>routes.push(tab),openSettings:(...a)=>routes.push(['settings',...a])},addEventListener(){},dispatchEvent(){},scrollY:0,scrollTo(){},open:(...a)=>calls.push(['window',...a])};
 if(bridge)window.Skylit=native;
 vm.runInNewContext(source,{window,document,localStorage:{getItem:k=>values.has(k)?values.get(k):null,setItem:(k,v)=>values.set(k,String(v))},Event:class{},setTimeout:()=>0,clearTimeout(){},setInterval:()=>0,clearInterval(){},Intl,Date,JSON,Math});
 const page=$('photos');
 return {$,calls,routes,window,workspace:created.find(e=>e.className==='photo-workspace'),feature:page.querySelector('.photo-feature'),details:page.querySelector('.two-cards'),settingsLink:page.querySelector('.photo-copy .quiet'),tiles:()=>$('photo-tiles').children.filter(c=>c.className==='photo-tile-card'),push:next=>{status={...status,...next};window.SkylitPhotos.receive(status)}};
}

test('phone pictures are usable without Gmail or an album',()=>{
 const h=launch({photos:3});
 assert.equal(h.workspace.hidden,false);assert.equal(h.feature.hidden,true);assert.equal(h.details.hidden,true);assert.equal(h.tiles().length,3);
 assert.equal(h.$('photo-play').disabled,false);assert.equal(h.$('photo-mail-status').textContent,'3 saved on this frame');assert.equal(h.$('photo-check').hidden,true);assert.doesNotMatch(h.$('photo-tiles').textContent+h.$('photo-mail-status').textContent,/Gmail|inbox/i);
 assert.equal(h.$('overview-photos').hidden,false);assert.equal(h.$('overview-photo-stack').children.length,3);
 h.$('photo-play').onclick();assert.deepEqual(h.calls.at(-1),['open',false]);
 h.tiles()[1].children[0].onclick();assert.deepEqual(h.calls.at(-1),['browse',1]);
 h.$('start-photos').onclick();assert.deepEqual(h.calls.at(-1),['open',false]);
 h.$('test-idle').onclick();assert.deepEqual(h.calls.at(-1),['open',true]);
 assert.equal(h.window.SkylitPhotos.open(false),true);assert.equal(h.window.SkylitPhotos.isOpen(),true);assert.equal(h.$('photo-counter').textContent,'1 / 3');h.window.SkylitPhotos.close();
 assert.equal(h.window.SkylitPhotos.open(false,2,false),true);assert.equal(h.$('photo-counter').textContent,'3 / 3');h.window.SkylitPhotos.close();
 assert.equal(h.window.SkylitPhotos.health().configured,false);
});
test('a phone upload arriving later reveals the library and Overview prints',()=>{
 const h=launch();
 assert.equal(h.workspace.hidden,true);assert.equal(h.feature.hidden,false);assert.equal(h.$('overview-photos').hidden,true);assert.equal(h.$('photo-play').disabled,true);
 h.$('start-photos').onclick();assert.equal(h.calls.some(c=>c[0]==='open'),false);
 h.push({photos:library(2)});
 assert.equal(h.workspace.hidden,false);assert.equal(h.feature.hidden,true);assert.equal(h.tiles().length,2);assert.equal(h.$('overview-photo-stack').children.length,2);assert.equal(h.$('photo-play').disabled,false);
 h.push({photos:[]});assert.equal(h.workspace.hidden,true);assert.equal(h.feature.hidden,false);assert.equal(h.$('overview-photos').hidden,true);
});
test('an empty library without Gmail mentions the phone app, not only Gmail',()=>{
 const h=launch({saved:'email'});
 assert.match(h.$('photo-tiles').textContent,/phone app/);assert.match(h.$('photo-mail-status').textContent,/phone app/);
 assert.match(model.caption(model.normalize({}),'UTC'),/phone app/);assert.equal(model.caption(model.normalize({photos:library(2)}),'UTC'),'2 saved on this frame');
});
test('the Google album flow is unchanged, and keeps its card beside phone pictures',()=>{
 const link='https://photos.app.goo.gl/example',empty=launch({album:link});
 assert.equal(empty.workspace.hidden,true);assert.equal(empty.feature.hidden,false);assert.equal(empty.details.hidden,false);assert.equal(empty.$('overview-photos').hidden,true);
 empty.$('start-photos').onclick();assert.deepEqual(empty.calls.at(-1),['album',link,false]);empty.$('test-idle').onclick();assert.deepEqual(empty.calls.at(-1),['album',link,true]);
 const both=launch({album:link,photos:2});
 assert.equal(both.workspace.hidden,false);assert.equal(both.feature.hidden,false);
 both.$('start-photos').onclick();assert.deepEqual(both.calls.at(-1),['album',link,false]);both.$('test-idle').onclick();assert.deepEqual(both.calls.at(-1),['album',link,true]);
 both.$('photo-play').onclick();assert.deepEqual(both.calls.at(-1),['open',false]);
 let opened=0;const none=launch();none.settingsLink.click=()=>opened++;none.$('start-photos').onclick();assert.equal(opened,1);
});
test('the email flow is unchanged',()=>{
 const h=launch({connected:true,photos:2,saved:'email'});
 assert.equal(h.workspace.hidden,false);assert.equal(h.feature.hidden,true);assert.equal(h.tiles().length,2);assert.match(h.$('photo-mail-status').textContent,/2 saved · Checked/);assert.equal(h.$('photo-check').disabled,false);assert.equal(h.$('photo-check').hidden,false);assert.equal(h.$('overview-photo-stack').children.length,2);
 h.$('start-photos').onclick();assert.deepEqual(h.calls.at(-1),['open',false]);h.$('test-idle').onclick();assert.deepEqual(h.calls.at(-1),['open',true]);
 assert.equal(h.window.SkylitPhotos.health().configured,true);
 const waiting=launch({connected:true,saved:'email'});let checks=0;waiting.$('photo-check').onclick=()=>checks++;waiting.$('start-photos').onclick();assert.equal(checks,1);assert.match(waiting.$('photo-tiles').textContent,/Check now/);
 let opened=0;const fresh=launch({saved:'email'});fresh.settingsLink.click=()=>opened++;fresh.$('start-photos').onclick();assert.equal(opened,1);assert.equal(fresh.$('photo-check').disabled,true);
});
