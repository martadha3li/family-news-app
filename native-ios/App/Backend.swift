import Foundation
import SwiftUI
import Security
import UIKit

struct Item: Identifiable {
    let raw: [String: Any]
    init(_ raw: [String: Any] = [:]) { self.raw = raw }
    var id: String { text("id") }
    func text(_ key: String) -> String { guard let value = raw[key], !(value is NSNull) else { return "" }; return String(describing: value) }
    func flag(_ key: String) -> Bool { raw[key] as? Bool ?? false }
    func number(_ key: String) -> Int { (raw[key] as? NSNumber)?.intValue ?? 0 }
    func child(_ key: String) -> Item { Item(raw[key] as? [String: Any] ?? [:]) }
    func rows(_ key: String) -> [Item] { Self.items(raw[key]) }
    var imagePaths:[String] {
        let paths=raw["image_paths"] as? [String] ?? []
        return Array((paths.isEmpty ? (text("image_path").isEmpty ? []:[text("image_path")]):paths).prefix(5))
    }
    static func items(_ value: Any?) -> [Item] { (value as? [[String: Any]] ?? []).map(Item.init) }
}
struct FamilyError: LocalizedError { let text: String; var errorDescription: String? { text } }
enum CredentialStore {
    static let service = "com.martadha3li.familynews.native-session"
    static var query: [String: Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"session"] }
    static func hasSession()->Bool {var q=query;q[kSecReturnAttributes as String]=true;q[kSecMatchLimit as String]=kSecMatchLimitOne;return SecItemCopyMatching(q as CFDictionary,nil)==errSecSuccess}
    static func load() -> Data? { var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne; var out:CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&out)==errSecSuccess else{return nil}; return out as? Data }
    static func save(_ data: Data) throws { var q=query; SecItemDelete(q as CFDictionary); q[kSecValueData as String]=data; q[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly; let status=SecItemAdd(q as CFDictionary,nil); if status != errSecSuccess { throw FamilyError(text:"تعذّر حفظ جلسة الدخول بأمان. أعد المحاولة.") } }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
@MainActor final class Backend: ObservableObject {
    let origin="https://dlkykiducjimwehfhxfq.supabase.co"
    let publishable="sb_publishable_em1zUQS1tUhfk_8Ji17n8g_H8CPQynt"
    let website="https://family-news-app.nimbletide.chatgpt.site/"
    @Published var family=Item(UserDefaults.standard.dictionary(forKey:"family-selection") ?? [:])
    @Published var platformAdmin=false
    @Published var profile=Item()
    @Published var user=Item()
    @Published var signedIn=false
    @Published var restoring=true
    @Published var startupProgress=0.0
    @Published var warning=""
    private var session:[String:Any]=[:]
    private var isolatedSession=false
    private var sessionGeneration=0
    private var refreshTask:Task<Void,Error>?
    private let network:URLSession = { let c=URLSessionConfiguration.ephemeral; c.urlCache=nil; c.requestCachePolicy = .reloadIgnoringLocalCacheData; c.timeoutIntervalForRequest=30; return URLSession(configuration:c) }()
    var active:Bool { signedIn && profile.text("status")=="active" }
    var admin:Bool { active && profile.text("role")=="admin" }
    var readOnly:Bool { family.flag("read_only") || (!family.text("subscription_ends_at").isEmpty && dateValue(family.text("subscription_ends_at"))<=Date()) }
    var writer:Bool { active && !readOnly && ["admin","journalist"].contains(profile.text("role")) }
    func errorText(_ error:Error)->String { let m=error.localizedDescription; if m.contains("Invalid login credentials"){return "البريد أو كلمة المرور غير صحيحة."}; if m.contains("Email not confirmed"){return "أكد بريدك من الرسالة أولًا."}; if m.lowercased().contains("rate limit"){return "انتظر قليلًا قبل إعادة المحاولة."}; return m }
    func request(_ path:String,method:String="GET",body:[String:Any]?=nil,auth:Bool=true,data:Data?=nil,mime:String="application/json") async throws -> Any {
        let generation=sessionGeneration
        if auth { try await refreshIfNeeded(); guard session["access_token"] is String else {throw FamilyError(text:"سجل دخولك مجددًا.")} }
        guard let url=URL(string:origin+path) else {throw FamilyError(text:"عنوان الطلب غير صالح.")}
        var r=URLRequest(url:url);r.httpMethod=method;r.setValue(publishable,forHTTPHeaderField:"apikey")
        if auth,let token=session["access_token"] as? String {r.setValue("Bearer "+token,forHTTPHeaderField:"Authorization")}
        r.setValue("return=representation",forHTTPHeaderField:"Prefer")
        if let data=data {r.httpBody=data;r.setValue(mime,forHTTPHeaderField:"Content-Type")}
        else if let body=body {r.httpBody=try JSONSerialization.data(withJSONObject:body);r.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (bytes,response)=try await network.data(for:r)
        if auth && generation != sessionGeneration {throw CancellationError()}
        let json:Any=bytes.isEmpty ? NSNull() : (try JSONSerialization.jsonObject(with:bytes,options:.fragmentsAllowed))
        guard let http=response as? HTTPURLResponse else {throw FamilyError(text:"تعذّر الاتصال.")}
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode==401 && auth {clearSession()}
            let e=Item(json as? [String:Any] ?? [:]);let msg=["msg","message","error_description","error"].map{e.text($0)}.first{!$0.isEmpty} ?? "تعذّر تنفيذ الطلب (\(http.statusCode))."
            throw FamilyError(text:msg)
        }
        return json
    }
    func table(_ name:String,_ query:[URLQueryItem]=[],method:String="GET",body:[String:Any]?=nil) async throws -> [Item] {var c=URLComponents();c.queryItems=query;return Item.items(try await request("/rest/v1/"+name+(c.percentEncodedQuery.map{"?"+$0} ?? ""),method:method,body:body))}
    func rpc(_ name:String,_ body:[String:Any]=[:]) async throws -> Any {try await request("/rest/v1/rpc/"+name,method:"POST",body:body)}
    func action(_ api:String,_ name:String,_ payload:[String:Any]=[:]) async throws -> Any {try await rpc(api,["action":name,"payload":payload])}
    func refreshIfNeeded() async throws {
        guard let refresh=session["refresh_token"] as? String else {return}
        let expiry=(session["expires_at"] as? NSNumber)?.doubleValue ?? 0
        guard expiry<Date().timeIntervalSince1970+60 else {return}
        if let task=refreshTask {_ = try await task.value;return}
        let generation=sessionGeneration
        let task=Task { () throws -> Void in
            do {guard let fresh=try await self.request("/auth/v1/token?grant_type=refresh_token",method:"POST",body:["refresh_token":refresh],auth:false) as? [String:Any] else {throw FamilyError(text:"سجل دخولك مجددًا.")};guard generation==self.sessionGeneration else{throw CancellationError()};try Task.checkCancellation();try self.keep(fresh);return}
            catch {if (error as? FamilyError) != nil {self.clearSession()};throw error}
        };refreshTask=task
        defer{refreshTask=nil};_ = try await task.value
    }
    private func keep(_ value:[String:Any]) throws {var s=value;if s["expires_at"]==nil {s["expires_at"]=Date().timeIntervalSince1970+(s["expires_in"] as? Double ?? 3600)};if !isolatedSession{try CredentialStore.save(JSONSerialization.data(withJSONObject:s))};session=s}
    func restore() async {
        defer{restoring=false};startupProgress=0.15
        if let bytes=CredentialStore.load(),let value=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any]{session=value;startupProgress=0.3;do{try await loadAccount(startup:true)}catch{warning=errorText(error)}}
        startupProgress=1;try? await Task.sleep(nanoseconds:180_000_000)
    }
    func login(email:String,password:String) async throws {guard let s=try await request("/auth/v1/token?grant_type=password",method:"POST",body:["email":email.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()=="admin" ? "martadha3li@gmail.com":email.trimmingCharacters(in:.whitespacesAndNewlines),"password":password],auth:false) as? [String:Any] else{throw FamilyError(text:"تعذّر تسجيل الدخول.")};try keep(s);try await loadAccount()}
    func loadAccount(startup:Bool=false) async throws {let u=Item(try await request("/auth/v1/user") as? [String:Any] ?? [:]);if startup{startupProgress=0.6};let tenant=Item(try await rpc("tenant_current") as? [String:Any] ?? [:]);guard tenant.text("status")=="active",family.id.isEmpty || family.id==tenant.id else{clearSession();throw FamilyError(text:"الكيان موقوف أو الحساب تابع لعائلة أخرى. غيّر الكيان ثم سجّل الدخول.")};selectFamily(tenant);platformAdmin=(try? await rpc("platform_action",["action":"check"])) as? Bool ?? false;let p=Item(try await rpc("profile_get") as? [String:Any] ?? [:]);guard !u.id.isEmpty,!p.text("status").isEmpty else{throw FamilyError(text:"لم يكتمل ملف الحساب.")};if startup{startupProgress=0.9};user=u;profile=p;signedIn=true;warning=""}
    func logout() async {do {_ = try await request("/auth/v1/logout",method:"POST")}catch{};clearSession()}
    func clearSession(){sessionGeneration += 1;refreshTask?.cancel();refreshTask=nil;session=[:];if !isolatedSession{CredentialStore.clear()};signedIn=false;platformAdmin=false;user=Item();profile=Item()}
    func signup(email:String,password:String,details:[String:Any]) async throws {guard password.count>=10 else{throw FamilyError(text:"كلمة المرور 10 أحرف على الأقل.")};_ = try await request("/auth/v1/signup?redirect_to="+website.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed)!,method:"POST",body:["email":email,"password":password,"data":details.merging(["family_code":family.text("code")]){_,new in new}],auth:false)}
    func selectFamily(_ item:Item){family=item;UserDefaults.standard.set(item.raw.filter{!($0.value is NSNull)},forKey:"family-selection");FamilyTheme.update(family);syncFamilyIcon()}
    func exitFamily()async{await logout();family=Item();UserDefaults.standard.removeObject(forKey:"family-selection");FamilyTheme.update(family);syncFamilyIcon()}
    func checkFamilyAccess()async {
        let epoch=sessionGeneration
        guard signedIn else{return}
        do{let current=Item(try await rpc("tenant_current")as? [String:Any] ?? [:]);guard epoch==sessionGeneration else{return};if current.text("status") != "active"{clearSession();warning="دخول الكيان معلّق أو موقوف"}else if current.id==family.id{family=current}}catch{}
    }
    func syncFamilyIcon(){TenantAppIcon.request(family){[weak self] message in self?.warning=message}}
    func platformLogin(username:String,password:String)async throws{
        isolatedSession=true
        let email=username.lowercased()=="admin" ? "martadha3li@gmail.com":username
        guard let value=try await request("/auth/v1/token?grant_type=password",method:"POST",body:["email":email,"password":password],auth:false)as? [String:Any]else{throw FamilyError(text:"تعذّر الدخول")};session=value
        guard (try await rpc("platform_action",["action":"check"])as? Bool)==true else{session=[:];throw FamilyError(text:"الحساب ليس لإدارة المنصة")}
    }
    func recover(email:String?=nil) async throws {_ = try await request("/auth/v1/recover?redirect_to="+website.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed)!,method:"POST",body:["email":email ?? user.text("email")],auth:false)}
    func signedData(bucket:String,path:String) async throws -> Data {guard !path.isEmpty else{throw FamilyError(text:"لا توجد صورة")};let safe=path.split(separator:"/").map{String($0).addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!}.joined(separator:"/");let out=Item(try await request("/storage/v1/object/sign/"+bucket+"/"+safe,method:"POST",body:["expiresIn":600]) as? [String:Any] ?? [:]);guard let url=URL(string:origin+"/storage/v1"+out.text("signedURL")),url.scheme=="https",url.host==URL(string:origin)?.host else{throw FamilyError(text:"تعذّر تحميل الصورة.")};return try await network.data(from:url).0}
    func upload(_ original:Data,bucket:String,portrait:Bool=true,preserveAspect:Bool=false) async throws -> String {
        guard original.count<=20*1024*1024,let image=UIImage(data:original) else{throw FamilyError(text:"اختر صورة أقل من 20 ميجابايت.")}
        var result:Data?
        for attempt in 0..<7 {let scale=pow(0.8,Double(attempt));let size=preserveAspect ? CGSize(width:image.size.width*min(1,1600/max(image.size.width,image.size.height))*scale,height:image.size.height*min(1,1600/max(image.size.width,image.size.height))*scale) : (portrait ? CGSize(width:1080*scale,height:1350*scale) : CGSize(width:512*scale,height:512*scale))
            let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
            let rendered=UIGraphicsImageRenderer(size:size,format:format).image{ctx in UIColor.white.setFill();ctx.fill(CGRect(origin:.zero,size:size));let fit=portrait ? min(size.width/image.size.width,size.height/image.size.height) : max(size.width/image.size.width,size.height/image.size.height);image.draw(in:CGRect(x:(size.width-image.size.width*fit)/2,y:(size.height-image.size.height*fit)/2,width:image.size.width*fit,height:image.size.height*fit))}
            if let jpg=rendered.jpegData(compressionQuality:0.78-Double(attempt)*0.05),jpg.count<=(portrait ? 409600:204800){result=jpg;break}
        }
        guard let bytes=result else{throw FamilyError(text:"تعذّر ضغط الصورة.")};let path=user.id+"/"+UUID().uuidString.lowercased()+".jpg"
        _ = try await request("/storage/v1/object/"+bucket+"/"+path,method:"POST",data:bytes,mime:"image/jpeg");return path
    }
}
struct MentionToken:Equatable {let term:String;let range:NSRange}
func mentionToken(_ text:String,caret:Int)->MentionToken? {
    let value=text as NSString;let end=max(0,min(caret,value.length));let prefix=value.substring(to:end) as NSString
    guard let expression=try? NSRegularExpression(pattern:"(?:^|[\\s(])(@[^\\s@]*)$"),let match=expression.firstMatch(in:prefix as String,range:NSRange(location:0,length:prefix.length)) else{return nil}
    let range=match.range(at:1);let token=prefix.substring(with:range);return MentionToken(term:String(token.dropFirst()),range:range)
}
struct AnnouncementFit {let gap:Double;let cell:Double;let icon:Double;var iconsOnly:Bool{cell<68}}
func announcementFit(width:Double,count:Int)->AnnouncementFit {
    let n=Double(max(1,count));let available=max(0,width-20);let gap=min(8,available/(n*10));let cell=max(0,(available-gap*(n-1))/n)
    return AnnouncementFit(gap:gap,cell:cell,icon:max(2,min(18,cell*0.5)))
}
struct MemberMention {let range:NSRange;let id:String}
func memberMentionRanges(_ body:String,members:[Item])->[MemberMention] {
    let value=body as NSString;var result:[MemberMention]=[]
    for member in members.sorted(by:{$0.text("display_name").count>$1.text("display_name").count}) {
        let name=member.text("display_name");guard !name.isEmpty else{continue};let token="@"+name;var start=0
        while start<value.length{let range=value.range(of:token,options:[],range:NSRange(location:start,length:value.length-start));if range.location==NSNotFound{break};start=NSMaxRange(range)
            let boundary=start==value.length || value.substring(with:NSRange(location:start,length:1)).rangeOfCharacter(from:.letters)==nil
            if boundary && !result.contains(where:{NSIntersectionRange($0.range,range).length>0}){result.append(MemberMention(range:range,id:member.id))}
        }
    }
    return result.sorted{$0.range.location<$1.range.location}
}
func q(_ key:String,_ value:String)->URLQueryItem {URLQueryItem(name:key,value:value)}
func phone(_ input:String)throws->String {
    let normalized=String(input.map {c -> Character in
        if let n=c.wholeNumberValue,(0...9).contains(n){return Character(String(n))}
        return c
    })
    var s=String(normalized.filter{!$0.isWhitespace && !"()-−–".contains($0)})
    if s.hasPrefix("05"),s.count==10{s="+966"+s.dropFirst()}
    else if s.hasPrefix("00"){s="+"+s.dropFirst(2)}
    guard s.range(of:"^\\+[1-9][0-9]{7,14}$",options:.regularExpression) != nil else{throw FamilyError(text:"أدخل رقم جوال صحيحًا مثل 05xxxxxxxx.")}
    return s
}
func dateValue(_ value:String)->Date {let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f.date(from:value) ?? ISO8601DateFormatter().date(from:value) ?? .distantPast}
var brandBlue:Color{FamilyTheme.primary}
var brandPink:Color{FamilyTheme.accent}

