from pathlib import Path
import re,unittest
ROOT=Path(__file__).resolve().parents[1]
MAIN=ROOT/'android/src/com/wesbos/homehq'

class LifecycleTest(unittest.TestCase):
    def setUp(self):
        self.activity=(MAIN/'MainActivity.java').read_text()
        self.thermostats=(MAIN/'Thermostats.java').read_text()
    def method(self,name):
        found=re.search(r'\n  [^\n]*\b'+name+r'\([^\n]*',self.activity)
        self.assertIsNotNone(found,name)
        return found.group(0)
    def test_nothing_is_evaluated_in_a_destroyed_web_view(self):
        destroy=self.method('onDestroy')
        self.assertRegex(destroy,r'remote\.destroy\(\);remote=null;')
        self.assertRegex(destroy,r'dashboard\.destroy\(\);dashboard=null;')
        for call in re.findall(r'[^;{}]*dashboard\.evaluateJavascript\(',self.activity):
            self.assertNotIn('runOnUiThread(()->dashboard.',call)
        lambdas=re.findall(r'(?:runOnUiThread|handler\.post(?:Delayed)?)\(\(\)->\{?([^\n]*?dashboard\.evaluateJavascript)',self.activity)
        for body in lambdas:self.assertIn('dashboard!=null',body,body)
    def test_services_start_once_and_stop_once(self):
        self.assertEqual(len(re.findall(r'\bphone\.start\(\)',self.activity)),1)
        self.assertEqual(len(re.findall(r'\bthermostats\.start\(\)',self.activity)),1)
        self.assertIn('phone.start()',self.activity.split('public void onCreate')[1].split('private boolean debugging')[0])
        destroy=self.method('onDestroy')
        for stop in ('phone.stop();','thermostats.stop();','calendars.close();','photoMail.close();','handler.removeCallbacksAndMessages(null);'):
            self.assertEqual(destroy.count(stop),1,stop)
        for name in ('PhoneLink','Thermostats'):
            source=(MAIN/f'{name}.java').read_text()
            start=source.split('void start() {')[1].split('\n  }\n')[0]
            stop=source.split('void stop() {')[1].split('\n  }\n')[0]
            self.assertIn('if (running) return;',start,name)
            self.assertIn('running = false;',stop,name)
            self.assertIn('main.removeCallbacksAndMessages(null);',stop,name)
            self.assertIn('unregisterNetworkCallback(network)',stop,name)
    def test_thermostats_are_polled_at_the_watched_pace_only_while_the_overview_is_really_on_screen(self):
        self.assertIn('()->overviewShowing&&foreground&&remote==null&&!localPhotosOpen&&!quietOpen',self.activity)
        self.assertRegex(self.activity,r'private volatile boolean overviewShowing;')
        self.assertRegex(self.activity,r'public void thermostatWatch\(boolean visible\)\{overviewShowing=visible;thermostats\.bridge\.watch\(visible\);\}')
        tick=self.thermostats.split('private final Runnable tick')[1].split('};')[0]
        self.assertLess(tick.index('bridge.watch(screen.showing());'),tick.index('bridge.tick();'))
    def test_idle_photos_wait_for_settings_and_for_pairing(self):
        idle=re.search(r'private final Runnable idleTask=[^\n]*',self.activity).group(0)
        self.assertIn('window.SkylitApp.settingsOpen()||window.SkylitPairing&&window.SkylitPairing.isOpen()',idle)
    def test_a_keyboard_or_mouse_being_plugged_in_does_not_restart_the_frame(self):
        manifest=(ROOT/'android/AndroidManifest.xml').read_text()
        changes=set(re.search(r'android:configChanges="([^"]+)"',manifest).group(1).split('|'))
        self.assertLessEqual({'orientation','screenSize','keyboard','keyboardHidden','navigation','screenLayout','smallestScreenSize'},changes)
        self.assertIn('android:launchMode="singleTask"',manifest)

if __name__=='__main__':unittest.main()
