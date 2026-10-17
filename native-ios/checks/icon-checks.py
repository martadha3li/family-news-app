from pathlib import Path
import subprocess,tempfile,json,plistlib,struct,hashlib
r=Path(__file__).resolve().parents[1]
s=(r/'App/Backend.swift').read_text();f=s[s.index('func desiredFamilyIcon('):s.index('@MainActor enum TenantAppIcon')]
tests='''
let keys:Set<String>=["Family01","Family_abc123"]
assert(desiredFamilyIcon(code:"01",identifier:"old",available:keys)=="Family01")
assert(desiredFamilyIcon(code:"99",identifier:"ABC-123",available:keys)=="Family_abc123")
assert(desiredFamilyIcon(code:"02",identifier:"new",available:keys)==nil)
assert(desiredFamilyIcon(code:"",identifier:"",available:keys)==nil)
assert(desiredFamilyIcon(code:"01",identifier:"old",available:[])==nil)
print("PASS: family 01 alternate icon, embedded UUID mapping, unknown-family fallback and platform reset")
'''
with tempfile.TemporaryDirectory()as tmp:
 p=Path(tmp)/'icons.swift';p.write_text('import Foundation\n'+f+tests);subprocess.run(['swift',str(p)],check=True)
assets=r/'App/Assets.xcassets';primary=(assets/'AppIcon.appiconset/AppIcon.png').read_bytes();family=(assets/'Family01.appiconset/AppIcon.png').read_bytes()
assert primary!=family
assert struct.unpack('>II',primary[16:24])==(1024,1024)
assert primary[25]==2,'primary icon must be RGB without alpha'
assert json.loads((assets/'Family01.appiconset/Contents.json').read_text())['images'][0]['filename']=='AppIcon.png'
assert 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = Family01' in (r/'FamilyNews.xcodeproj/project.pbxproj').read_text()
assert 'applicationState == .active' in s and 'app.alternateIconName != wanted' in s
p=plistlib.loads((r/'App/Info.plist').read_bytes());assert p['UILaunchScreen']['UIImageName']=='PlatformLogo'
print('PASS: independent platform mark, original family asset preserved, alternate catalog declared and foreground-only idempotent switch')
