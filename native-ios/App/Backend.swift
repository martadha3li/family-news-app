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
    static func items(_ value: Any?) -> [Item] { (value as? [[String: Any]] ?? []).map(Item.init) }
}
struct FamilyError: LocalizedError { let text: String; var errorDescription: String? { text } }
enum CredentialStore {
    static let service = "com.martadha3li.familynews.native-session"
    static var query: [String: Any] { [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"session"] }
    static func load() -> Data? { var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne; var out:CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&out)==errSecSuccess else{return nil}; return out as? Data }
    static func save(_ data: Data) throws { var q=query; SecItemDelete(q as CFDictionary); q[kSecValueData as String]=data; q[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly; let status=SecItemAdd(q as CFDictionary,nil); if status != errSecSuccess { throw FamilyError(text:"تعذّر حفظ جلسة الدخول بأمان. أعد المحاولة.") } }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
@MainActor final class Backend: ObservableObject {
    let origin="https://dlkykiducjimwehfhxfq.supabase.co"
    let publishable="sb_publishable_em1zUQS1tUhfk_8Ji17n8g_H8CPQynt"
    let website="https://family-news-app.nimbletide.chatgpt.site/"
    @Published var profile=Item()
    @Published var user=Item()
    @Published var signedIn=false
    @Published var restoring=true
    @Published var warning=""
    private var session:[String:Any]=[:]
    private var sessionGeneration=0
    private var refreshTask:Task<[String:Any],Error>?
    private let network:URLSession = { let c=URLSessionConfiguration.ephemeral; c.urlCache=nil; c.requestCachePolicy = .reloadIgnoringLocalCacheData; c.timeoutIntervalForRequest=30; return URLSession(configuration:c) }()
    var active:Bool { signedIn && profile.text("status")=="active" }
    var admin:Bool { active && profile.text("role")=="admin" }
    var writer:Bool { active && ["admin","journalist"].contains(profile.text("role")) }
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
        let task=Task { () throws -> [String:Any] in
            do {guard let fresh=try await self.request("/auth/v1/token?grant_type=refresh_token",method:"POST",body:["refresh_token":refresh],auth:false) as? [String:Any] else {throw FamilyError(text:"سجل دخولك مجددًا.")};guard generation==self.sessionGeneration else{throw CancellationError()};try Task.checkCancellation();try self.keep(fresh);return fresh}
            catch {if (error as? FamilyError) != nil {self.clearSession()};throw error}
        };refreshTask=task
        defer{refreshTask=nil};_ = try await task.value
    }
    private func keep(_ value:[String:Any]) throws {var s=value;if s["expires_at"]==nil {s["expires_at"]=Date().timeIntervalSince1970+(s["expires_in"] as? Double ?? 3600)};try CredentialStore.save(JSONSerialization.data(withJSONObject:s));session=s}
    func restore() async {defer{restoring=false};guard let bytes=CredentialStore.load(),let value=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] else{return};session=value;do{try await loadAccount()}catch{warning=errorText(error)}}
    func login(email:String,password:String) async throws {guard let s=try await request("/auth/v1/token?grant_type=password",method:"POST",body:["email":email.trimmingCharacters(in:.whitespacesAndNewlines),"password":password],auth:false) as? [String:Any] else{throw FamilyError(text:"تعذّر تسجيل الدخول.")};try keep(s);try await loadAccount()}
    func loadAccount() async throws {let u=Item(try await request("/auth/v1/user") as? [String:Any] ?? [:]);let p=Item(try await rpc("profile_get") as? [String:Any] ?? [:]);guard !u.id.isEmpty,!p.text("status").isEmpty else{throw FamilyError(text:"لم يكتمل ملف الحساب.")};user=u;profile=p;signedIn=true;warning=""}
    func logout() async {do {_ = try await request("/auth/v1/logout",method:"POST")}catch{};clearSession()}
    func clearSession(){sessionGeneration += 1;refreshTask?.cancel();refreshTask=nil;session=[:];CredentialStore.clear();signedIn=false;user=Item();profile=Item()}
    func signup(email:String,password:String,details:[String:Any]) async throws {guard password.count>=10 else{throw FamilyError(text:"كلمة المرور 10 أحرف على الأقل.")};_ = try await request("/auth/v1/signup?redirect_to="+website.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed)!,method:"POST",body:["email":email,"password":password,"data":details],auth:false)}
    func recover(email:String?=nil) async throws {_ = try await request("/auth/v1/recover?redirect_to="+website.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed)!,method:"POST",body:["email":email ?? user.text("email")],auth:false)}
    func signedData(bucket:String,path:String) async throws -> Data {guard !path.isEmpty else{throw FamilyError(text:"لا توجد صورة")};let safe=path.split(separator:"/").map{String($0).addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!}.joined(separator:"/");let out=Item(try await request("/storage/v1/object/sign/"+bucket+"/"+safe,method:"POST",body:["expiresIn":600]) as? [String:Any] ?? [:]);guard let url=URL(string:origin+"/storage/v1"+out.text("signedURL")),url.scheme=="https",url.host==URL(string:origin)?.host else{throw FamilyError(text:"تعذّر تحميل الصورة.")};return try await network.data(from:url).0}
    func upload(_ original:Data,bucket:String,portrait:Bool=true) async throws -> String {
        guard original.count<=20*1024*1024,let image=UIImage(data:original) else{throw FamilyError(text:"اختر صورة أقل من 20 ميجابايت.")}
        var result:Data?
        for attempt in 0..<7 {let scale=pow(0.8,Double(attempt));let size=portrait ? CGSize(width:1080*scale,height:1350*scale) : CGSize(width:512*scale,height:512*scale)
            let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
            let rendered=UIGraphicsImageRenderer(size:size,format:format).image{ctx in UIColor.white.setFill();ctx.fill(CGRect(origin:.zero,size:size));let fit=portrait ? min(size.width/image.size.width,size.height/image.size.height) : max(size.width/image.size.width,size.height/image.size.height);image.draw(in:CGRect(x:(size.width-image.size.width*fit)/2,y:(size.height-image.size.height*fit)/2,width:image.size.width*fit,height:image.size.height*fit))}
            if let jpg=rendered.jpegData(compressionQuality:0.78-Double(attempt)*0.05),jpg.count<=(portrait ? 409600:204800){result=jpg;break}
        }
        guard let bytes=result else{throw FamilyError(text:"تعذّر ضغط الصورة.")};let path=user.id+"/"+UUID().uuidString.lowercased()+".jpg"
        _ = try await request("/storage/v1/object/"+bucket+"/"+path,method:"POST",data:bytes,mime:"image/jpeg");return path
    }
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
let brandBlue=Color(red:0.224,green:0.482,blue:0.612)
let brandPink=Color(red:0.675,green:0.314,blue:0.545)
