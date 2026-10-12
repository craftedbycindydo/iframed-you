from pathlib import Path
import re,subprocess,sys,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import dev_server

SOURCES=('TccClient','TccHttp','TccSync')
SUPPORT=('Json','KeyValue','FrameTime')

class TccTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.javac,cls.java=dev_server.jdk()
        if not cls.javac or not cls.java:raise unittest.SkipTest('JDK required')
        cls.classes=tempfile.TemporaryDirectory()
        sources=[ROOT/'android/src/com/wesbos/homehq'/f'{name}.java' for name in SOURCES+SUPPORT]+sorted((ROOT/'tests/android/jvm/tcc').glob('*.java'))
        try:subprocess.run([cls.javac,'--release','8','-Xlint:-options','-d',cls.classes.name,*map(str,sources)],check=True,capture_output=True,text=True)
        except subprocess.CalledProcessError as failure:raise AssertionError(failure.stderr)
    @classmethod
    def tearDownClass(cls):
        if getattr(cls,'classes',None):cls.classes.cleanup()
    def source(self,name):
        return (ROOT/'android/src/com/wesbos/homehq'/f'{name}.java').read_text()
    def test_client_sync_and_transport_against_fake_service(self):
        result=subprocess.run([self.java,'-cp',self.classes.name,'com.wesbos.homehq.TccTest'],capture_output=True,text=True,timeout=180)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertRegex(result.stdout,r'Tcc: \d+ checks passed')
    def test_sources_stay_off_android_and_within_api_23(self):
        newer=r'java\.util\.function|java\.util\.stream|java\.time|\.removeIf\(|\.getOrDefault\(|\.putIfAbsent\(|\.computeIfAbsent\(|\.forEach\(|String\.join\(|List\.of\(|Map\.of\(|Math\.floorMod\(|newKeySet\(|->'
        for name in SOURCES:
            source=self.source(name)
            self.assertIsNone(re.search(r'\b(android|androidx|org\.json|javax\.mail)\.',source),name)
            self.assertIsNone(re.search(newer,source),name)
    def test_sources_have_no_comments_logging_or_other_hosts(self):
        for name in SOURCES:
            source=self.source(name)
            self.assertIsNone(re.search(r'//(?!["\w.])|/\*',re.sub(r'"(\\.|[^"\\])*"','""',source)),name)
            self.assertIsNone(re.search(r'System\.(out|err)|\bLog\.|printStackTrace|java\.util\.logging',source),name)
            self.assertEqual(set(re.findall(r'https?://[^"\s]+',source))-{'https://'},set(),name)
        self.assertIn('static final String HOST = "mytotalconnectcomfort.com";',self.source('TccClient'))
        self.assertIn('setInstanceFollowRedirects(false)',self.source('TccHttp'))

if __name__=='__main__':unittest.main()
