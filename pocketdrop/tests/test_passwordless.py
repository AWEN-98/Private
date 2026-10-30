#!/usr/bin/env python3
"""Static regression checks for the iOS 8 no-code LAN transport contract."""
from pathlib import Path
src = (Path(__file__).resolve().parents[1] / "main.m").read_text(encoding="utf-8")
checks = {
    "No password input in HTML": 'id=\'code\'' not in src and 'pdcode' not in src,
    "No old pairing header or auth": 'x-pocket-key' not in src and "Pairing code required" not in src,
    "Wi-Fi socket bound to en0 address": "inet_pton(AF_INET,ip.UTF8String,&a.sin_addr)" in src and "INADDR_ANY" not in src,
    "Only Wi-Fi subnet peers admitted": "PDPeerOnWiFi(peer)" in src,
    "Device permission required": 'peerApproved:peer' in src and 'requestApprovalForPeer:peer' in src,
    "One-tap approval exists": "允许本次连接" in src and "UIAlertController" in src,
    "Unapproved clients cannot access files": src.index("peerApproved:peer") < src.index('isEqualToString:@"/api/files"'),
    "Revoke all permissions on stop": src.count("[self.approvedPeers removeAllObjects]") >= 2,
    "Anti DNS rebinding": 'headers[@"host"]' in src and 'expectedHost' in src,
    "Cross-site Origin check": "Cross-origin request rejected" in src,
    "Files and clipboard remain": all(p in src for p in ('@"/upload"', '@"/file"', '@"/api/text"', '@"/delete"')),
    "No-code web UI auto-connects": "refresh();</script></html>" in src,
}
for key, ok in checks.items():
    print(("PASS" if ok else "FAIL") + ": " + key)
if not all(checks.values()):
    raise SystemExit(1)
