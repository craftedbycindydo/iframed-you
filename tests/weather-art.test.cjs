const {test}=require('node:test');
const assert=require('node:assert/strict');
const art=require('../web/weather-art.js');

test('each supported current weather condition has its own scene',()=>{
  const cases=[
    [0,'clear','Clear skies'],[1,'partly-cloudy','Partly cloudy'],
    [2,'partly-cloudy','Partly cloudy'],[3,'cloudy','Cloudy'],
    [45,'fog','Foggy'],[48,'fog','Foggy'],
    [51,'rain','Rain'],[61,'rain','Rain'],[67,'rain','Rain'],
    [71,'snow','Snow'],[77,'snow','Snow'],
    [80,'rain-showers','Rain showers'],[82,'rain-showers','Rain showers'],
    [85,'snow-showers','Snow showers'],[86,'snow-showers','Snow showers'],
    [95,'storm','Thunderstorms'],[99,'storm','Thunderstorms'],
  ];
  for(const [code,scene,label] of cases){
    assert.equal(art.describe(code).scene,scene,`WMO ${code}`);
    assert.equal(art.describe(code).label,label,`WMO ${code}`);
  }
  assert.equal(new Set(cases.map(([code])=>art.describe(code).scene)).size,9);
  assert.equal(art.describe(999).label,'Weather unavailable');
});

test('scene and day/night state update the same card',()=>{
  const classes=new Set();
  const element={dataset:{},classList:{toggle(name,on){if(on)classes.add(name);else classes.delete(name)}}};
  art.apply(element,95,0);
  assert.equal(element.dataset.weather,'storm');
  assert.ok(classes.has('night'));
  art.apply(element,0,1);
  assert.equal(element.dataset.weather,'clear');
  assert.ok(!classes.has('night'));
});
