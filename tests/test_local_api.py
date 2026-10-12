from pathlib import Path
import re,subprocess,sys,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import dev_server

class LocalApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.javac,cls.java=dev_server.jdk()
        if not cls.javac or not cls.java:raise unittest.SkipTest('JDK required')
        cls.classes=tempfile.TemporaryDirectory()
        try:dev_server.compile_pure(cls.javac,cls.classes.name)
        except subprocess.CalledProcessError as failure:raise AssertionError(failure.stderr)
    @classmethod
    def tearDownClass(cls):
        if getattr(cls,'classes',None):cls.classes.cleanup()
    def run_main(self,name,pattern):
        result=subprocess.run([self.java,'-cp',self.classes.name,'com.wesbos.homehq.'+name],capture_output=True,text=True,timeout=180)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertRegex(result.stdout,pattern)
    def test_protocol_pairing_store_and_photos(self):
        self.run_main('LocalApiTest',r'LocalApi: \d+ checks passed')
    def test_icloud_album_protocol_planning_sync_and_endpoints(self):
        self.run_main('ICloudTest',r'ICloud: \d+ checks passed')
    def test_real_server_over_sockets(self):
        self.run_main('LocalServerTest',r'LocalServer: \d+ checks passed')
    def test_pure_sources_stay_off_android(self):
        for name in dev_server.PURE_SOURCES:
            source=(ROOT/'android/src/com/wesbos/homehq'/f'{name}.java').read_text()
            self.assertIsNone(re.search(r'\b(android|androidx|org\.json|javax\.mail)\.',source),name)
    def test_android_api_23_library_surface(self):
        newer=r'java\.util\.function|java\.util\.stream|java\.time|\.removeIf\(|\.getOrDefault\(|\.putIfAbsent\(|\.computeIfAbsent\(|\.forEach\(|String\.join\(|List\.of\(|Map\.of\(|Math\.floorMod\(|newKeySet\('
        for name in (*dev_server.PURE_SOURCES,'PhoneLink'):
            source=(ROOT/'android/src/com/wesbos/homehq'/f'{name}.java').read_text()
            self.assertIsNone(re.search(newer,source),name)

if __name__=='__main__':unittest.main()
