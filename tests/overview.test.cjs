const {test}=require('node:test');const assert=require('node:assert/strict');const M=require('../web/overview-model.js');
test('upcoming omits finished events, retains ongoing events and respects all-day exclusive ends',()=>{
 const now=Date.parse('2026-10-10T12:00Z');const e=(title,props)=>Object.assign({title,startDay:'2026-10-10',start:now+3600000,end:now+7200000},props);
 const events=[e('done',{end:now}),e('ongoing',{start:now-10000}),e('all day',{allDay:true,endDay:'2026-10-11'}),e('yesterday',{allDay:true,startDay:'2026-10-09',endDay:'2026-10-10'}),e('later',{startDay:'2026-10-11',start:now+86400000,end:now+90000000})];
 assert.deepEqual(M.upcoming(events,'2026-10-10',now).map(e=>e.title),['all day','ongoing','later']);
 assert.equal(M.upcoming(events,'2026-10-10',now,1).length,1);assert.equal(events[0].title,'done');
});
test('weather distinguishes fresh, stale, absent and invalid observations',()=>{
 const data={current:{temperature_2m:18.7,weather_code:3},fetchedAt:1000};
 assert.equal(M.weather(data,1801000).stale,false);assert.equal(M.weather(data,1801001).stale,true);
 assert.equal(M.weather(data).temperature,19);assert.equal(M.weather(null),null);assert.equal(M.weather({current:{temperature_2m:null}}),null);
});
