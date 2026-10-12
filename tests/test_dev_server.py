from pathlib import Path
import hashlib,hmac,http.client,json,os,re,ssl,subprocess,sys,unittest,urllib.request
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import dev_server

class DevServerTest(unittest.TestCase):
    def launch(self,*flags):
        server=subprocess.Popen([sys.executable,str(ROOT/'scripts/dev_server.py'),'--port','0','--control-port','0',*flags],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        self.addCleanup(server.wait,10)
        self.addCleanup(server.terminate)
        self.addCleanup(server.stdout.close)
        self.addCleanup(server.stdin.close)
        first=server.stdout.readline()
        started=re.fullmatch(r'Skylit dev frame ([0-9a-f]{32}) fp ([0-9a-f]{64}) listening on 127\.0\.0\.1 port (\d+)\n',first)
        self.assertIsNotNone(started,first)
        self.server,self.frame_id,self.fp,self.port=server,started[1],started[2],int(started[3])
        self.control=int(re.fullmatch(r'control on 127\.0\.0\.1 port (\d+)\n',server.stdout.readline())[1])
    def until(self,pattern):
        for line in self.server.stdout:
            found=re.search(pattern,line)
            if found:return found
        self.fail('the dev server stopped before printing '+pattern)
    def ask(self,path):
        return json.load(urllib.request.urlopen(f'http://127.0.0.1:{self.control}{path}',timeout=5))
    def call(self,method,path,body=None,token=None,version=ssl.TLSVersion.TLSv1_2):
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname=False
        context.verify_mode=ssl.CERT_NONE
        context.minimum_version=context.maximum_version=version
        connection=http.client.HTTPSConnection('127.0.0.1',self.port,context=context,timeout=10)
        headers={'Authorization':'Bearer '+token} if token else {}
        connection.request(method,path,json.dumps(body) if body is not None else None,headers)
        self.seen=hashlib.sha256(connection.sock.getpeercert(binary_form=True)).digest()
        self.cipher=connection.sock.cipher()
        response=connection.getresponse()
        text=response.read()
        connection.close()
        return response.status,json.loads(text) if text else None
    def pair(self):
        n_p,token=os.urandom(32),os.urandom(32)
        status,started=self.call('POST','/v2/pair/start',{'commit':hashlib.sha256(n_p).hexdigest(),'tokenHash':hashlib.sha256(token).hexdigest(),'deviceName':"Maya's iPhone"})
        self.assertEqual(status,200,started)
        pinned=self.seen
        self.assertEqual(self.call('POST','/v2/pair/reveal',{'session':started['session'],'nP':n_p.hex()})[0],204)
        self.assertEqual(self.seen,pinned)
        digest=hmac.new(n_p+bytes.fromhex(started['nF']),b'skylit-pair-v2\x00'+pinned,hashlib.sha256).digest()
        code='%06d'%(int.from_bytes(digest[0:4],'big')%1000000)
        pick='%02d'%(int.from_bytes(digest[4:8],'big')%100)
        return started['session'],token.hex(),code,pick
    def test_vector_with_an_independent_implementation(self):
        n_p,n_f,fp=bytes(range(0,32)),bytes(range(32,64)),bytes(range(64,96))
        self.assertEqual(hashlib.sha256(n_p).hexdigest(),'630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd')
        digest=hmac.new(n_p+n_f,b'skylit-pair-v2\x00'+fp,hashlib.sha256).digest()
        self.assertEqual(digest.hex(),'526438df18ab2fc054b103a87964836abe6e20d4118d11b6a6e50ebbca57d7af')
        self.assertEqual(('%06d'%(int.from_bytes(digest[0:4],'big')%1000000),'%02d'%(int.from_bytes(digest[4:8],'big')%100)),('299871','64'))
    def test_tls_pairing_and_console_flow(self):
        if not all(dev_server.jdk()):self.skipTest('JDK required')
        self.launch('--pair-window','--auto-approve','0.5')
        status,info=self.call('GET','/v2/info')
        self.assertEqual((status,info),(200,{'v':2,'frameId':self.frame_id,'name':'Skylit','pairing':True}))
        self.assertEqual(self.seen.hex(),self.fp)
        self.assertEqual(self.fp[:32],self.frame_id)
        self.assertEqual(self.cipher[1],'TLSv1.2')
        self.assertIn(self.cipher[0],('ECDHE-ECDSA-AES128-GCM-SHA256','ECDHE-ECDSA-AES256-GCM-SHA384'))
        with self.assertRaises(ssl.SSLError):self.call('GET','/v2/info',version=ssl.TLSVersion.TLSv1_3)
        with self.assertRaises((http.client.HTTPException,OSError)):urllib.request.urlopen(f'http://127.0.0.1:{self.port}/v2/info',timeout=5)
        session,token,code,pick=self.pair()
        shown=self.until(r'^PAIRING CODE (\d{6}) numbers (\d\d) (\d\d) (\d\d) pick (\d\d)$')
        self.assertEqual((shown[1],shown[5]),(code,pick))
        self.assertIn(pick,shown.group(2,3,4))
        self.assertEqual(len(set(shown.group(2,3,4))),3)
        self.until(r'^auto-tap '+pick+' approved$')
        status,result=self.call('GET','/v2/pair/result?session='+session)
        self.assertEqual((status,result['frameId'],result['name']),(200,self.frame_id,'Skylit'))
        status,devices=self.call('GET','/v1/devices',token=token)
        self.assertEqual((status,[(d['name'],d['self'],d['id']==result['deviceId']) for d in devices]),(200,[("Maya's iPhone",True,True)]))
        self.assertEqual(self.call('GET','/v1/state')[0],401)
        self.assertEqual(self.call('POST','/v2/pair/start',{'commit':'0'*64,'tokenHash':'0'*64,'deviceName':'Late'})[0],409)
        self.server.stdin.write('\n')
        self.server.stdin.flush()
        self.until(r'^pairing window \{"ok":true')
        self.assertTrue(self.call('GET','/v2/info')[1]['pairing'])
    def test_negative_taps_and_control_port(self):
        if not all(dev_server.jdk()):self.skipTest('JDK required')
        self.launch('--auto-approve','0','--tap','decoy')
        self.assertEqual(self.ask('/state'),{'fp':self.fp,'frameId':self.frame_id,'pick':None,'pairing':{'phase':'idle'}})
        self.assertEqual(self.call('POST','/v2/pair/start',{'commit':'0'*64,'tokenHash':'0'*64,'deviceName':'Early'})[0],409)
        self.assertEqual(self.ask('/open')['pairing']['phase'],'waiting')
        session,token,code,pick=self.pair()
        self.until(r'^auto-tap (?!'+pick+r')\d\d refused$')
        self.assertEqual(self.call('GET','/v2/pair/result?session='+session)[0],403)
        self.assertEqual(self.call('GET','/v1/state',token=token)[0],401)
        self.assertEqual(self.ask('/state')['pairing'],{'phase':'cancelled','reason':'decoy'})
        with self.assertRaises(urllib.error.HTTPError) as unknown:self.ask('/nothing')
        unknown.exception.close()

if __name__=='__main__':unittest.main()
