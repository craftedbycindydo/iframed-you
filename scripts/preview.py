#!/usr/bin/env python3
"""Loopback-only, isolated public demo. Never reads household configuration."""
import argparse
import json
import shutil
from functools import partial
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from tempfile import TemporaryDirectory
from assets import stage_assets


DEMO_HOUSEHOLD = {
    'snapshot': {
        'rev': 1,
        'people': [{'id': 'p1', 'name': 'Maya', 'color': '#9A513B'}, {'id': 'p2', 'name': 'Sam', 'color': '#547D91'}],
        'chores': [
            {'id': 'c1', 'title': 'Make bed', 'emoji': '🛏️', 'personId': 'p1', 'days': [], 'done': ['2026-10-10']},
            {'id': 'c2', 'title': 'Water the plants', 'emoji': '🪴', 'personId': 'p1', 'days': [3, 6], 'done': []},
            {'id': 'c3', 'title': 'Pack school bag', 'emoji': '📚', 'personId': 'p1', 'days': [1, 2, 3, 4, 5], 'done': []},
            {'id': 'c4', 'title': 'Feed the dog', 'emoji': '🐕', 'personId': 'p2', 'days': [], 'done': ['2026-10-10']},
            {'id': 'c5', 'title': 'Set the table', 'emoji': '🍽️', 'personId': 'p2', 'days': [], 'done': []},
            {'id': 'c6', 'title': 'Take out recycling', 'emoji': '🗑️', 'personId': None, 'days': [6], 'done': []},
        ],
        'shopping': [
            {'id': 's1', 'name': 'Milk', 'qty': 2, 'note': '', 'done': False},
            {'id': 's2', 'name': 'Bread', 'qty': 1, 'note': 'Sourdough', 'done': False},
            {'id': 's3', 'name': 'Apples', 'qty': 1, 'note': '', 'done': True},
        ],
    },
    'pairing': {'devices': [{'id': 'd1', 'name': 'Example phone', 'pairedAt': '2026-10-08T17:30:00Z', 'lastSeen': '2026-10-10T08:15:00Z'}]},
}
DEMO_HOUSEHOLD_SCRIPT = "if(!localStorage.getItem('skylit.household.preview'))localStorage.setItem('skylit.household.preview',JSON.stringify(%s));\n" % json.dumps(DEMO_HOUSEHOLD)

DEMO_ICLOUD_SCRIPT = """(()=>{
let status=null;
const base=window.Skylit.photoStatus;
const extra=['lake','orchard','marigolds'].map((name,i)=>({id:String(90+i).padStart(64,'0'),url:'demo-photos/'+name+'.png',at:Date.now()}));
const push=()=>{if(window.SkylitICloud)window.SkylitICloud.receive(status);if(window.SkylitPhotos)window.SkylitPhotos.receive(window.Skylit.photoStatus())};
const finish=()=>setTimeout(()=>{if(!status)return;status=Object.assign({},status,{count:extra.length,lastSync:new Date().toISOString(),syncing:false});push()},1500);
window.Skylit.photoStatus=()=>{const row=JSON.parse(base());if(status&&status.count)row.photos=row.photos.concat(extra);return JSON.stringify(row)};
Object.assign(window.Skylit,{
icloudStatus:()=>JSON.stringify(status),
icloudConnect(url){if(!/^https:\\/\\/(www\\.icloud\\.com\\/sharedalbum\\/#|share\\.icloud\\.com\\/photos\\/)[A-Za-z0-9_-]+$/.test(url))return JSON.stringify({ok:false,error:'Use a public iCloud shared album link.'});status={name:'Example album',count:0,lastSync:null,syncing:true,error:null};finish();return JSON.stringify({ok:true})},
icloudDisconnect(){status=null;push();return true},
icloudSync(){if(!status)return;status=Object.assign({},status,{syncing:true});finish()}
});
})();
"""

