const {test}=require('node:test'),assert=require('node:assert/strict');
const P=require('../web/calendar-policy.js');
test('review mode shows own and approved organizers and groups unapproved events',()=>{
 const policy=P.clean({enabled:true,owner:'Family@Example.test',approved:['friend@example.test']});
 const items=[{organizer:'family@example.test'},{organizer:'FRIEND@example.test'},{organizer:'new@example.test'},{organizer:'new@example.test'},{organizer:''}];
 assert.deepEqual(items.map(e=>P.allowed(e,policy)),[true,true,false,false,false]);
 assert.deepEqual(P.pending(items,policy),[{address:'new@example.test',count:2},{address:'',count:1}]);
 assert.equal(P.allowed({organizer:''},{...policy,unattributed:true}),true);
});
test('approval is exact, bounded, reversible and off by default',()=>{
 const initial=P.clean({approved:['FRIEND@example.test','friend@example.test','bad value']});
 assert.deepEqual(initial.approved,['friend@example.test']);
 assert(P.allowed({organizer:'stranger@example.test'},initial));
 const active=P.approve({...initial,enabled:true},'stranger@example.test');
 assert(P.allowed({organizer:'stranger@example.test'},active));
 assert(!P.allowed({organizer:'other@stranger.example.test'},active));
 assert(!P.allowed({organizer:'stranger@example.test'},P.revoke(active,'stranger@example.test')));
});
