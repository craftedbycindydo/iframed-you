const {test}=require('node:test'),assert=require('node:assert/strict');
const model=require('../web/household-model.js');
const base=()=>model.normalize({rev:4,people:[{id:'p1',name:'Maya',color:'#00a36c'},{id:'p2',name:'Sam',color:'#2D5BFF'}],chores:[
 {id:'c1',title:'Make bed',emoji:'🛏️',personId:'p1',days:[1,2,3,4,5],done:['2026-10-12']},
 {id:'c2',title:'Feed dog',personId:'p2',days:[],done:[]},
 {id:'c3',title:'Recycling',personId:null,days:[0,6],done:['2026-10-11']},
 {id:'c4',title:'Homework',personId:'p1',days:[1],done:[]}],shopping:[{id:'s1',name:'Milk',qty:2,note:'',done:false},{id:'s2',name:'Tea',done:true}]});
const context={id:(()=>{let n=0;return()=>'new'+(++n)})(),today:'2026-10-12'};

test('due-today follows weekdays, with empty days meaning every day',()=>{
 const s=base(),due=date=>s.chores.filter(c=>model.dueOn(c,date)).map(c=>c.id);
 assert.equal(model.weekday('2026-10-11'),0);assert.equal(model.weekday('2026-10-17'),6);
 assert.deepEqual(due('2026-10-11'),['c2','c3']);
 assert.deepEqual(due('2026-10-12'),['c1','c2','c4']);
 assert.deepEqual(due('2026-10-13'),['c1','c2']);
 assert.deepEqual(due('2026-10-17'),['c2','c3']);
 for(let i=0;i<7;i++)assert.equal(model.dueOn(s.chores[1],model.shiftDate('2026-10-11',i)),true);
});
test('local date keys use the chosen zone and survive an invalid one',()=>{
 const now=new Date('2026-10-12T03:30:00Z');
 assert.equal(model.dateKey(now,'America/Edmonton'),'2026-10-11');assert.equal(model.dateKey(now,'Europe/London'),'2026-10-12');
 assert.match(model.dateKey(now,'Not/AZone'),/^\d{4}-\d{2}-\d{2}$/);
});
test('today view groups by person with Anyone last and reports progress',()=>{
 const monday=model.today(base(),'2026-10-12');
 assert.deepEqual(monday.groups.map(g=>g.person?g.person.name:'Anyone'),['Maya','Sam']);
 assert.deepEqual(monday.groups.map(g=>[g.done,g.total]),[[1,2],[0,1]]);assert.deepEqual([monday.done,monday.total],[1,3]);
 assert.equal(monday.groups[0].rows[0].done,true);assert.equal(monday.groups[0].rows[1].done,false);
 const sunday=model.today(base(),'2026-10-11');
 assert.deepEqual(sunday.groups.map(g=>g.person?g.person.name:'Anyone'),['Sam','Anyone']);assert.deepEqual([sunday.done,sunday.total],[1,2]);
 assert.deepEqual(model.today(model.normalize({}),'2026-10-12'),{date:'2026-10-12',groups:[],done:0,total:0});
});
test('done toggles per date and keeps only the last fourteen days',()=>{
 let s=base();
 s=model.apply(s,{op:'chore.done',id:'c2',date:'2026-10-12',done:true},context).snapshot;assert.equal(model.isDone(s.chores[1],'2026-10-12'),true);assert.equal(model.isDone(s.chores[1],'2026-10-11'),false);assert.equal(s.rev,5);
 s=model.apply(s,{op:'chore.done',id:'c2',date:'2026-10-12',done:true},context).snapshot;assert.deepEqual(s.chores[1].done,['2026-10-12']);
 s=model.apply(s,{op:'chore.done',id:'c2',date:'2026-10-12',done:false},context).snapshot;assert.deepEqual(s.chores[1].done,[]);
 s.chores[1].done=['2026-09-28','2026-09-29'];
 s=model.apply(s,{op:'chore.done',id:'c2',date:'2026-10-12',done:true},context).snapshot;assert.deepEqual(s.chores[1].done,['2026-09-29','2026-10-12']);
 assert.equal(model.apply(s,{op:'chore.done',id:'c2',date:'2026-02-30',done:true},context).ok,false);
 assert.equal(model.apply(s,{op:'chore.done',id:'gone',date:'2026-10-12',done:true},context).ok,false);
});
test('normalisation tolerates malformed snapshots without throwing',()=>{
 for(const raw of [null,undefined,'x',42,[],{people:'no',chores:{},shopping:7}])assert.deepEqual(model.normalize(raw),{rev:0,people:[],chores:[],shopping:[]});
 const s=model.normalize({rev:-2,people:[null,{id:'',name:'x'},{id:'p1',name:'  Maya  ',color:'red'},{id:'p1',name:'Duplicate'},{id:'p2',name:'   '},...Array.from({length:20},(_,i)=>({id:'x'+i,name:'N'+i,color:'#abcdef'}))],
  chores:[{id:'c1',title:'T'.repeat(200),emoji:7,personId:'missing',days:[1,1,9,'2',-1,6],done:['2026-10-12','nope','2026-13-01','2026-10-12']},{id:'c2'},{title:'no id'}],
  shopping:[{id:'s1',name:'Milk',qty:500,note:5,done:'yes'},{id:'s2',name:''},{id:'s3',name:'Eggs',qty:12,note:'n'.repeat(500),done:true}]});
 assert.equal(s.rev,0);assert.equal(s.people.length,12);assert.deepEqual(s.people[0],{id:'p1',name:'Maya',color:model.colors[0][0]});assert.equal(s.people[1].color,'#ABCDEF');
 assert.deepEqual(s.chores,[{id:'c1',title:'T'.repeat(80),emoji:'',personId:null,days:[1,6],done:['2026-10-12']}]);
 assert.deepEqual(s.shopping.map(x=>[x.id,x.qty,x.note.length,x.done]),[['s1',1,0,false],['s3',12,200,true]]);
 assert.equal(model.normalize({chores:Array.from({length:150},(_,i)=>({id:'c'+i,title:'t'}))}).chores.length,100);
 assert.equal(model.normalize({shopping:Array.from({length:250},(_,i)=>({id:'s'+i,name:'n'}))}).shopping.length,200);
});
test('validation mirrors the contract limits',()=>{
 const s=base(),bad=op=>assert.notEqual(model.check(s,op),'',JSON.stringify(op)),good=op=>assert.equal(model.check(s,op),'',JSON.stringify(op));
 good({op:'person.add',name:'A',color:'#123abc'});good({op:'person.add',name:'n'.repeat(80),color:'#123ABC'});
 for(const op of [{op:'person.add',name:'   ',color:'#123abc'},{op:'person.add',name:'n'.repeat(81),color:'#123abc'},{op:'person.add',name:'A',color:'blue'},{op:'person.add',name:'A'},{op:'person.update',id:'nope',name:'A'},{op:'person.update',id:'p1',color:'#12'},{op:'person.remove',id:'nope'}])bad(op);
 good({op:'chore.add',title:'Sweep'});good({op:'chore.add',title:'Sweep',emoji:'👨‍👩‍👧‍👦',personId:null,days:[0,6]});good({op:'chore.update',id:'c1',days:[]});
 for(const op of [{op:'chore.add',title:''},{op:'chore.add',title:'x',personId:'nope'},{op:'chore.add',title:'x',days:[7]},{op:'chore.add',title:'x',days:[1,1]},{op:'chore.add',title:'x',days:'mon'},{op:'chore.add',title:'x',emoji:'😀'.repeat(9)},{op:'chore.update',id:'zz',title:'x'},{op:'chore.remove',id:'zz'}])bad(op);
 good({op:'item.add',name:'Eggs'});good({op:'item.add',name:'Eggs',qty:99,note:''});good({op:'item.update',id:'s1',done:true});good({op:'items.clearDone'});
 for(const op of [{op:'item.add',name:''},{op:'item.add',name:'x',qty:0},{op:'item.add',name:'x',qty:100},{op:'item.add',name:'x',qty:1.5},{op:'item.update',id:'s1',done:'yes'},{op:'item.update',id:'zz',done:true},{op:'item.remove',id:'zz'},{op:'unknown'},null])bad(op);
 const full=model.normalize({people:Array.from({length:12},(_,i)=>({id:'p'+i,name:'P',color:'#000000'})),chores:Array.from({length:100},(_,i)=>({id:'c'+i,title:'t'})),shopping:Array.from({length:200},(_,i)=>({id:'s'+i,name:'n'}))});
 assert.match(model.check(full,{op:'person.add',name:'A',color:'#000000'}),/12/);assert.match(model.check(full,{op:'chore.add',title:'A'}),/100/);assert.match(model.check(full,{op:'item.add',name:'A'}),/full/);
 assert.equal(model.check(full,{op:'person.update',id:'p0',name:'B'}),'');
});
test('the preview store applies every operation and leaves its input untouched',()=>{
 const start=base(),frozen=JSON.stringify(start);let s=start;const run=op=>{const r=model.apply(s,op,context);assert.equal(r.ok,true,JSON.stringify(op));s=r.snapshot;};
 run({op:'person.add',name:' Priya ',color:'#abcdef'});assert.deepEqual(s.people[2],{id:s.people[2].id,name:'Priya',color:'#ABCDEF'});
 run({op:'person.update',id:'p1',name:'Maya R'});assert.equal(s.people[0].name,'Maya R');assert.equal(s.people[0].color,'#00A36C');
 run({op:'chore.add',title:'Sweep',emoji:'🧹',personId:'p2',days:[6,0]});assert.deepEqual(s.chores[4],{id:s.chores[4].id,title:'Sweep',emoji:'🧹',personId:'p2',days:[0,6],done:[]});
 run({op:'chore.update',id:'c1',personId:null});assert.equal(s.chores[0].personId,null);assert.equal(s.chores[0].title,'Make bed');
 run({op:'person.remove',id:'p2'});assert.equal(s.people.some(p=>p.id==='p2'),false);assert.equal(s.chores.filter(c=>c.personId==='p2').length,0);assert.equal(s.chores.length,5);
 run({op:'chore.remove',id:'c4'});assert.equal(s.chores.length,4);
 run({op:'item.add',name:'Eggs',qty:6});assert.deepEqual(s.shopping[2],{id:s.shopping[2].id,name:'Eggs',qty:6,note:'',done:false});
 run({op:'item.update',id:'s1',done:true,note:'whole'});run({op:'items.clearDone'});assert.deepEqual(s.shopping.map(x=>x.name),['Eggs']);
 run({op:'item.remove',id:s.shopping[0].id});assert.equal(s.shopping.length,0);
 assert.equal(s.rev,14);assert.equal(JSON.stringify(start),frozen);
 const failed=model.apply(s,{op:'item.remove',id:'gone'},context);assert.equal(failed.ok,false);assert.equal(typeof failed.error,'string');
});
test('day summaries and avatar ink are readable',()=>{
 assert.equal(model.describeDays([]),'Every day');assert.equal(model.describeDays([1,2,3,4,5]),'Weekdays');assert.equal(model.describeDays([0,6]),'Weekends');assert.equal(model.describeDays([1,3]),'Mon, Wed');
 assert.equal(model.ink('#000000'),'#ffffff');assert.equal(model.ink('#FFFFFF'),'#1c1814');assert.equal(model.ink('bad'),'#ffffff');
 for(const [value] of model.colors)assert.match(value,/^#[0-9A-F]{6}$/);
});
