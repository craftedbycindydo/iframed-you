from pathlib import Path
import re,subprocess,sys,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import dev_server

MAIN=ROOT/'android/src/com/wesbos/homehq'
PURE=('ThermostatBridge','TccClient','TccHttp','TccSync','Json','KeyValue','FrameTime')

class ThermostatBridgeTest(unittest.TestCase):
    def test_bridge_against_the_fake_service(self):
        javac,java=dev_server.jdk()
        if not javac or not java:self.skipTest('JDK required')
        sources=[MAIN/f'{name}.java' for name in PURE]+sorted((ROOT/'tests/android/jvm/tcc').glob('*.java'))+sorted((ROOT/'tests/android/jvm/thermostat').glob('*.java'))
        with tempfile.TemporaryDirectory() as classes:
            built=subprocess.run([javac,'--release','8','-Xlint:-options','-d',classes,*map(str,sources)],capture_output=True,text=True)
            self.assertEqual(built.returncode,0,built.stderr)
            result=subprocess.run([java,'-cp',classes,'com.wesbos.homehq.ThermostatBridgeTest'],capture_output=True,text=True,timeout=120)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertRegex(result.stdout,r'ThermostatBridge: \d+ checks passed')
    def test_glue_keeps_secrets_out_of_logs_scripts_and_routes(self):
        bridge=(MAIN/'ThermostatBridge.java').read_text()
        self.assertIsNone(re.search(r'\b(android|androidx|org\.json)\.|System\.(out|err)|printStackTrace',bridge))
        android=(MAIN/'Thermostats.java').read_text()
        for call in re.findall(r'Log\.\w+\(([^;]*)\);',android)+re.findall(r'output\.note\(([^;]*)\);',bridge):
            self.assertIsNone(re.search(r'password|sealed|email|username|name\b|cookie|snapshot',re.sub(r'"(\\.|[^"\\])*"','""',call)),call)
        self.assertEqual(re.findall(r'dashboard\.evaluate\(([^;]*)\);',android),['"window.SkylitThermostat&&window.SkylitThermostat.receive(" + snapshot + ")"'])
        activity=(MAIN/'MainActivity.java').read_text()
        self.assertIn('thermostats=new Thermostats(this,script->{if(dashboard==null)return false;dashboard.evaluateJavascript(Json.scriptSafe(script),null);return true;},()->overviewShowing&&foreground&&remote==null&&!localPhotosOpen&&!quietOpen)',activity)
        secret=(MAIN/'TccSecret.java').read_text()
        self.assertIn('"skylit_thermostat_v1"',secret)
        self.assertNotIn('skylit_photo_mail',secret)
        self.assertIn('cipher.updateAAD(account.getBytes(StandardCharsets.UTF_8))',secret)
        self.assertNotIn('thermostat',(MAIN/'LocalApi.java').read_text().lower())
        for name in ('ThermostatBridge','Thermostats','TccSecret'):
            source=re.sub(r'"(\\.|[^"\\])*"','""',(MAIN/f'{name}.java').read_text())
            self.assertIsNone(re.search(r'//|/\*',source),name)

if __name__=='__main__':unittest.main()
