#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import argparse, json, os, signal, socket, subprocess, sys, threading, time, urllib.request

IOS = Path(__file__).resolve().parents[1]
ROOT = IOS.parent


def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


class Frame:
    def __init__(self, api_port, control_port):
        self.api_port = api_port
        self.control_port = control_port
        self.process = None
        self.java = None

    def start(self):
        self.process = subprocess.Popen([sys.executable, str(ROOT / 'scripts/dev_server.py'), '--port', str(self.api_port), '--fake-icloud',
                                         '--control-port', str(self.control_port)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        deadline = time.time() + 60
        while time.time() < deadline:
            if self.process.poll() is not None:
                raise SystemExit('dev server exited: ' + (self.process.stdout.read() or ''))
            try:
                self.control('/state')
                break
            except OSError:
                time.sleep(0.3)
        else:
            raise SystemExit('dev server never answered on its control port')
        self.java = self.child_java()
        threading.Thread(target=self.drain, daemon=True).start()

    def drain(self):
        for line in self.process.stdout:
            sys.stdout.write('[frame] ' + line)
            sys.stdout.flush()

    def child_java(self):
        for _ in range(50):
            found = subprocess.run(['pgrep', '-P', str(self.process.pid)], capture_output=True, text=True).stdout.split()
            if found:
                return int(found[0])
            time.sleep(0.1)
        raise SystemExit('could not find the dev server java process')

    def control(self, path):
        with urllib.request.urlopen(f'http://127.0.0.1:{self.control_port}{path}', timeout=3) as reply:
            return json.load(reply)

    def pause(self):
        os.kill(self.java, signal.SIGSTOP)

    def resume(self):
        os.kill(self.java, signal.SIGCONT)

    def stop(self):
        if self.process and self.process.poll() is None:
            try:
                self.resume()
            except OSError:
                pass
            self.process.terminate()
            try:
                self.process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                self.process.kill()
        self.process = None

    def restart(self):
        self.stop()
        self.start()


def serve_supervisor(frame, port):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.do_POST()

        def do_POST(self):
            try:
                if self.path == '/pause':
                    frame.pause()
                elif self.path == '/resume':
                    frame.resume()
                elif self.path == '/restart':
                    frame.restart()
                elif self.path != '/state':
                    self.send_error(404)
                    return
                body = json.dumps(frame.control('/state')).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except Exception as failure:
                self.send_error(500, str(failure))

        def log_message(self, *_):
            pass

    server = HTTPServer(('127.0.0.1', port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def main():
    parser = argparse.ArgumentParser(description='Start a throwaway dev frame and run LiveFrameUITests against it.')
    parser.add_argument('--destination', required=True, help='xcodebuild destination id of a simulator')
    parser.add_argument('--runs', type=int, default=1)
    parser.add_argument('--derived-data', default=str(IOS / 'build/dd'))
    parser.add_argument('--shots', help='Directory for screenshots')
    parser.add_argument('--build', action='store_true', help='Build first instead of test-without-building')
    parser.add_argument('--all-tests', action='store_true', help='Run the whole SkylitUITests target, not only LiveFrameUITests')
    args = parser.parse_args()
    api_port, control_port, supervisor_port = free_port(), free_port(), free_port()
    frame = Frame(api_port, control_port)
    green = 0
    try:
        supervisor = serve_supervisor(frame, supervisor_port)
        for run in range(1, args.runs + 1):
            frame.restart()
            env = dict(os.environ, TEST_RUNNER_SKYLIT_LIVE_API=str(api_port), TEST_RUNNER_SKYLIT_LIVE_CONTROL=str(control_port),
                       TEST_RUNNER_SKYLIT_LIVE_SUPERVISOR=str(supervisor_port))
            if args.shots:
                env['TEST_RUNNER_SKYLIT_SHOTS'] = args.shots
            action = 'test' if args.build and run == 1 else 'test-without-building'
            command = ['xcodebuild', action, '-project', str(IOS / 'Skylit.xcodeproj'), '-scheme', 'Skylit', '-destination', f'id={args.destination}',
                       '-derivedDataPath', args.derived_data] + ([] if args.all_tests else ['-only-testing:SkylitUITests/LiveFrameUITests'])
            log = IOS / f'build/live-run-{run}.log'
            with open(log, 'w') as output:
                result = subprocess.run(command, env=env, stdout=output, stderr=subprocess.STDOUT, cwd=str(IOS))
            print(f'run {run}: {"green" if result.returncode == 0 else "FAILED"} (log: {log})', flush=True)
            if result.returncode != 0:
                break
            green += 1
        supervisor.shutdown()
    finally:
        frame.stop()
    print(f'{green}/{args.runs} consecutive green runs')
    sys.exit(0 if green == args.runs else 1)


if __name__ == '__main__':
    main()
