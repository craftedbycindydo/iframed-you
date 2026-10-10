/* Local display rules. Google Calendar remains the source of event truth. */
(function(root,factory){if(typeof module==='object'&&module.exports)module.exports=factory();else root.SkylitCalendarPolicy=factory();})(typeof self!=='undefined'?self:this,function(){
'use strict';
const MAX_SENDERS=100;
function email(value){const v=String(value||'').trim().toLowerCase();return v.length<=254&&/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(v)?v:'';}
function clean(input){const x=input&&typeof input==='object'?input:{};const approved=[];for(const item of Array.isArray(x.approved)?x.approved:[]){const address=email(item);if(address&&!approved.includes(address)&&approved.length<MAX_SENDERS)approved.push(address);}return {enabled:x.enabled===true,owner:email(x.owner),approved,unattributed:x.unattributed===true};}
function allowed(event,policy){const p=clean(policy);if(!p.enabled)return true;const address=email(event&&event.organizer);return address?address===p.owner||p.approved.includes(address):p.unattributed;}
function pending(events,policy){const p=clean(policy),groups=new Map();if(!p.enabled)return [];for(const e of events){if(allowed(e,p))continue;const address=email(e.organizer);const key=address||'';if(!groups.has(key))groups.set(key,{address,count:0});groups.get(key).count++;}return [...groups.values()].sort((a,b)=>b.count-a.count||a.address.localeCompare(b.address));}
function approve(policy,address){const p=clean(policy),value=email(address);if(!value||p.approved.length>=MAX_SENDERS)return p;if(value!==p.owner&&!p.approved.includes(value))p.approved.push(value);return p;}
function revoke(policy,address){const p=clean(policy),value=email(address);p.approved=p.approved.filter(item=>item!==value);return p;}
return {email,clean,allowed,pending,approve,revoke,MAX_SENDERS};
});
