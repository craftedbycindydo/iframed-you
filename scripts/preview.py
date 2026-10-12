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
    'pairing': {'devices': [{'id': 'd1', 'name': 'Example phone', 'pairedAt': '2026-10-08T17:30:00Z'}]},
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
        page = target / 'index.html'
        page.write_text(page.read_text().replace('<script src="local-config.js">', '<script src="demo.js"></script><script src="local-config.js">').replace('<script src="photos.js">', '<script src="demo-photos.js"></script><script src="demo-icloud.js"></script><script src="photos.js">').replace('<script src="household.js">', '<script src="demo-household.js"></script><script src="household.js">'))
        print(f'Synthetic demo only: http://127.0.0.1:{args.port}', flush=True)
        try:
            PreviewServer(('127.0.0.1', args.port), partial(PreviewHandler, directory=temp)).serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == '__main__':
    main()
