from pathlib import Path
import subprocess,tempfile,plistlib
root=Path(__file__).resolve().parents[1]
source=(root/'App/Backend.swift').read_text()
core=source[source.index('struct Item:'):source.index('enum CredentialStore')]
core += source[source.index('struct MentionToken:'):source.index('func q(')]
core += source[source.index('func q('):source.index('let brandBlue=')]
tests=r'''
func expect(_ value:Bool,_ label:String) {precondition(value,label)}
expect(try phone("0501234567")=="+966501234567","Saudi mobile")
expect(try phone("٠٥٠١٢٣٤٥٦٧")=="+966501234567","Arabic digits")
expect(try phone("۰۰۹۶۶۵۰۱۲۳۴۵۶۷")=="+966501234567","Persian digits and international prefix")
expect(try phone("+966 (50) 123-4567")=="+966501234567","Formatted international number")
for value in ["", "+966", "phone", "05012345678999999999"] {do {_ = try phone(value);fatalError("Accepted invalid phone")}catch{}}
expect(Item(["image_path":"old.jpg"]).imagePaths==["old.jpg"],"Legacy cover")
expect(Item(["image_paths":["1.jpg","2.jpg"],"image_path":"1.jpg"]).imagePaths==["1.jpg","2.jpg"],"Ordered album")
expect(Item(["image_paths":[],"image_path":NSNull()]).imagePaths.isEmpty,"No image")
expect(Item(["image_paths":["1","2","3","4","5","6"]]).imagePaths.count==5,"Display limit")
expect(mentionToken("مرحبا @",caret:8)?.term=="","At opens suggestions")
let mentionText="خبر @أحمد"
expect(mentionToken(mentionText,caret:(mentionText as NSString).length)?.term=="أحمد","Arabic mention prefix")
expect(mentionToken("a@example.com",caret:13)==nil,"Email is not a mention")
expect(mentionToken("مرحبا @أحمد ",caret:13)==nil,"Completed mention")
let middle="@علي ثم باقي النص"
expect(mentionToken(middle,caret:4)?.term=="علي","Caret in middle of text")
for width in [280.0,320,390,768,1200] {for count in [1,2,3,5,10,50,200] {let fit=announcementFit(width:width,count:count);expect(fit.cell*Double(count)+fit.gap*Double(count-1)<=width-20+0.001,"All ads fit without scrolling")}}
expect(!announcementFit(width:390,count:2).iconsOnly,"Two ads show titles")
expect(announcementFit(width:320,count:5).iconsOnly,"Crowded ads become icons")
let mentions=memberMentionRanges("خبر @أحمد علي ثم @أحمد علي",members:[Item(["id":"u1","display_name":"أحمد علي"])])
expect(mentions.count==2 && mentions.allSatisfy{$0.id=="u1"},"Every saved mention links to the same member")
expect(memberMentionRanges("@أحمد عليان",members:[Item(["id":"u1","display_name":"أحمد علي"])]).isEmpty,"Do not link a name prefix")
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

news=(root/'App/News.swift').read_text()
alerts=(root/'App/Notifications.swift').read_text()
assert 'maxSelectionCount:5-album.count' in news
assert 'aspectRatio(4.0/5.0' in news and '.tabViewStyle(.page' in news
assert 'safeAreaInset(edge:.top' in news and 'AnnouncementTabs' in news
assert 'registerForRemoteNotifications' not in alerts
assert 'removeAllDeliveredNotifications' in alerts and 'owner==identity' in alerts
print('PASS: album compatibility, five-photo limit, fixed carousel, pinned announcements, notification privacy and free signing')

assert 'sheet(isPresented:$comments)' not in news
assert 'InlineComments(post:post' in news and '.frame(height:64)' in news
assert 'MentionEditor' in news and 'mention_search' in news
assert plist['CFBundleShortVersionString']=='$(MARKETING_VERSION)'
print('PASS: inline comments, bounded ad bar, mention caret and dynamic build version')
