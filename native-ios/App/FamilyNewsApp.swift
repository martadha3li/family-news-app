import SwiftUI
import PhotosUI
import UIKit
import LocalAuthentication

@main struct FamilyNewsApp: App {
    @StateObject private var api=Backend()
    @StateObject private var alerts=NativeNotifications()
    var body:some Scene {WindowGroup {RootScreen().environmentObject(api).environmentObject(alerts).environment(\.layoutDirection,.rightToLeft).environment(\.locale,Locale(identifier:"ar_SA")).tint(brandBlue)}}
}
struct TaskButton:View {
    let title:String
    var symbol:String=""
    var action:() async throws -> Void
    @EnvironmentObject private var api:Backend
    @State private var busy=false
    @State private var error=""
    var body:some View {Button{busy=true;Task{defer{busy=false};do{try await action()}catch{self.error=api.errorText(error)}}}label:{HStack(spacing:7){if busy{ProgressView()}else if !symbol.isEmpty{Image(systemName:symbol)};if !title.isEmpty{Text(title)}}.frame(minHeight:30)}.disabled(busy).alert("تعذّر إكمال الطلب",isPresented:Binding(get:{!error.isEmpty},set:{if !$0{error=""}})){Button("حسنًا",role:.cancel){}}message:{Text(error)}}
}
struct LoadError:View {let text:String;var body:some View{if !text.isEmpty{Text(text).font(.footnote).foregroundStyle(.red).padding().frame(maxWidth:.infinity)}}}
struct EmptyState:View {let title:String;var symbol="tray";var body:some View{VStack(spacing:12){Image(systemName:symbol).font(.system(size:38,weight:.light)).foregroundStyle(brandBlue);Text(title).font(.headline)}.frame(maxWidth:.infinity).padding(.vertical,50)}}
struct Brand:View {@EnvironmentObject private var api:Backend;var body:some View{HStack{if let image=tenantLogo(api.family){Image(uiImage:image).resizable().scaledToFit().frame(width:48,height:42);Text(api.family.text("name")).font(.headline).lineLimit(1)}else{Image("FamilyLogo").resizable().scaledToFit().frame(width:135,height:42)}}.accessibilityLabel(api.family.text("name").isEmpty ? "أخبار العائلة":api.family.text("name"))}}
func tenantLogo(_ tenant:Item)->UIImage?{guard let encoded=tenant.text("logo").split(separator:",").last,tenant.text("logo").hasPrefix("data:image/jpeg;base64,"),let data=Data(base64Encoded:String(encoded))else{return nil};return UIImage(data:data)}
struct PrivateImage:View {
    @EnvironmentObject private var api:Backend
    let path:String
    var bucket="profile-images"
    var fill=true
    @State private var image:UIImage?
    @State private var failed=false
    @State private var retry=0
    var body:some View {ZStack{Color(.secondarySystemBackground);if let image=image{if fill{Image(uiImage:image).resizable().scaledToFill()}else{Image(uiImage:image).resizable().scaledToFit()}}else if failed{Button{retry += 1}label:{Image(systemName:"arrow.clockwise").padding()}.accessibilityLabel("إعادة تحميل الصورة")}else{ProgressView()}}.clipped().task(id:path+String(retry)){guard !path.isEmpty else{return};do{let data=try await api.signedData(bucket:bucket,path:path);try Task.checkCancellation();image=UIImage(data:data);failed=image==nil}catch{if !Task.isCancelled{failed=true}}}.privacySensitive()}
}
struct Avatar:View {let path:String;let name:String;var size:CGFloat=42;var body:some View{Group{if path.isEmpty{ZStack{brandBlue.opacity(0.1);Text(String(name.prefix(1))).font(.system(size:size*0.4,weight:.semibold)).foregroundStyle(brandBlue)}}else{PrivateImage(path:path)}}.frame(width:size,height:size).clipShape(Circle()).accessibilityHidden(true)}}
struct RootScreen:View {
    @EnvironmentObject private var api:Backend
    @EnvironmentObject private var alerts:NativeNotifications
    @StateObject private var gate=BiometricGate()
    @Environment(\.scenePhase) private var phase
    var body:some View {
        Group {
            if api.family.id.isEmpty{TenantSelectionScreen()}
            else if (gate.hasSession || api.signedIn) && !gate.unlocked{BiometricLockScreen(gate:gate,api:api)}
            else if api.restoring{LaunchScreen(progress:api.startupProgress)}
            else if !api.signedIn{LoginScreen()}
            else{HomeScreen()}
        }.task(id:api.family.id){if api.family.id.isEmpty{api.restoring=false}else{await gate.start(api)}}
        .task(id:String(api.active)+String(gate.unlocked)+String(describing:phase)){
            guard api.active,gate.unlocked,phase == .active else{return};await alerts.updatePermission()
            while !Task.isCancelled && api.active && gate.unlocked && phase == .active{await alerts.refresh(api);do{try await Task.sleep(nanoseconds:15_000_000_000)}catch{break}}
        }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.willResignActiveNotification)){_ in PrivacyShield.show()}
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didBecomeActiveNotification)){_ in PrivacyShield.hide()}
        .onChange(of:api.signedIn){_,value in if value{Task{await gate.afterPasswordLogin(api)}}else{alerts.reset();gate.signedOut()}}
        .onChange(of:api.active){_,value in if !value{alerts.reset()}}
        .onChange(of:phase){_,value in
            if value == .background{gate.lock();alerts.visibleThread=""}
            if value == .active{Task{await gate.open(api)}}
        }
    }
}
struct LoginScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var email=""
    @State private var password=""
    @State private var signup=false
    @State private var full=""
    @State private var mobile=""
    @State private var gender="male"
    @State private var reference=""
    @State private var relationship="father"
    @State private var sponsor=""
    @State private var sent=false
    @State private var recoverySent=false
    @State private var kinship:[Item]=[]
    @FocusState private var field:Int?
    var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading,spacing:22){Brand().frame(maxWidth:.infinity).padding(.top,30);VStack(alignment:.leading,spacing:8){Text(signup ? "مكانك بيننا":"أهلًا بعودتك").font(.largeTitle.bold());Text("أخبار العائلة ومناسباتها… أقرب إليك.").foregroundStyle(.secondary)};Picker("نوع الدخول",selection:$signup){Text("تسجيل الدخول").tag(false);Text("حساب جديد").tag(true)}.pickerStyle(.segmented)
        VStack(spacing:16){TextField("البريد الإلكتروني",text:$email).keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($field,equals:0).submitLabel(.next).onSubmit{field=1};SecureField("كلمة المرور",text:$password).textContentType(signup ? .newPassword:.password).focused($field,equals:1).submitLabel(.go)}.textFieldStyle(.roundedBorder)
        if signup{Group{TextField("الاسم الرباعي",text:$full).textContentType(.name);TextField("رقم الجوال",text:$mobile).keyboardType(.phonePad);Picker("الجنس",selection:$gender){Text("ذكر").tag("male");Text("أنثى").tag("female")};if gender=="female"{TextField("اسم المعرّف من العائلة (رباعي)",text:$reference);Picker("صلة القرابة",selection:$relationship){ForEach(kinship,id:\.rawCode){o in Text(o.text("label")).tag(o.text("code"))}}};TextField("اسم المعرّف أو جواله (اختياري)",text:$sponsor)}.textFieldStyle(.roundedBorder)}
        TaskButton(title:signup ? "إنشاء حساب":"تسجيل الدخول",symbol:"arrow.left"){field=nil;if signup{guard full.split(whereSeparator:{$0.isWhitespace}).count==4 else{throw FamilyError(text:"أدخل الاسم الرباعي.")};if gender=="female" && reference.trimmingCharacters(in:.whitespaces).isEmpty{throw FamilyError(text:"أدخل اسم المعرّف.")};try await api.signup(email:email,password:password,details:["display_name":full,"full_name":full,"phone":try phone(mobile),"gender":gender,"reference_name":gender=="female" ? reference:"","relationship":gender=="female" ? relationship:"","sponsor_hint":sponsor]);sent=true;password=""}else{try await api.login(email:email,password:password);password=""}}.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth:.infinity)
        if !signup{TaskButton(title:"نسيت كلمة المرور؟",symbol:"key"){guard email.contains("@") else{throw FamilyError(text:"أدخل بريدك أولًا.")};try await api.recover(email:email);recoverySent=true}}
        Button("تغيير الكيان العائلي"){Task{await api.exitFamily()}};LoadError(text:api.warning);Text("حسابات العائلة محمية. يتطلب التسجيل تأكيد البريد واعتماد الحساب وفق ضوابط المدير.").font(.footnote).foregroundStyle(.secondary)
    }.padding(24).frame(maxWidth:520).frame(maxWidth:.infinity)}.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).navigationTitle("").task{do{kinship=Item.items(try await api.request("/rest/v1/rpc/tenant_kinship",method:"POST",body:["code":api.family.text("code")],auth:false));if !kinship.contains(where:{$0.text("code")==relationship}){relationship=kinship.first?.text("code") ?? ""}}catch{}}.alert("تغيير كلمة المرور",isPresented:$recoverySent){Button("حسنًا",role:.cancel){}}message:{Text("أرسلنا رابط التحقق إلى بريدك. افتحه لإكمال تغيير كلمة المرور.")}.toolbar{ToolbarItemGroup(placement:.keyboard){Spacer();Button("تم"){field=nil}}}.alert("تأكيد البريد",isPresented:$sent){Button("حسنًا"){signup=false}}message:{Text("أرسلنا رسالة التأكيد. افتح أحدث رسالة، ثم عد إلى التطبيق وسجل الدخول.")}}}
}
struct HomeScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var selection=0
    @State private var campaign:PopupCampaign?
    @State private var checkedCampaign=false
    @State private var chats=false
    @State private var notifications=false
    var body:some View{TabView(selection:$selection){NavigationStack{if api.active{NewsScreen()}else{VStack(spacing:20){Image(systemName:"person.badge.clock").font(.largeTitle);Text(api.profile.text("status")=="suspended" ? "الحساب موقوف مؤقتًا":"حسابك بانتظار الاعتماد").font(.title3);TaskButton(title:"تحديث حالة الحساب",symbol:"arrow.clockwise"){try await api.loadAccount()};NavigationLink("إكمال ملفي"){ProfileScreen()}}.padding()}}.tabItem{Label("الأخبار",systemImage:"house")}.tag(0)
        if api.active{Color.clear.tabItem{Label("الدردشات",systemImage:"bubble.left.and.bubble.right")}.tag(1)}
        NavigationStack{ProfileScreen()}.tabItem{Label("حسابي",systemImage:"person.crop.circle")}.tag(2)
        NavigationStack{MoreScreen()}.tabItem{Label("المزيد",systemImage:"line.3.horizontal")}.tag(3)
    }.task(id:api.active){
        guard api.active,!checkedCampaign else{return};checkedCampaign=true
        let owner=api.user.id
        do{
            let ads=Item.items(try await api.rpc("promo_due"))
            for ad in ads{
                try Task.checkCancellation()
                let key="promo-hidden-"+owner+"-"+ad.id
                if UserDefaults.standard.bool(forKey:key){_ = try? await api.rpc("promo_hide",["ad_id":Int(ad.id) ?? 0,"hide":true]);continue}
                guard let image=UIImage(data:try await api.signedData(bucket:"ad-images",path:ad.text("image_path"))) else{continue}
                let claim=try await api.rpc("promo_claim",["ad_id":Int(ad.id) ?? 0]) as? Bool ?? false
                guard api.user.id==owner,api.active,!Task.isCancelled else{return}
                if claim{campaign=PopupCampaign(ad:ad,image:image);break}
            }
        }catch{}
    }.fullScreenCover(item:$campaign){item in PopupAdvertisement(campaign:item).environmentObject(api)}.onReceive(NotificationCenter.default.publisher(for:.openFamilyNotifications)){_ in if api.active{chats=false;notifications=true}}.sheet(isPresented:$notifications){NavigationStack{NotificationsScreen()}}.onChange(of:selection){_,value in if value==1{selection=0;chats=true}}.fullScreenCover(isPresented:$chats){NavigationStack{ChatsScreen()}.environmentObject(api)} }
}