func desiredFamilyIcon(code:String,identifier:String,available:Set<String>)->String?{
    if code=="01",available.contains("Family01"){return "Family01"}
    let key="Family_"+identifier.replacingOccurrences(of:"-",with:"").lowercased()
    return !identifier.isEmpty && available.contains(key) ? key:nil
}
@MainActor enum TenantAppIcon {
    private static var wanted:String?
    private static var busy=false
    private static var report:((String)->Void)?
    static func request(_ family:Item,report:@escaping(String)->Void){
        let info=Bundle.main.infoDictionary ?? [:]
        let icons=(info["CFBundleIcons"]as? [String:Any]) ?? (info["CFBundleIcons~ipad"]as? [String:Any]) ?? [:]
        let available=Set((icons["CFBundleAlternateIcons"]as? [String:Any] ?? [:]).keys)
        wanted=desiredFamilyIcon(code:family.text("code"),identifier:family.id,available:available)
        self.report=report;apply()
    }
    private static func apply(){
        let app=UIApplication.shared
        guard !busy,app.applicationState == .active,app.supportsAlternateIcons,app.alternateIconName != wanted else{return}
        busy=true;let target=wanted
        app.setAlternateIconName(target){error in Task{@MainActor in
            busy=false
            if let error=error{report?("تعذّر تغيير أيقونة التطبيق: "+error.localizedDescription)}
            if wanted != target{apply()}
        }}
    }
}

