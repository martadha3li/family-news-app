from pathlib import Path
import subprocess,tempfile,plistlib
root=Path(__file__).resolve().parents[1]
source=(root/'App/Backend.swift').read_text()
core=source[source.index('struct Item:'):source.index('enum CredentialStore')]
core += source[source.index('func q('):source.index('let brandBlue=')]
tests=r'''
func expect(_ value:Bool,_ label:String) {precondition(value,label)}
expect(try phone("0501234567")=="+966501234567","Saudi mobile")
expect(try phone("٠٥٠١٢٣٤٥٦٧")=="+966501234567","Arabic digits")
expect(try phone("۰۰۹۶۶۵۰۱۲۳۴۵۶۷")=="+966501234567","Persian digits and international prefix")
expect(try phone("+966 (50) 123-4567")=="+966501234567","Formatted international number")
for value in ["", "+966", "phone", "05012345678999999999"] {do {_ = try phone(value);fatalError("Accepted invalid phone")}catch{}}
let row=Item(["id":123,"body":NSNull(),"active":true,"count":9])
expect(row.id=="123","Numeric message ID")
expect(row.text("body")=="","JSON null")
expect(row.flag("active"),"Boolean")
expect(row.number("count")==9,"Count")
expect(!row.flag("missing"),"Missing flag")
expect(dateValue("2026-10-17T10:00:00.123456+00:00")>Date.distantPast,"Database timestamp")
var components=URLComponents();components.queryItems=[q("display_name","ilike.*أحمد علي*"),q("limit","20")]
expect(components.percentEncodedQuery?.contains("%") == true,"UTF8 query encoding")
print("PASS: phone normalization, invalid inputs, nullable records, numeric IDs, timestamp and query encoding")
'''
# Swift executes actual pure functions extracted from the production source.
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'checks.swift';p.write_text('import Foundation\n'+core+'\n'+tests)
 subprocess.run(['swift',str(p)],check=True)
plist=plistlib.loads((root/'App/Info.plist').read_bytes())
assert plist['CFBundleIdentifier']=='$(PRODUCT_BUNDLE_IDENTIFIER)'
assert 'UIMainStoryboardFile' not in plist
for p in (root/'App').glob('*.swift'):
 text=p.read_text()
 assert 'import WebKit' not in text and 'WKWebView' not in text and 'import Capacitor' not in text
 assert 'service_role' not in text and 'sb_secret_' not in text
assert 'kSecAttrAccessibleWhenUnlockedThisDeviceOnly' in source
assert 'URLSessionConfiguration.ephemeral' in source
assert 'sessionGeneration' in source
assert not list(root.rglob('*.html'))
print('PASS: no web runtime, no privileged key, protected local session, no private disk cache')