struct LaunchScreen:View {
    @EnvironmentObject private var api:Backend
    let progress:Double
    @Environment(\.accessibilityReduceMotion)private var reduceMotion
    @State private var animate=false
    var body:some View {
        ZStack{Color(.systemBackground).ignoresSafeArea();VStack(spacing:28){
            ZStack{Circle().stroke(brandBlue.opacity(0.08),lineWidth:1).frame(width:200,height:200);Circle().trim(from:0,to:0.68).stroke(AngularGradient(colors:[brandBlue,brandPink,brandBlue.opacity(0.1)],center:.center),style:StrokeStyle(lineWidth:3,lineCap:.round)).frame(width:200,height:200).rotationEffect(.degrees(animate && !reduceMotion ? 360:0));Group{if let logo=tenantLogo(api.family){Image(uiImage:logo).resizable().scaledToFit()}else{Image("AppIconPreview").resizable().scaledToFit()}}.frame(width:120,height:120).scaleEffect(animate && !reduceMotion ? 1.045:0.96)}
            Brand();VStack(spacing:10){ProgressView(value:progress).tint(brandBlue).frame(width:180);Text("\(Int(progress*100))٪").font(.system(size:20,weight:.semibold,design:.rounded)).monospacedDigit();Text("جاري تهيئة أخبار العائلة").font(.footnote).foregroundStyle(.secondary)}
        }}.onAppear{withAnimation(.easeInOut(duration:1.6).repeatForever(autoreverses:true)){animate=true}}.animation(.easeInOut(duration:0.2),value:progress)
    }
}

