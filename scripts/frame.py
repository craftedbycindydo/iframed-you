#!/usr/bin/env python3
"""Connect to the paired frame over TLS, verify its identity, then run an ADB command."""
import argparse
import ipaddress
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def tls_endpoint(listing, serial):
    """Only accept this frame's TLS connect service, never legacy or pairing ports."""
    for line in listing.splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[0].startswith('adb-' + serial + '-') and fields[1] == '_adb-tls-connect._tcp':
            return checked_endpoint(fields[2])
    return None


def connected_tls(listing, serial):
    for line in listing.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[1] == "device" and fields[0].startswith("adb-" + serial + "-") and fields[0].endswith("._adb-tls-connect._tcp"):
            return fields[0]
    return None


def checked_endpoint(value):
    host, port = value.rsplit(':', 1)
    ipaddress.ip_address(host.strip('[]'))
    if not 0 < int(port) < 65536:
        raise ValueError('Invalid port')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--address', help='Current IP:port from Wireless debugging (optional)')
    parser.add_argument('command', nargs=argparse.REMAINDER, help='ADB command, such as shell or install -r dist/skylit.apk')
    args = parser.parse_args()
    config_path = ROOT / '.local/device.json'
    if not config_path.exists():
        parser.error('Create .local/device.json with adb path and device serial; see docs/wireless.md.')
    config = json.loads(config_path.read_text())
    adb = config.get('adb') or shutil.which('adb')
    serial = config['serial']
    if not adb:
        parser.error('Install Android platform-tools or configure the adb path.')

    def run(*cmd, **kwargs):
        return subprocess.run([adb, *cmd], check=True, **kwargs)

    connected = run('devices', capture_output=True, text=True).stdout
    endpoint = checked_endpoint(args.address) if args.address else connected_tls(connected, serial)
    already_connected = bool(endpoint) and not args.address
    if not endpoint:
        listing = run('mdns', 'services', capture_output=True, text=True).stdout
        endpoint = tls_endpoint(listing, serial)
    if not endpoint:
        parser.error('Frame not discovered. Check both devices are on the same Wi-Fi and Wireless debugging is on. Use --address IP:PORT from its settings if needed.')
    if not already_connected:
        result = run('connect', endpoint, capture_output=True, text=True)
        if 'connected to' not in result.stdout:
            parser.error('Connection failed: ' + result.stdout.strip())
    observed = run('-s', endpoint, 'shell', 'getprop', 'ro.serialno', capture_output=True, text=True).stdout.strip()
    if observed != serial:
        parser.error('Connected device does not match the configured frame; command not executed.')
    print('Connected to paired frame at ' + endpoint, file=sys.stderr)
    command = args.command
    if command and command[0] == '--':
        command = command[1:]
    if command:
        return subprocess.run([adb, '-s', endpoint, *command]).returncode
    print(endpoint)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, KeyError, subprocess.CalledProcessError) as exc:
        sys.exit('Could not connect to frame: ' + str(exc))