DEMO_THERMOSTAT_SCRIPT = """(()=>{
let account='frame@example.com',signIn=null;
const timers=new Map();
const things=[
{id:'t1',name:'Level-0',online:true,units:'F',indoor:69,mode:'heat',heatAllowed:true,coolAllowed:true,setpoint:70,changing:false,error:null,message:null,range:{min:40,max:90},step:1,hold:'schedule',holdUntil:null},
{id:'t2',name:'level-1',online:true,units:'F',indoor:74,mode:'cool',heatAllowed:true,coolAllowed:true,setpoint:76,changing:false,error:null,message:null,range:{min:50,max:99},step:1,hold:'temporary',holdUntil:'18:00'}];
const snapshot=()=>JSON.stringify({configured:!!account,status:account?'ok':'unconfigured',controllable:!!account,polledAt:new Date().toISOString(),retryAt:null,account:account||null,message:null,signIn,thermostats:account?things:[]});
const push=()=>{if(window.SkylitThermostat)window.SkylitThermostat.receive(snapshot())};
const later=(thing,change)=>{thing.changing=true;clearTimeout(timers.get(thing.id));timers.set(thing.id,setTimeout(()=>{change();thing.changing=false;push()},1100));push()};
const find=id=>account?things.find(thing=>thing.id===id):null;
Object.assign(window.Skylit,{
thermostatSnapshot:snapshot,
thermostatSignIn(email,password){if(!/^\\S+@\\S+$/.test(email)||!password)return JSON.stringify({ok:false,error:'Enter the account email and password.'});signIn={pending:true};push();setTimeout(()=>{if(password==='wrong')signIn={ok:false,error:'That email or password was not accepted.',retryAt:null};else{signIn=null;account=email}push()},900);return JSON.stringify({ok:true,pending:true})},
thermostatSignOut(){account='';signIn=null;push();return true},
thermostatStep(id,delta){const thing=find(id);if(!thing)return JSON.stringify({ok:false,error:'That thermostat is no longer listed.'});thing.setpoint=Math.min(thing.range.max,Math.max(thing.range.min,thing.setpoint+(delta>0?1:-1)));later(thing,()=>{thing.hold='temporary';thing.holdUntil='18:00'});return JSON.stringify({ok:true,setpoint:thing.setpoint})},
thermostatMode(id,mode){const thing=find(id);if(!thing||!['heat','cool'].includes(mode))return false;later(thing,()=>{thing.mode=mode;thing.setpoint=mode==='heat'?70:76;thing.range=mode==='heat'?{min:40,max:90}:{min:50,max:99}});return true},
thermostatResume(id){const thing=find(id);if(!thing)return false;later(thing,()=>{thing.hold='schedule';thing.holdUntil=null});return true},
thermostatWatch(){}
});
})();
"""


class PreviewServer(ThreadingHTTPServer):
    # Chromium requests the script bundle concurrently; avoid dropping startup assets.
    request_queue_size = 64


class PreviewHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        if "If-Modified-Since" in self.headers:
            del self.headers["If-Modified-Since"]
        super().do_GET()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8767)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with TemporaryDirectory(prefix='skylit-demo-') as temp:
        stage_assets(root / 'web', temp)
        target = Path(temp)
        (target / 'demo.js').write_text((root / 'tests/fixtures/demo.js').read_text())
        (target / 'demo-photos.js').write_text((root / 'tests/fixtures/demo-photos.js').read_text())
        shutil.copytree(root / 'tests/fixtures/demo-photos', target / 'demo-photos')
        (target / 'demo-household.js').write_text(DEMO_HOUSEHOLD_SCRIPT)
        (target / 'demo-icloud.js').write_text(DEMO_ICLOUD_SCRIPT)
        (target / 'demo-thermostat.js').write_text(DEMO_THERMOSTAT_SCRIPT)
        page = target / 'index.html'
        page.write_text(page.read_text().replace('<script src="local-config.js">', '<script src="demo.js"></script><script src="local-config.js">').replace('<script src="photos.js">', '<script src="demo-photos.js"></script><script src="demo-icloud.js"></script><script src="photos.js">').replace('<script src="household.js">', '<script src="demo-household.js"></script><script src="household.js">').replace('<script src="thermostat.js">', '<script src="demo-thermostat.js"></script><script src="thermostat.js">'))
        print(f'Synthetic demo only: http://127.0.0.1:{args.port}', flush=True)
        try:
            PreviewServer(('127.0.0.1', args.port), partial(PreviewHandler, directory=temp)).serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
