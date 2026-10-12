import getpass
import http.client
import re
import time
import urllib.parse

HOST = 'mytotalconnectcomfort.com'
AUTH = '.ASPXAUTH_TRUEHOME'
cookies = {}
ajax = True


def send(method, path, body=None, content='application/json'):
    headers = {'Accept': '*/*', 'Content-Type': content}
    if ajax:
        headers['X-Requested-With'] = 'XMLHttpRequest'
    if cookies:
        headers['Cookie'] = '; '.join(f'{name}={value}' for name, value in cookies.items())
    link = http.client.HTTPSConnection(HOST, timeout=30)
    link.request(method, path, body=body, headers=headers)
    reply = link.getresponse()
    text = reply.read().decode('utf-8', 'replace')
    step = f'{method} {path.split("?")[0]} {reply.status}'
    location = reply.getheader('Location')
    if location:
        step += f' to {location.split("?")[0]}'
    for header in reply.headers.get_all('Set-Cookie') or []:
        name, _, value = header.split(';', 1)[0].strip().partition('=')
        lowered = header.lower()
        if not value and (name == AUTH or 'expires=' in lowered or 'max-age=' in lowered):
            cookies.pop(name, None)
            step += f' -{name}'
        else:
            cookies[name] = value
            step += f' +{name}'
    title = re.search(r'<title>\s*([^<]{0,60})', text)
    if title:
        step += f' title {title.group(1).strip()}'
    if 'validation-summary-errors' in text:
        step += ' refused'
    step += f' type {reply.getheader("Content-Type")} length {len(text)}'
    print(step)
    if 'json' in (reply.getheader('Content-Type') or '') and len(text) < 400:
        print('  body', re.sub(r'[A-Za-z0-9_\-+/=]{24,}', '<long>', text))
    link.close()
    return reply.status, location, text


def follow(method, path, body=None, content='application/json'):
    for _ in range(6):
        status, location, text = send(method, path, body, content)
        if not 300 <= status < 400 or not location:
            return status, text
        path = urllib.parse.urlsplit(urllib.parse.urljoin(f'https://{HOST}{path}', location))
        path = path.path + ('?' + path.query if path.query else '')
        method, body, content = 'GET', None, 'application/json'
    return status, text


email = input('Honeywell email: ').strip()
password = getpass.getpass('Honeywell password (hidden): ')
for ajax in (True, False):
    print('--- with ajax header' if ajax else '--- like a browser')
    cookies.clear()
    follow('GET', '/portal')
    form = urllib.parse.urlencode({'timeOffset': int(time.timezone / 60), 'UserName': email, 'Password': password, 'RememberMe': 'false'})
    follow('POST', '/portal', form, 'application/x-www-form-urlencoded')
    follow('GET', '/portal')
    print('holding', sorted(cookies))
    status, _, listed = send('POST', '/portal/Location/GetLocationListData/?page=1&filter=')
    print('locations', len(re.findall(r'"LocationID"', listed)), 'thermostats', len(re.findall(r'"DeviceID"', listed)))
