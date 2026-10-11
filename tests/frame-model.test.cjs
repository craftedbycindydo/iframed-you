const {test}=require('node:test'),assert=require('node:assert/strict');
const model=require('../web/frame-model.js');
const photo=n=>({id:String(n).padStart(64,'0'),url:'https://appassets.androidplatform.net/private-photos/'+String(n).padStart(64,'0')+'.jpg'});
test('photo choices exclude hidden pictures everywhere and preserve stable IDs after reorder',()=>{
 const photos=[photo(1),photo(2),photo(3)],raw={[photo(1).id]:{hidden:true},[photo(2).id]:{favourite:true,fit:'contain',caption:'Portrait'}};
 const curated=model.curation(raw,photos.slice().reverse());
 assert.deepEqual(model.pictures(photos,curated).map(p=>p.id),[photo(2).id,photo(3).id]);
 assert.deepEqual(model.pictures(photos,curated,{favouritesOnly:true}).map(p=>p.id),[photo(2).id]);
 assert.deepEqual(model.overviewPictures(photos,curated,{preferFavourites:true}).map(p=>p.id),[photo(2).id,photo(3).id]);
 assert.equal(curated[photo(2).id].caption,'Portrait');
 assert.deepEqual(Object.keys(model.curation(curated,[photo(3)])),[]);
});
test('quiet hours follow configured time and both occurrences of the autumn DST hour',()=>{
 const p={quiet:true,quietStart:'22:00',quietEnd:'07:00'};
 assert.equal(model.quietAt(p,new Date('2026-10-11T01:59Z'),'America/Toronto'),false);
 assert.equal(model.quietAt(p,new Date('2026-10-11T02:00Z'),'America/Toronto'),true);
 assert.equal(model.quietAt(p,new Date('2026-10-11T11:00Z'),'America/Toronto'),false);
 for(const t of ['2026-11-01T05:30Z','2026-11-01T06:30Z'])assert.equal(model.quietAt(p,new Date(t),'America/Toronto'),true);
 assert.equal(model.quietAt({...p,quietStart:'07:00',quietEnd:'07:00'},new Date(),'UTC'),false);
 assert.equal(model.quietAt(p,new Date(),'invalid zone'),false);
});
test('display transfer never exports household content or service secrets and rejects extra fields',()=>{
 const secret={album:'private',email:'private',calendar:'private',city:{name:'private'},note:'private',senders:['private'],password:'private'};
 const exported=model.exportPreferences({...secret,text:'large',preset:'photos'},{...secret,theme:'sage',mode:'dark',clock:'24'});
 assert.doesNotMatch(JSON.stringify(exported),/private|album|password|city|note|senders/);
 const display=model.importPreferences(exported);assert.equal(display.theme,'sage');assert.equal(display.text,'large');
 assert.throws(()=>model.importPreferences({...exported,account:'secret'}));
 assert.throws(()=>model.importPreferences({...exported,display:{...exported.display,album:'secret'}}));
});
test('local utility records are bounded, invalid dates rejected, and countdown days survive DST',()=>{
 const h=model.household({note:'a'.repeat(900),shopping:Array.from({length:80},(_,i)=>({id:String(i),text:'b'.repeat(200),done:true})),countdowns:[{title:'bad',date:'2026-02-30'}],timers:[{id:'x',end:NaN}]});
 assert.equal(h.note.length,600);assert.equal(h.shopping.length,60);assert.equal(h.shopping[0].text.length,100);assert.equal(h.countdowns.length,0);assert.equal(h.timers.length,0);
 assert.equal(model.dayDelta('2026-11-02','2026-10-31'),2);
});
test('curated YouTube links normalize only known video/playlist routes',()=>{
 assert.equal(model.youtubeLink('https://m.youtube.com/watch?v=abcdefghijk&tracking=x'),'https://www.youtube.com/watch?v=abcdefghijk');
 for(const value of ['http://youtube.com/watch?v=abcdefghijk','https://youtube.com.evil.test/watch?v=abcdefghijk','https://owner@youtube.com/watch?v=abcdefghijk','https://youtube.com:443/watch?v=abcdefghijk#token','https://youtube.com/embed/abcdefghijk','https://youtube.com/watch?v=short'])assert.equal(model.youtubeLink(value),null,value);
});