// Logo palettes are computed once when the selected tenant changes.
enum FamilyTheme {
    static var primary:Color{color(UserDefaults.standard.string(forKey:"family-theme-primary") ?? "123747")}
    static var accent:Color{color(UserDefaults.standard.string(forKey:"family-theme-accent") ?? "94763c")}
    static func color(_ hex:String)->Color{let n=UInt32(hex,radix:16) ?? 0x123747;return Color(red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255)}
    static func update(_ family:Item){var palette=["123747","94763c"];if family.text("code")=="01"{palette=["397b9c","ac508b"]}else if let data=Data(base64Encoded:family.text("logo").components(separatedBy:",").last ?? ""),let image=UIImage(data:data),let cg=image.cgImage{var bytes=[UInt8](repeating:0,count:64*64*4);if let ctx=CGContext(data:&bytes,width:64,height:64,bitsPerComponent:8,bytesPerRow:256,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue){ctx.draw(cg,in:CGRect(x:0,y:0,width:64,height:64));var bins:[Int:[Int]]=[:];for i in stride(from:0,to:bytes.count,by:4){let r=Int(bytes[i]),g=Int(bytes[i+1]),b=Int(bytes[i+2]);if bytes[i+3]<180 || max(r,g,b)-min(r,g,b)<30 || max(r,g,b)<35{continue};let key=(r/32)*64+(g/32)*8+b/32;var v=bins[key] ?? [0,0,0,0];v[0]+=r;v[1]+=g;v[2]+=b;v[3]+=1;bins[key]=v};let ranked=bins.values.sorted{$0[3]>$1[3]};let colors=ranked.map{v in [v[0]/v[3],v[1]/v[3],v[2]/v[3]]};if let first=colors.first{let second=colors.first{abs($0[0]-first[0])+abs($0[1]-first[1])+abs($0[2]-first[2])>150} ?? first;palette=[first,second].map{rgb in var c=rgb;while (Double(c[0])*0.2126+Double(c[1])*0.7152+Double(c[2])*0.0722)>115{c=c.map{Int(Double($0)*0.92)}};return c.map{String(format:"%02x",$0)}.joined()}}}}
        UserDefaults.standard.set(palette[0],forKey:"family-theme-primary");UserDefaults.standard.set(palette[1],forKey:"family-theme-accent")
    }
}