@MainActor final class BiometricGate:ObservableObject {
    @Published private(set) var unlocked=false
    @Published private(set) var busy=false
    @Published private(set) var hasSession=CredentialStore.hasSession()
    @Published var message=""
    @Published private(set) var title="بصمة الجهاز"
    @Published private(set) var symbol="faceid"
    private var context:LAContext?
    private var generation=0
    private var starting=true
    private var automaticAttempted=false
    func describe(_ context:LAContext){switch context.biometryType{case .touchID:title="Touch ID";symbol="touchid";case .faceID:title="Face ID";symbol="faceid";default:title="بصمة الجهاز";symbol="lock.fill"}}
    func start(_ api:Backend)async {
        starting=false
        if hasSession{await open(api)}else{await api.restore()}
    }
    func afterPasswordLogin(_ api:Backend)async {
        hasSession=true;guard !unlocked,!busy,UIApplication.shared.applicationState == .active else{return}
        let probe=LAContext();var error:NSError?;let available=probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,error:&error);describe(probe)
        if !available{unlocked=true;message="";return} // The password has just been verified by the server.
        await open(api)
    }
    func open(_ api:Backend,automatic:Bool=true)async {
        guard !starting,!busy,!unlocked,hasSession || api.signedIn,!(automatic && automaticAttempted),UIApplication.shared.applicationState == .active else{return}
        automaticAttempted=true
        let identity=generation;let context=LAContext();self.context=context
        context.localizedCancelTitle="إلغاء";context.localizedFallbackTitle="";context.touchIDAuthenticationAllowableReuseDuration=0
        var error:NSError?;let available=context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,error:&error);describe(context)
        guard available else{message="فعّل بصمة الوجه أو الإصبع في إعدادات الجهاز، أو سجّل الدخول بالبريد وكلمة المرور.";self.context=nil;return}
        busy=true;message=""
        do {
            let success=try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,localizedReason:"افتح أخبار العائلة باستخدام بصمتك")
            guard identity==generation,success else{if identity==generation{busy=false};return}
            unlocked=true;busy=false;self.context=nil
            if !api.signedIn{await api.restore()}else{do{try await api.loadAccount()}catch{api.warning=api.errorText(error)}}
        }catch {
            guard identity==generation else{return};busy=false;self.context=nil;unlocked=false
            if let local=error as? LAError,local.code == .userCancel || local.code == .systemCancel || local.code == .appCancel{message="التطبيق مقفل. اضغط المحاولة مجددًا للفتح."}else{message="لم يتم التحقق من البصمة. أعد المحاولة أو سجّل الدخول بكلمة المرور."}
        }
    }
    func lock(){guard hasSession else{return};automaticAttempted=false;generation += 1;context?.invalidate();context=nil;busy=false;unlocked=false;message=""}
    func signedOut(){automaticAttempted=false;generation += 1;context?.invalidate();context=nil;busy=false;unlocked=false;hasSession=false;message=""}
    func passwordLogin(_ api:Backend){signedOut();api.clearSession();api.restoring=false}
}
struct BiometricLockScreen:View {
    @ObservedObject var gate:BiometricGate
    @ObservedObject var api:Backend
    var body:some View {
        VStack(spacing:24){Spacer();Brand();Image(systemName:gate.symbol).font(.system(size:60,weight:.light)).foregroundStyle(brandBlue);Text("أخبار العائلة مقفل").font(.title2.bold());Text("افتح التطبيق باستخدام "+gate.title).font(.subheadline).foregroundStyle(.secondary)
            if !gate.message.isEmpty{Text(gate.message).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)}
            Button{Task{await gate.open(api,automatic:false)}}label:{HStack{if gate.busy{ProgressView()}else{Image(systemName:gate.symbol)};Text("فتح باستخدام "+gate.title)}.frame(maxWidth:.infinity).padding(12)}.buttonStyle(.borderedProminent).disabled(gate.busy)
            Button("تسجيل الدخول بالبريد وكلمة المرور"){gate.passwordLogin(api)}.font(.subheadline).disabled(gate.busy)
            Spacer();Text("تُفحص البصمة بواسطة الجهاز، ولا تُرسل صور الوجه أو البصمة إلى التطبيق.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(28).frame(maxWidth:480).frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(.systemBackground)).privacySensitive()
    }
}
@MainActor enum PrivacyShield {
    static var covers:[UIView]=[]
    static func show(){guard covers.isEmpty else{return};for scene in UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}){for window in scene.windows where window.isKeyWindow{
        let cover=UIView(frame:window.bounds);cover.autoresizingMask=[.flexibleWidth,.flexibleHeight];cover.backgroundColor = .systemBackground;cover.isUserInteractionEnabled=true
        let logo=UIImageView(image:UIImage(named:"FamilyLogo"));logo.contentMode = .scaleAspectFit;logo.translatesAutoresizingMaskIntoConstraints=false;cover.addSubview(logo);NSLayoutConstraint.activate([logo.centerXAnchor.constraint(equalTo:cover.centerXAnchor),logo.centerYAnchor.constraint(equalTo:cover.centerYAnchor),logo.widthAnchor.constraint(equalToConstant:190),logo.heightAnchor.constraint(equalToConstant:70)])
        window.addSubview(cover);covers.append(cover)
    }}}
    static func hide(){for cover in covers{cover.removeFromSuperview()};covers=[]}
}

