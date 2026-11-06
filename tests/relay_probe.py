"""Probe the GLKVM relay add-on from the LAN: HTTPS console, device port, and a STUN binding request."""

import os
import socket
import ssl
import struct
import sys
import urllib.request

if len(sys.argv) != 2:
    sys.exit("usage: relay_probe.py <relay host>")
host = sys.argv[1]

ctx = ssl.create_default_context()
ctx.minimum_version = ssl.TLSVersion.TLSv1_2
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
with urllib.request.urlopen(f"https://{host}/", context=ctx, timeout=10) as r:
    body = r.read(4096).decode("utf-8", "replace")
    title = body.split("<title>")[1].split("</title>")[0] if "<title>" in body else "(no title)"
    print(f"https 443: {r.status}, title {title!r}")
with socket.create_connection((host, 443), timeout=5) as s, ctx.wrap_socket(s, server_hostname=host) as t:
    cert = t.getpeercert(binary_form=True)
    print(f"tls 443: {t.version()}, peer certificate {len(cert)} bytes")

for port in (5912, 10443):
    with socket.create_connection((host, port), timeout=5):
        print(f"tcp {port}: open")

# RFC 5389 Binding Request; a success response (0x0101) carries XOR-MAPPED-ADDRESS (0x0020).
tid = os.urandom(12)
req = struct.pack("!HHI12s", 0x0001, 0, 0x2112A442, tid)
u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
u.settimeout(5)
u.sendto(req, (host, 3478))
data, _ = u.recvfrom(2048)
mtype, mlen, cookie = struct.unpack("!HHI", data[:8])
ok = mtype == 0x0101 and data[8:20] == tid
attrs, i = {}, 20
while i + 4 <= 20 + mlen:
    t, n = struct.unpack("!HH", data[i : i + 4])
    attrs[t] = data[i + 4 : i + 4 + n]
    i += 4 + n + (-n % 4)
xma = attrs.get(0x0020)
if xma:
    port = struct.unpack("!H", xma[2:4])[0] ^ 0x2112
    ip = socket.inet_ntoa(bytes(a ^ b for a, b in zip(xma[4:8], struct.pack("!I", 0x2112A442), strict=True)))
    print(f"stun udp 3478: binding success={ok}, mapped {ip}:{port}")
else:
    print(f"stun udp 3478: type 0x{mtype:04x}, success={ok}, no mapped address")
