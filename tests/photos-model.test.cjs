const test=require('node:test');
const assert=require('node:assert/strict');
const Photos=require('../web/photos-model.js');

test('only a private local photo URL is accepted for slideshow images',()=>{
  const id='a'.repeat(64),good='https://appassets.androidplatform.net/private-photos/'+id+'.jpg';
  assert.equal(Photos.safePhoto(good),good);
  for(const bad of ['https://appassets.androidplatform.net.evil.test/private-photos/'+id+'.jpg','http://appassets.androidplatform.net/private-photos/'+id+'.jpg','https://appassets.androidplatform.net/private-photos/../index.html','https://appassets.androidplatform.net/private-photos/'+id+'.jpg?x=1'])assert.equal(Photos.safePhoto(bad),null);
});

test('malformed native status cannot provide external images or unsafe limits',()=>{
  const id='b'.repeat(64),good='https://appassets.androidplatform.net/private-photos/'+id+'.jpg';
  const state=Photos.normalize(JSON.stringify({connected:true,email:'person@example.invalid',days:365,maximum:999,lastSync:-1,photos:[{url:good,at:123},{url:'https://example.com/secret.jpg'}]}));
  assert.equal(state.photos.length,1);
  assert.equal(state.photos[0].url,good);
  assert.equal(state.days,30);assert.equal(state.maximum,30);assert.equal(state.lastSync,0);
  assert.match(Photos.caption(state),/not yet verified|verify mail access/);
});

test('last check displays in the configured city time rather than Android timezone',()=>{
  const checked=Date.UTC(2026,9,10,22,26,0);
  const status={connected:true,busy:false,error:'',lastSync:checked,photos:[{},{}]};
  const caption=Photos.caption(status,'America/Toronto');
  assert.match(caption,/2 saved/);
  assert.match(caption,/6:26/);
  assert.doesNotMatch(caption,/10:26/);
});

test('retention accepts recent-day and count modes with bounded persistent exclusions',()=>{
 for(const days of [0,7,30,90,180])assert.equal(Photos.normalize({days}).days,days);
 for(const days of [-1,1,365,Infinity,'30'])assert.equal(Photos.normalize({days}).days,30);
 const id='a'.repeat(64),state=Photos.normalize({excluded:[id,id,'../file','https://example.invalid/photo.jpg',null]});
 assert.deepEqual(state.excluded,[id]);
 assert.equal(Photos.normalize({excluded:Array.from({length:5000},(_,i)=>i.toString(16).padStart(64,'0'))}).excluded.length,4096);
});
