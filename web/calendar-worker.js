/* Parsing and recurrence expansion stay off the touch/UI thread. */
importScripts('ical.js','calendar-model.js');
onmessage=function(e){const m=e.data;try{postMessage({events:CalendarModel.parse(m.body,m.from,m.to,m.zone)});}catch(error){postMessage({error:'Could not read this calendar. Check its iCal format, timezone definitions, or recurrence complexity.'});}};
