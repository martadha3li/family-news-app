from pathlib import Path
import subprocess,tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'App/FamilyNewsApp.swift').read_text();f=s[s.index('func subscriptionDuration('):s.index('func subscriptionSummary(')]
tests='''
let formatter=ISO8601DateFormatter()
func duration(_ a:String,_ b:String)->String{subscriptionDuration(formatter.date(from:a)!,formatter.date(from:b)!)}
assert(duration("2027-01-31T00:00:00+03:00","2027-02-28T00:00:00+03:00")=="1 شهر")
assert(duration("2028-02-29T00:00:00+03:00","2029-02-28T00:00:00+03:00")=="1 سنة")
assert(duration("2026-01-01T00:00:00+03:00","2026-01-10T02:03:00+03:00")=="1 أسبوع و 2 يوم و 2 ساعة و 3 دقيقة")
print("PASS: native subscription calendar arithmetic, Riyadh timezone, leap years and all duration units")
'''
with tempfile.TemporaryDirectory()as tmp:
 p=Path(tmp)/'subscription.swift';p.write_text('import Foundation\n'+f+tests);subprocess.run(['swift',str(p)],check=True)
