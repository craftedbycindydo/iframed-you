#!/usr/bin/env python3
"""Check the selected frame's actual Wi-Fi route and reachability without printing identifiers.

Usage: python3 scripts/check_network.py --usb [--samples 12 --interval 5]
       python3 scripts/check_network.py --wireless [--address IP:PORT]
"""
import argparse
import ipaddress
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def usb_selected(listing, serial):
    return any(
        (fields := line.split()) and len(fields) >= 3
        and fields[0] == serial and fields[1] == 'device'
        and any(part.startswith('usb:') for part in fields[2:])
        for line in listing.splitlines()
    )


def gateway_from_route(route):
    match = re.search(r'\bvia\s+(\d{1,3}(?:\.\d{1,3}){3})\b', route)
    if not match:
        return None
    try:
        return str(ipaddress.IPv4Address(match.group(1)))
    except ipaddress.AddressValueError:
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    transport = parser.add_mutually_exclusive_group(required=True)
    transport.add_argument('--usb', action='store_true', help='Use only the configured USB transport')
    transport.add_argument('--wireless', action='store_true', help='Use only paired TLS wireless ADB')
    parser.add_argument('--address', help='Current wireless debugging IP:port if mDNS discovery fails')
    parser.add_argument('--samples', type=int, default=1)
    parser.add_argument('--interval', type=float, default=5)
    args = parser.parse_args()
    if args.address and not args.wireless:
        parser.error('--address requires --wireless')
    if not 1 <= args.samples <= 120 or not 0 <= args.interval <= 60:
        parser.error('Use 1–120 samples and a 0–60 second interval')

    config = ROOT / '.local/device.json'
    if not config.exists():
        parser.error('Configure .local/device.json first; see docs/wireless.md')
    settings = json.loads(config.read_text())
    adb, serial = settings['adb'], settings['serial']

    def host_adb(*parts):
        return subprocess.run([adb, *parts], capture_output=True, text=True, timeout=15)

    if args.usb:
        listing = host_adb('devices', '-l')
        if listing.returncode or not usb_selected(listing.stdout, serial):
            parser.error('Configured frame is not an authorized USB device')
        endpoint = serial
    else:
        command = [sys.executable, str(ROOT / 'scripts/frame.py')]
        if args.address:
            command += ['--address', args.address]
        found = subprocess.run(command, capture_output=True, text=True, timeout=30)
        if found.returncode:
            parser.error('Paired TLS frame is unavailable; see docs/wireless.md')
        endpoint = found.stdout.strip()
    def device(*parts):
        return host_adb('-s', endpoint, 'shell', *parts)

    identity = device('getprop', 'ro.serialno')
    if identity.returncode or identity.stdout.strip() != serial:
        parser.error('Connected device does not match configured frame')

    failed = False
    for sample in range(args.samples):
        ipv4 = device('ip', '-4', 'addr', 'show', 'dev', 'wlan0')
        route4 = device('ip', '-4', 'route', 'get', '1.1.1.1')
        gateway = gateway_from_route(route4.stdout) if route4.returncode == 0 else None
        router_ok = device('ping', '-c', '1', '-W', '2', gateway).returncode == 0 if gateway else False
        internet4 = device('ping', '-c', '1', '-W', '2', '1.1.1.1').returncode == 0
        dns = device('ping', '-c', '1', '-W', '2', 'calendar.google.com').returncode == 0
        address6 = device('ip', '-6', 'addr', 'show', 'dev', 'wlan0')
        has_ipv6 = any('inet6 ' in line and 'fe80:' not in line for line in address6.stdout.splitlines())
        internet6 = device('ping6', '-c', '1', '-W', '2', '2606:4700:4700::1111').returncode == 0 if has_ipv6 else None
        results = {
            'IPv4': ipv4.returncode == 0 and 'inet ' in ipv4.stdout,
            'policy route': route4.returncode == 0,
            'router': router_ok,
            'IPv4 internet': internet4,
            'IPv6 internet': internet6,
            'DNS': dns,
        }
        failed |= any(value is False for value in results.values())
        print('sample %d: %s' % (sample + 1, ', '.join(
            '%s=%s' % (name, 'n/a' if value is None else 'ok' if value else 'FAIL')
            for name, value in results.items()
        )), flush=True)
        if sample + 1 < args.samples:
            time.sleep(args.interval)
    return int(failed)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (KeyError, OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        sys.exit('Network check could not complete; inspect the selected ADB transport')
