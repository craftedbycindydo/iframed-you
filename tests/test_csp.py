from pathlib import Path
import re,unittest
ROOT=Path(__file__).resolve().parents[1]
PAGE=(ROOT/'web/index.html').read_text()

class ContentSecurityPolicyTest(unittest.TestCase):
    def policy(self):
        found=re.search(r'<meta http-equiv="Content-Security-Policy" content="([^"]+)">',PAGE)
        self.assertIsNotNone(found)
        return {part.split()[0]:part.split()[1:] for part in found.group(1).split(';') if part.strip()}
    def test_policy_is_strict(self):
        policy=self.policy()
        self.assertEqual(policy['default-src'],["'none'"])
        self.assertEqual(policy['script-src'],["'self'"])
        self.assertEqual(policy['style-src'],["'self'"])
        self.assertEqual(policy['img-src'],["'self'"])
        self.assertEqual(policy['worker-src'],["'self'"])
        self.assertEqual(policy['base-uri'],["'none'"])
        self.assertEqual(policy['form-action'],["'none'"])
        self.assertEqual(sorted(policy['connect-src']),['https://api.open-meteo.com','https://geocoding-api.open-meteo.com'])
        for sources in policy.values():
            for source in sources:self.assertNotIn(source,("'unsafe-inline'","'unsafe-eval'",'*','data:','blob:','http:','https:'))
        self.assertLess(PAGE.index('Content-Security-Policy'),PAGE.index('<link'))
        self.assertLess(PAGE.index('Content-Security-Policy'),PAGE.index('<script'))
    def test_page_needs_nothing_the_policy_forbids(self):
        self.assertIsNone(re.search(r'<script(?![^>]*\ssrc=)[^>]*>',PAGE))
        self.assertIsNone(re.search(r'<style|\sstyle=|\son[a-z]+=|javascript:',PAGE))
        for source in re.findall(r'<script[^>]*\ssrc="([^"]+)"',PAGE)+re.findall(r'<link[^>]*\shref="([^"]+)"',PAGE):
            self.assertIsNone(re.match(r'[a-z]+:|//',source),source)
        allowed=('https://api.open-meteo.com/','https://geocoding-api.open-meteo.com/')
        for script in sorted((ROOT/'web').glob('*.js')):
            if script.name in ('ical.js','suncalc.js','local-config.js'):continue
            text=script.read_text()
            self.assertIsNone(re.search(r'''<[a-z][^>'"`]*\s(style|on[a-z]+)=|\beval\(|new Function\(|createElement\(['"](script|style|iframe)['"]\)|\.cssText|setAttribute\(['"]style''',text),script.name)
            for call in re.findall(r'''fetch(?:JSON)?\(\s*[`'"](https?://[^`'"?]+)''',text):
                self.assertTrue(call.startswith(allowed),script.name+' '+call)

if __name__=='__main__':unittest.main()
