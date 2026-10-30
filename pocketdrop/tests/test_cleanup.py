#!/usr/bin/env python3
"""PocketDrop cleanup safety contract for the iOS 8 client."""
from pathlib import Path

src=(Path(__file__).resolve().parents[1] / "main.m").read_text(encoding="utf-8")
must={
    "Shows a mobile clean button": 'action:@selector(clearInbox)' in src,
    "User must confirm deletion on phone": 'alertControllerWithTitle:@"确认一键清理？"' in src and 'UIAlertActionStyleDestructive' in src,
    "Clearly warns deletion is irreversible": "此操作无法撤销" in src,
    "Only files from PocketDrop inbox": 'PDDir() stringByAppendingPathComponent:name' in src,
    "Uses a shared safe file snapshot": 'static NSArray *PDInboxSnapshot(void)' in src,
    "Only regular files can be deleted": 'NSFileTypeRegular' in src and 'static NSDictionary *PDClearInbox(void)' in src,
    "Skips hidden/in-progress uploads": '[name hasPrefix:@"."]' in src,
    "Disallows subfolders and alternate paths": '[PDSafeName(name) isEqualToString:name]' in src,
    "Does not recursively remove directory": 'removeItemAtPath:PDDir()' not in src,
    "Shows removed count and freed bytes": 'report[@"removed"]' in src and 'report[@"bytesFreed"]' in src,
    "Web cleanup requires confirmation": "if(!confirm('清理手机 PocketDrop 收件箱的 '" in src,
    "Web cleanup endpoint uses DELETE": 'isEqualToString:@"DELETE"] && [base isEqualToString:@"/api/files"]' in src,
    "Web deletion checks peer approval first": src.index('BOOL allowed=[self peerApproved:peer]') < src.index('isEqualToString:@"DELETE"] && [base isEqualToString:@"/api/files"]'),
    "Web deletion checks cross-origin first": src.index('Cross-origin request rejected') < src.index('isEqualToString:@"DELETE"] && [base isEqualToString:@"/api/files"]'),
    "Clipboard and uploads remain supported": all(v in src for v in ('@"/api/text"','@"/upload"','@"/file"')),
}
for name,passed in must.items():
    print(("PASS" if passed else "FAIL") + ": " + name)
if not all(must.values()):
    raise SystemExit(1)
