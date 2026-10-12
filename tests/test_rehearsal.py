from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
import hashlib,http.client,json,os,ssl,sys,threading,time,unittest,urllib.parse
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
sys.path.insert(0,str(ROOT/'tests'))
import dev_server
import test_dev_server

FEED='https://calendar.google.com/calendar/ical/test%40example.org/private-test/basic.ics'
ALBUM='https://www.icloud.com/sharedalbum/#B0aGWZuqDGWZuqD'

class RehearsalTest(unittest.TestCase):
    launch,ask,call,pair=(getattr(test_dev_server.DevServerTest,name) for name in ('launch','ask','call','pair'))
    def raw(self,method,path,token,body=None,kind=None):
        context=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname=False
        context.verify_mode=ssl.CERT_NONE
        connection=http.client.HTTPSConnection('127.0.0.1',self.port,context=context,timeout=10)
        connection.request(method,path,body,{'Authorization':'Bearer '+token,**({'Content-Type':kind} if kind else {})})
        self.assertEqual(hashlib.sha256(connection.sock.getpeercert(binary_form=True)).hexdigest(),self.fp,'the pinned certificate')
        response=connection.getresponse()
        data=response.read()
        connection.close()
        return response.status,data
    def ok(self,method,path,body,token):
        status,answer=self.call(method,path,body,token)
        self.assertEqual(status,200,(method,path,answer))
        self.rev+=1
        self.assertEqual(answer['rev'],self.rev,(method,path,'one change, one revision'))
        return answer
    def join(self):
        self.assertEqual(self.ask('/open')['pairing']['phase'],'waiting')
        self.assertTrue(self.call('GET','/v2/info')[1]['pairing'])
        session,token,code,pick=self.pair()
        shown=self.ask('/state')
        self.assertEqual((shown['pairing']['phase'],shown['pairing']['code'],shown['pick']),('code',code,pick))
        self.assertIn(pick,shown['pairing']['numbers'])
        self.assertEqual(self.call('GET','/v2/pair/result?session='+session)[0],202)
        self.assertEqual(self.ask('/tap/'+pick)['pairing']['phase'],'paired')
        status,result=self.call('GET','/v2/pair/result?session='+session)
        self.assertEqual((status,result['frameId']),(200,self.frame_id))
        self.assertEqual(self.ask('/cancel')['pairing'],{'phase':'idle'})
        return token,result['deviceId']
    def dashboard(self,**op):
        answer=self.ask('/household/'+urllib.parse.quote(json.dumps(op),safe=''))
        self.assertTrue(answer['ok'],answer)
        self.rev+=1
        self.assertEqual(answer['snapshot']['rev'],self.rev)
        return answer['snapshot']
    def settled(self,token):
        for _ in range(100):
            status,state=self.call('GET','/v1/state',token=token)
            self.assertEqual(status,200)
            album=state['settings']['icloudAlbum']
            if album and not album['syncing'] and album['lastSync'] and album['count']==4:return state
            time.sleep(0.1)
        self.fail('the album did not finish syncing: '+json.dumps(state['settings']))
    def test_a_morning_with_two_phones(self):
        if not all(dev_server.jdk()):self.skipTest('JDK required')
        self.launch('--fake-icloud')
        reading=threading.Thread(target=lambda:[None for _ in self.server.stdout],daemon=True)
        reading.start()
        self.addCleanup(reading.join,10)
        self.addCleanup(self.server.terminate)
        self.rev=0

        self.assertEqual(self.call('GET','/v2/info'),(200,{'v':2,'frameId':self.frame_id,'name':'Skylit','pairing':False}))
        self.assertEqual(self.call('GET','/v1/state')[0],401)
        self.assertEqual(self.call('POST','/v2/pair/start',{'commit':'0'*64,'tokenHash':'0'*64,'deviceName':'Early'})[1]['error']['code'],'conflict')

        first,first_id=self.join()
        status,fresh=self.call('GET','/v1/state',token=first)
        self.assertEqual((status,fresh),(200,{'rev':0,'people':[],'chores':[],'shopping':[],'settings':{'location':None,'appearance':{'palette':'linen','mode':'auto'},'icloudAlbum':None},'calendars':[],'photos':{'count':0}}))

        people=[self.ok('POST','/v1/people',{'name':name,'color':color},first)['person']['id'] for name,color in (('Maya','#00A36C'),('Noor','#2D5BFF'))]
        chores=[self.ok('POST','/v1/chores',chore,first)['chore']['id'] for chore in (
            {'title':'Make bed','emoji':'🛏️','personId':people[0],'days':[1,2,3,4,5]},{'title':'Feed the cat','personId':people[1]},
            {'title':'Water plants','days':[0,6]},{'title':'Take out bins','emoji':'🗑️'})]
        items=[self.ok('POST','/v1/shopping',item,first)['item']['id'] for item in (
            {'name':'Milk','qty':2},{'name':'Eggs','qty':12,'note':'free range'},{'name':'Bread'},{'name':'Apples','qty':6},{'name':'Rice'})]
        self.assertEqual((people,chores,items),(['p1','p2'],['c3','c4','c5','c6'],['s7','s8','s9','s10','s11']))
        pictures=[b'\xff\xd8\xff\xe0'+os.urandom(6000) for _ in range(2)]
        for picture in pictures:
            status,data=self.raw('POST','/v1/photos',first,picture,'image/jpeg')
            self.rev+=1
            self.assertEqual((status,json.loads(data)['rev'],json.loads(data)['photo']['id']),(200,self.rev,hashlib.sha256(picture).hexdigest()))
        self.assertEqual(json.loads(self.raw('POST','/v1/photos',first,pictures[0],'image/jpeg')[1])['rev'],self.rev,'the same picture twice changes nothing')
        location={'name':'Denver','latitude':39.74,'longitude':-104.99,'timezone':'America/Denver'}
        self.ok('PUT','/v1/settings/location',location,first)
        self.ok('PUT','/v1/settings/appearance',{'palette':'sage','mode':'dark'},first)
        self.assertEqual(self.ok('POST','/v1/calendars',{'name':'Family','color':'#2D5BFF','url':FEED},first)['calendar'],{'id':'k1','name':'Family','color':'#2D5BFF'})
        self.assertEqual(self.call('POST','/v1/calendars',{'name':'Again','color':'#2D5BFF','url':FEED},first)[0],409)
        self.assertEqual(self.call('PUT','/v1/settings/icloud-album',{'url':ALBUM},first)[0],200)
        state=self.settled(first)
        self.assertEqual((state['settings']['icloudAlbum']['name'],state['settings']['icloudAlbum']['error'],state['photos']['count']),('Family',None,6))
        self.assertNotIn(FEED,json.dumps(state))
        self.assertNotIn('B0aGWZuqDGWZuqD',json.dumps(state))
        self.rev=state['rev']
        self.assertEqual(self.call('GET','/v1/state?since=%d'%self.rev,token=first)[0],304)

        today=datetime.now(ZoneInfo('America/Denver')).date().isoformat()
        self.dashboard(op='chore.done',id=chores[0],date=today,done=True)
        self.dashboard(op='chore.done',id=chores[3],date=today,done=True)
        self.dashboard(op='item.update',id=items[0],done=True)
        shown=self.dashboard(op='item.update',id=items[2],done=True)
        status,state=self.call('GET','/v1/state?since=%d'%(self.rev-4),token=first)
        self.assertEqual(status,200)
        self.assertEqual({key:state[key] for key in shown},shown,'the phone and the frame show the same household')
        self.assertEqual([chore['done'] for chore in state['chores']],[[today],[],[],[today]])
        self.assertEqual([item['done'] for item in state['shopping']],[True,False,True,False,False])

        second,second_id=self.join()
        self.assertEqual(self.call('GET','/v1/state',token=second),(200,state),'a second phone sees everything')
        status,listed=self.call('GET','/v1/photos',token=second)
        self.assertEqual((status,len(listed)),(200,6))
        self.assertLessEqual({hashlib.sha256(picture).hexdigest() for picture in pictures},{photo['id'] for photo in listed})
        self.assertEqual(self.raw('GET','/v1/photos/'+hashlib.sha256(pictures[1]).hexdigest(),second),(200,pictures[1]))
        self.assertEqual([(device['id'],device['self']) for device in self.call('GET','/v1/devices',token=second)[1]],[(first_id,False),(second_id,True)])
        self.assertEqual(self.call('DELETE','/v1/devices/'+second_id,token=first)[0],403)

        self.assertEqual(self.call('DELETE','/v1/devices/'+first_id,token=first)[0],204)
        self.assertEqual(self.call('GET','/v1/state',token=first)[0],401)
        self.assertEqual([device['id'] for device in self.call('GET','/v1/devices',token=second)[1]],[second_id])
        self.assertEqual(self.call('GET','/v1/state?since=%d'%self.rev,token=second)[0],304,'unpairing is not a household change')

        self.assertEqual(self.ask('/restart')['fp'],self.fp)
        self.assertEqual(self.call('GET','/v2/info'),(200,{'v':2,'frameId':self.frame_id,'name':'Skylit','pairing':False}))
        self.assertEqual(self.seen.hex(),self.fp,'the same certificate after a restart')
        self.assertEqual(self.call('GET','/v1/state',token=first)[0],401)
        after=self.settled(second)
        self.assertGreaterEqual(after['rev'],self.rev)
        for part in ('people','chores','shopping','calendars','photos'):self.assertEqual(after[part],state[part],part+' survives a restart')
        self.assertEqual((after['settings']['location'],after['settings']['appearance']),(location,{'palette':'sage','mode':'dark'}))
        self.assertEqual((after['settings']['icloudAlbum']['name'],after['settings']['icloudAlbum']['count']),('Family',4))
        self.assertEqual({photo['id'] for photo in self.call('GET','/v1/photos',token=second)[1]},{photo['id'] for photo in listed})
        self.assertEqual([device['id'] for device in self.call('GET','/v1/devices',token=second)[1]],[second_id])
        self.rev=after['rev']
        self.assertEqual(self.ok('POST','/v1/shopping',{'name':'Tea'},second)['item']['id'],'s12','ids continue after a restart')
        self.assertEqual(self.ok('POST','/v1/shopping/clear-done',None,second),{'rev':self.rev})
        self.assertEqual([item['name'] for item in self.call('GET','/v1/state',token=second)[1]['shopping']],['Eggs','Apples','Rice','Tea'])
        self.assertEqual(self.call('DELETE','/v1/settings/icloud-album',token=second)[0],200)
        final=self.call('GET','/v1/state',token=second)[1]
        self.assertEqual((final['settings']['icloudAlbum'],final['photos']['count']),(None,2),'disconnecting the album keeps the phone pictures')

if __name__=='__main__':unittest.main()