struct TenantSelectionScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var term=""
    @State private var families:[Item]=[]
    @State private var error=""
    @State private var selected:Item?
    @State private var request=false
    @State private var platform=false
    var body:some View{NavigationStack{List{
        Section{Text("اختر عائلتك مرة واحدة. يُحفظ الاختيار على هذا الجهاز، ويمكن تغييره لاحقًا.").font(.subheadline);TextField("كود العائلة أو اسمها",text:$term).textInputAutocapitalization(.never);LoadError(text:error)}
        Section("العوائل المتاحة"){ForEach(families){family in Button{selected=family}label:{HStack(spacing:12){if let image=tenantLogo(family){Image(uiImage:image).resizable().scaledToFit().frame(width:48,height:48)};VStack(alignment:.leading){Text(family.text("name")).font(.headline);Text("الكود "+family.text("code")).font(.caption)}}}}}
        Section{Button("تسجيل عائلة جديدة"){request=true};Button("دخول إدارة المنصة"){platform=true}}
    }.navigationTitle("أهلًا بك").task(id:term){do{try await Task.sleep(nanoseconds:220_000_000);let rows=Item.items(try await api.request("/rest/v1/rpc/tenant_directory",method:"POST",body:["term":term],auth:false));try Task.checkCancellation();families=rows;error=""}catch{if !Task.isCancelled{self.error=api.errorText(error)}}}
    .confirmationDialog(selected?.text("name") ?? "",isPresented:Binding(get:{selected != nil},set:{if !$0{selected=nil}}),titleVisibility:.visible){Button("تأكيد الدخول وحفظ الكيان"){if let family=selected{Task{if api.signedIn{await api.logout()};api.selectFamily(family);selected=nil}}}}message:{Text("ستفتح واجهة هذه العائلة مباشرة في المرات القادمة.")}
    .sheet(isPresented:$request){NavigationStack{TenantRequestScreen()}}
    .sheet(isPresented:$platform){TenantPlatformLogin()}
    }}
}
struct TenantRequestScreen:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss)private var dismiss
    @State private var name=""
    @State private var phoneText=""
    @State private var email=""
    @State private var photo:PhotosPickerItem?
    @State private var logo:UIImage?
    @State private var sent=false
    @State private var error=""
    var body:some View{Form{Section("طلب كيان عائلي"){TextField("اسم العائلة",text:$name);TextField("رقم التواصل",text:$phoneText).keyboardType(.phonePad);TextField("البريد الإلكتروني",text:$email).keyboardType(.emailAddress).textInputAutocapitalization(.never);PhotosPicker(selection:$photo,matching:.images){Label("شعار العائلة",systemImage:"photo")};if let image=logo{Image(uiImage:image).resizable().scaledToFit().frame(height:140)};LoadError(text:error);Text("يبقى الطلب بانتظار مراجعة إدارة المنصة والتواصل بشأن الرسوم والتفعيل.").font(.footnote)};TaskButton(title:"إرسال الطلب",symbol:"paperplane"){
        guard let image=logo else{throw FamilyError(text:"اختر شعار العائلة")};let scale=min(1,512/max(image.size.width,image.size.height));let size=CGSize(width:image.size.width*scale,height:image.size.height*scale);let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true;let rendered=UIGraphicsImageRenderer(size:size,format:format).image{ctx in UIColor.white.setFill();ctx.fill(CGRect(origin:.zero,size:size));image.draw(in:CGRect(origin:.zero,size:size))};guard let data=rendered.jpegData(compressionQuality:0.72),data.count<=200000 else{throw FamilyError(text:"اختر شعارًا أصغر")}
        _ = try await api.request("/rest/v1/rpc/tenant_request",method:"POST",body:["data":["name":name,"phone":try phone(phoneText),"email":email,"logo":"data:image/jpeg;base64,"+data.base64EncodedString()]],auth:false);sent=true
    }}.navigationTitle("تسجيل عائلة").toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){dismiss()}}}.onChange(of:photo){_,item in Task{do{guard let data=try await item?.loadTransferable(type:Data.self),data.count<=20*1024*1024,let image=UIImage(data:data)else{throw FamilyError(text:"اختر صورة صالحة أقل من 20 ميجابايت")};logo=image;error=""}catch{self.error=api.errorText(error)}}}.alert("تم استلام الطلب",isPresented:$sent){Button("حسنًا"){dismiss()}}message:{Text("بانتظار تواصل إدارة المنصة بشأن الرسوم والتفعيل.")}}
}
struct TenantPlatformLogin:View {
    @StateObject private var portal=Backend()
    @Environment(\.dismiss)private var dismiss
    @Environment(\.scenePhase)private var phase
    @State private var username="admin"
    @State private var password=""
    @State private var authorized=false
    var body:some View{NavigationStack{Group{if authorized{TenantPlatformList().environmentObject(portal)}else{Form{Text("إدارة المنصة للمالك المتحقق منه. استخدم كلمة مرور حسابك الحالية.").font(.footnote);TextField("اسم الدخول أو البريد",text:$username).textInputAutocapitalization(.never);SecureField("كلمة المرور",text:$password);TaskButton(title:"دخول الإدارة",symbol:"lock.shield"){try await portal.platformLogin(username:username,password:password);password="";authorized=true}}.environmentObject(portal).navigationTitle("إدارة المنصة")}}.toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){portal.clearSession();dismiss()}}}}.onChange(of:phase){_,value in if value == .background{portal.clearSession();dismiss()}}}
}
struct TenantPlatformList:View {
    @EnvironmentObject private var api:Backend
    @State private var tenants:[Item]=[]
    @State private var error=""
    @State private var edit:Item?
    func load()async{do{tenants=Item.items(try await api.rpc("platform_action",["action":"list"]));error=""}catch{self.error=api.errorText(error)}}
    var body:some View{List{Section{Text("تسجيل الرسوم والسداد يدويًا، ثم تفعيل الكيان. لا توجد بوابة دفع مفعّلة.").font(.footnote)};LoadError(text:error);ForEach(tenants){family in Button{edit=family}label:{VStack(alignment:.leading,spacing:7){Text(family.text("name")).font(.headline);Text("الكود "+family.text("code")+" · "+family.text("status")).font(.caption);Text("\(family.number("members")) عضو · \(family.number("posts")) خبر").font(.caption)}}}}.navigationTitle("الكيانات العائلية").task{await load()}.refreshable{await load()}.sheet(item:$edit){family in NavigationStack{TenantPlatformEditor(family:family){await load()}}}}
}
struct TenantPlatformEditor:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss)private var dismiss
    let family:Item
    let saved:()async->Void
    @State private var name=""
    @State private var code=""
    @State private var status="pending"
    @State private var payment="unpaid"
    @State private var fee="0"
    @State private var notes=""
    var body:some View{Form{Section("بيانات الكيان"){TextField("اسم العائلة",text:$name);TextField("الكود",text:$code).textInputAutocapitalization(.never);Text(family.text("contact_email"));Text(family.text("contact_phone"))};Section("السداد والتفعيل"){TextField("الرسوم بالريال",text:$fee).keyboardType(.decimalPad);Picker("السداد",selection:$payment){Text("غير مسدد").tag("unpaid");Text("مسدد").tag("paid");Text("معفى").tag("waived")};Picker("الحالة",selection:$status){Text("بانتظار التفعيل").tag("pending");Text("مفعّل").tag("active");Text("موقوف").tag("suspended");Text("مرفوض").tag("rejected")};TextField("ملاحظات الإدارة",text:$notes,axis:.vertical)};TaskButton(title:"حفظ التغييرات",symbol:"checkmark"){guard let amount=Double(fee),amount>=0 else{throw FamilyError(text:"تحقق من الرسوم")};_ = try await api.rpc("platform_action",["action":"save","data":["id":family.id,"name":name,"code":code,"status":status,"payment_status":payment,"fee_sar":amount,"notes":notes]]);await saved();dismiss()}}.navigationTitle("إدارة الكيان").toolbar{ToolbarItem(placement:.cancellationAction){Button("إلغاء"){dismiss()}}}.onAppear{name=family.text("name");code=family.text("code");status=family.text("status");payment=family.text("payment_status");fee=family.text("fee_sar");notes=family.text("notes")}}
}
