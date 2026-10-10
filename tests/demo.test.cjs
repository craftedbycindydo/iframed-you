const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
test('demo mocks only forecast requests and lets other fetches load normally',async()=>{
 const calls=[],window={fetch:async url=>{calls.push(url);return 'real response'}};
 vm.runInNewContext(fs.readFileSync('tests/fixtures/demo.js','utf8'),{Date,URLSearchParams,location:{search:''},window,localStorage:{getItem:()=>null,setItem(){}},document:{createElement:()=>({style:{}}),body:{append(){}}},setTimeout});
 const forecast=await window.fetch('https://api.open-meteo.com/v1/forecast?latitude=51');assert.equal((await forecast.json()).current.temperature_2m,17);
 assert.equal(await window.fetch('/momo-routine.js'),'real response');assert.deepEqual(calls,['/momo-routine.js']);
});
