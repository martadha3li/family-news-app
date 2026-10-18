import SwiftUI
import PhotosUI
import UIKit
import LocalAuthentication

@main struct FamilyNewsApp: App {
    @StateObject private var api=Backend()
    @StateObject private var alerts=NativeNotifications()
    var body:some Scene {WindowGroup {RootScreen().onAppear{FamilyTheme.update(api.family)}.environmentObject(api).environmentObject(alerts).environment(\.layoutDirection,.rightToLeft).environment(\.locale,Locale(identifier:"ar_SA")).tint(brandBlue)}}
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
struct Brand:View {@EnvironmentObject private var api:Backend;var body:some View{HStack{if let image=tenantLogo(api.family){Image(uiImage:image).resizable().scaledToFit().frame(width:48,height:42);Text(api.family.text("name")).font(.headline).lineLimit(1)}else if api.family.text("code")=="01"{Image("FamilyLogo").resizable().scaledToFit().frame(width:135,height:42)}else{Image("PlatformLogo").resizable().scaledToFit().frame(width:42,height:42);Text(api.family.text("name").isEmpty ? "منصة العوائل":api.family.text("name")).font(.headline)}}.accessibilityLabel(api.family.text("name").isEmpty ? "أخبار العائلة":api.family.text("name"))}}
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
        }.task(id:api.family.id){api.syncFamilyIcon();if api.family.id.isEmpty{api.restoring=false}else{await gate.start(api)}}
        .task(id:String(api.active)+String(gate.unlocked)+String(describing:phase)){
            guard api.active,gate.unlocked,phase == .active else{return};await alerts.updatePermission()
            while !Task.isCancelled && api.active && gate.unlocked && phase == .active{await api.checkFamilyAccess();guard api.active else{break};await alerts.refresh(api);do{try await Task.sleep(nanoseconds:15_000_000_000)}catch{break}}
        }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.willResignActiveNotification)){_ in PrivacyShield.show()}
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didBecomeActiveNotification)){_ in PrivacyShield.hide()}
        .onChange(of:api.signedIn){_,value in if value{Task{await gate.afterPasswordLogin(api)}}else{alerts.reset();gate.signedOut()}}
        .onChange(of:api.active){_,value in if !value{alerts.reset()}}
        .onChange(of:phase){_,value in
            if value == .background{gate.lock();alerts.visibleThread=""}
            if value == .active{api.syncFamilyIcon();Task{await gate.open(api)}}
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
    }.safeAreaInset(edge:.top){if api.readOnly || api.family.flag("trial"){Text(lifecycleDescription(api.family)).font(.footnote).padding(8).frame(maxWidth:.infinity).background(Color.orange.opacity(0.15))}}.task(id:api.active){
        guard api.active,!api.readOnly,!checkedCampaign else{return};checkedCampaign=true
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
            ZStack{Circle().stroke(brandBlue.opacity(0.08),lineWidth:1).frame(width:200,height:200);Circle().trim(from:0,to:0.68).stroke(AngularGradient(colors:[brandBlue,brandPink,brandBlue.opacity(0.1)],center:.center),style:StrokeStyle(lineWidth:3,lineCap:.round)).frame(width:200,height:200).rotationEffect(.degrees(animate && !reduceMotion ? 360:0));Group{if let logo=tenantLogo(api.family){Image(uiImage:logo).resizable().scaledToFit()}else{Image(api.family.text("code")=="01" ? "Family01Preview":"AppIconPreview").resizable().scaledToFit()}}.frame(width:120,height:120).scaleEffect(animate && !reduceMotion ? 1.045:0.96)}
            Brand();VStack(spacing:10){ProgressView(value:progress).tint(brandBlue).frame(width:180);Text("\(Int(progress*100))٪").font(.system(size:20,weight:.semibold,design:.rounded)).monospacedDigit();Text("جاري تهيئة "+(api.family.text("name").isEmpty ? "منصة العوائل":api.family.text("name"))).font(.footnote).foregroundStyle(.secondary)}
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
    @State private var showFamilies=true
    @State private var loadingDirectory=true
    var body:some View{NavigationStack{List{
        Section{Brand().frame(maxWidth:.infinity).padding(.vertical,12);Text("اختر عائلتك مرة واحدة. يُحفظ الاختيار على هذا الجهاز، ويمكن تغييره لاحقًا.").font(.subheadline);TextField("كود العائلة أو اسمها",text:$term).textInputAutocapitalization(.never);LoadError(text:error)}
        Section{DisclosureGroup("العوائل المتاحة",isExpanded:$showFamilies){ForEach(families){family in Button{selected=family}label:{HStack(spacing:12){Group{if let image=tenantLogo(family){Image(uiImage:image).resizable().scaledToFit()}else{Image(family.text("code")=="01" ? "Family01Preview":"PlatformLogo").resizable().scaledToFit()}}.frame(width:48,height:48);VStack(alignment:.leading){Text(family.text("name")).font(.headline);Text("الكود "+family.text("code")).font(.caption)}}}}}}
        Section{Button("تسجيل عائلة جديدة"){request=true};Button("دخول إدارة المنصة"){platform=true}}
    }.navigationTitle("أهلًا بك").overlay{if loadingDirectory{LaunchScreen(progress:0.35)}}.task(id:term){defer{if !Task.isCancelled{loadingDirectory=false}};do{try await Task.sleep(nanoseconds:220_000_000);let rows=Item.items(try await api.request("/rest/v1/rpc/tenant_directory",method:"POST",body:["term":term],auth:false));try Task.checkCancellation();families=rows;error=""}catch{if !Task.isCancelled{self.error=api.errorText(error)}}}
    .confirmationDialog(selected?.text("name") ?? "",isPresented:Binding(get:{selected != nil},set:{if !$0{selected=nil}}),titleVisibility:.visible){Button("تأكيد الدخول وحفظ الكيان"){if let family=selected{Task{if api.signedIn{await api.logout()};api.selectFamily(family);selected=nil}}}}message:{Text("ستفتح واجهة هذه العائلة باسمها وشعارها مباشرة في المرات القادمة. "+(selected?.text("code")=="01" ? "ستتغير أيقونة التطبيق إلى شعار العائلة على الشاشة الرئيسية. يبقى اسم التطبيق العوائل وفق قيود الآيفون.":"تغيير أيقونة الشاشة الرئيسية لهذا الكيان يحتاج تحديثًا يتضمن شعاره. يبقى اسم التطبيق العوائل وفق قيود الآيفون."))}
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
    @State private var resultMessage=""
    @State private var error=""
    func submit()async throws {
        guard let image=logo else{throw FamilyError(text:"اختر شعار العائلة")}
        let scale=min(1,512/max(image.size.width,image.size.height))
        let size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
        let rendered=UIGraphicsImageRenderer(size:size,format:format).image{ctx in UIColor.white.setFill();ctx.fill(CGRect(origin:.zero,size:size));image.draw(in:CGRect(origin:.zero,size:size))}
        guard let bytes=rendered.jpegData(compressionQuality:0.72),bytes.count<=200000 else{throw FamilyError(text:"اختر شعارًا أصغر")}
        let data:[String:Any]=["name":name,"phone":try phone(phoneText),"email":email,"logo":"data:image/jpeg;base64,"+bytes.base64EncodedString()]
        let result=try await api.request("/rest/v1/rpc/tenant_request",method:"POST",body:["data":data],auth:false)
        resultMessage=result as? String ?? "تم إنشاء التجربة المجانية";sent=true
    }
    func loadPhoto(_ item:PhotosPickerItem?)async{do{guard let data=try await item?.loadTransferable(type:Data.self),data.count<=20*1024*1024,let image=UIImage(data:data)else{throw FamilyError(text:"اختر صورة صالحة أقل من 20 ميجابايت")};logo=image;error=""}catch{self.error=api.errorText(error)}}
    var fields:some View{Section("كيان عائلي جديد"){TextField("اسم العائلة",text:$name);TextField("رقم التواصل",text:$phoneText).keyboardType(.phonePad);TextField("البريد الإلكتروني",text:$email).keyboardType(.emailAddress).textInputAutocapitalization(.never);PhotosPicker(selection:$photo,matching:.images){Label("شعار العائلة",systemImage:"photo")};if let image=logo{Image(uiImage:image).resizable().scaledToFit().frame(height:140)};Text("تجربة مجانية لمدة 30 يومًا دون انتظار تفعيل. بعد انتهائها يتوقف الإضافة والدردشة، وبعد 30 يومًا إضافية دون اشتراك يحذف الكيان وصوره وبياناته نهائيًا. أكّد بريدك لتصبح المدير.").font(.footnote)}}
    var body:some View{Form{fields;LoadError(text:error);TaskButton(title:"بدء التجربة المجانية",symbol:"paperplane"){try await submit()}}.navigationTitle("تسجيل عائلة").toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){dismiss()}}}.onChange(of:photo){_,item in Task{await loadPhoto(item)}}.alert("تم إنشاء عائلتك",isPresented:$sent){Button("حسنًا"){dismiss()}}message:{Text(resultMessage)}}
}
struct TenantPlatformLogin:View {
    @StateObject private var portal=Backend()
    @Environment(\.dismiss)private var dismiss
    @Environment(\.scenePhase)private var phase
    @State private var username="admin"
    @State private var password=""
    @State private var authorized=false
    var body:some View{NavigationStack{Group{if authorized{PlatformDashboard().environmentObject(portal)}else{Form{Text("إدارة المنصة للمالك المتحقق منه. استخدم كلمة مرور حسابك الحالية.").font(.footnote);TextField("اسم الدخول أو البريد",text:$username).textInputAutocapitalization(.never);SecureField("كلمة المرور",text:$password);TaskButton(title:"دخول الإدارة",symbol:"lock.shield"){try await portal.platformLogin(username:username,password:password);password="";authorized=true}}.environmentObject(portal).navigationTitle("إدارة المنصة")}}.toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){portal.clearSession();dismiss()}}}}.onChange(of:phase){_,value in if value == .background{portal.clearSession();dismiss()}}}
}
struct TenantPlatformList:View {
    @EnvironmentObject private var api:Backend
    @State private var tenants:[Item]=[]
    @State private var error=""
    @State private var edit:Item?
    func load()async{do{tenants=Item.items(try await api.rpc("platform_action",["action":"list"]));error=""}catch{self.error=api.errorText(error)}}
    var body:some View{List{Section{Text("تسجيل الرسوم والسداد يدويًا، ثم تفعيل الكيان. لا توجد بوابة دفع مفعّلة.").font(.footnote)};LoadError(text:error);ForEach(tenants){family in Button{edit=family}label:{VStack(alignment:.leading,spacing:7){Text(family.text("name")).font(.headline);Text("الكود "+family.text("code")+" · "+family.text("status")).font(.caption);Text("\(family.number("members")) عضو · \(family.number("posts")) خبر").font(.caption);Text(subscriptionSummary(family)).font(.caption).foregroundStyle(.secondary)}}}}.navigationTitle("الكيانات العائلية").task{await load()}.refreshable{await load()}.sheet(item:$edit){family in NavigationStack{TenantPlatformEditor(family:family){await load()}}}}
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
    var body:some View{Form{Section("بيانات الكيان"){TextField("اسم العائلة",text:$name);TextField("الكود",text:$code).textInputAutocapitalization(.never);Text(family.text("contact_email"));Text(family.text("contact_phone"))};Section("السداد والتفعيل"){Picker("السداد",selection:$payment){Text("غير مسدد").tag("unpaid");Text("مسدد").tag("paid");Text("معفى").tag("waived")};Picker("الحالة",selection:$status){Text("بانتظار التفعيل").tag("pending");Text("مفعّل").tag("active");Text("موقوف").tag("suspended");Text("مرفوض").tag("rejected")};TextField("ملاحظات الإدارة",text:$notes,axis:.vertical)};Section("الاشتراك"){Text(lifecycleDescription(family));if family.text("payment_status")=="unpaid" && family.text("trial_started_at").isEmpty && family.text("subscription_ends_at").isEmpty{NavigationLink("منح تجربة مجانية 30 يومًا"){PlatformTrialScreen(family:family)}};NavigationLink("فترة الاشتراك والتجديد"){TenantPlanScreen(family:family)};NavigationLink("الاستهلاك والدخول والصيانة"){TenantOperationsScreen(family:family)}};TaskButton(title:"حفظ التغييرات",symbol:"checkmark"){guard let amount=Double(fee),amount>=0 else{throw FamilyError(text:"تحقق من الرسوم")};_ = try await api.rpc("platform_action",["action":"save","data":["id":family.id,"name":name,"code":code,"status":status,"payment_status":payment,"fee_sar":amount,"notes":notes]]);await saved();dismiss()}}.navigationTitle("إدارة الكيان").toolbar{ToolbarItem(placement:.cancellationAction){Button("إلغاء"){dismiss()}}}.onAppear{name=family.text("name");code=family.text("code");status=family.text("status");payment=family.text("payment_status");fee=family.text("fee_sar");notes=family.text("notes")}}
}

let subscriptionPlans:[(String,String)]=[("12","سنة"),("24","سنتان"),("36","٣ سنوات"),("6","٦ أشهر")]
func subscriptionDuration(_ start:Date,_ end:Date)->String {
    guard end>start else{return "انتهى الاشتراك"}
    var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(identifier:"Asia/Riyadh")!
    var months=(cal.component(.year,from:end)-cal.component(.year,from:start))*12+cal.component(.month,from:end)-cal.component(.month,from:start)
    while cal.date(byAdding:.month,value:months,to:start)!>end{months -= 1}
    let cursor=cal.date(byAdding:.month,value:months,to:start)!
    let c=cal.dateComponents([.day,.hour,.minute],from:cursor,to:end)
    let days=c.day ?? 0
    let parts:[(Int,String)]=[(months/12,"سنة"),(months%12,"شهر"),(days/7,"أسبوع"),(days%7,"يوم"),(c.hour ?? 0,"ساعة"),(c.minute ?? 0,"دقيقة")]
    let text=parts.filter{$0.0>0}.map{String($0.0)+" "+$0.1}.joined(separator:" و ")
    return text.isEmpty ? "أقل من دقيقة":text
}
func subscriptionSummary(_ family:Item,now:Date=Date())->String {
    guard !family.text("subscription_ends_at").isEmpty else{return "لم تحدد فترة اشتراك"}
    let start=dateValue(family.text("subscription_starts_at")),end=dateValue(family.text("subscription_ends_at"))
    if now<start{return "يبدأ لاحقًا · "+subscriptionDuration(start,end)}
    return now>=end ? "انتهى الاشتراك":"المتبقي "+subscriptionDuration(now,end)
}
struct TenantSubscriptionEditor:View {
    @EnvironmentObject private var api:Backend
    let family:Item
    let saved:()async->Void
    @State private var record=Item()
    @State private var enabled=false
    @State private var start=Date()
    @State private var end=Date()
    @State private var prices:[String:String]=[:]
    @State private var plan="12"
    @State private var payment="paid"
    @State private var confirm=false
    @State private var requestID=UUID().uuidString
    @State private var error=""
    @State private var renewing=false
    func display(_ item:Item){record=item;enabled = !item.text("subscription_ends_at").isEmpty;start=enabled ? dateValue(item.text("subscription_starts_at")):Date();end=enabled ? dateValue(item.text("subscription_ends_at")):Calendar(identifier:.gregorian).date(byAdding:.year,value:1,to:start)!;for(key,_)in subscriptionPlans{prices[key]=item.child("renewal_prices").text(key)}}
    func refresh()async throws{let rows=Item.items(try await api.rpc("platform_action",["action":"list"]));if let row=rows.first(where:{$0.id==family.id}){display(row)};await saved()}
    var priceText:String{record.child("renewal_prices").text(plan)}
    var confirmationText:String {
        let label=subscriptionPlans.first{$0.0==plan}?.1 ?? ""
        let amount=payment=="waived" ? "إعفاء من الرسوم":priceText+" ر.س مسددة يدويًا"
        return family.text("name")+" · "+label+" · "+amount
    }
    func priceLabel(_ key:String,_ label:String)->String {
        let amount=record.child("renewal_prices").text(key)
        return label+" · "+(amount.isEmpty ? "لم يحدد السعر":amount+" ر.س")
    }
    func savePeriod()async throws {
        guard !enabled || end>start else{throw FamilyError(text:"يجب أن تكون النهاية بعد البداية")}
        var amounts:[String:Double]=[:]
        for(key,_)in subscriptionPlans{
            let text=(prices[key] ?? "").trimmingCharacters(in:.whitespaces)
            if !text.isEmpty{
                guard let value=Double(text),value.isFinite,value>=0,value<=99999999.99,abs(value*100-(value*100).rounded())<0.00001 else{throw FamilyError(text:"تحقق من أسعار الباقات")}
                amounts[key]=value
            }
        }
        let formatter=ISO8601DateFormatter()
        var data:[String:Any]=["id":family.id,"renewal_prices":amounts]
        data["subscription_starts_at"]=enabled ? formatter.string(from:start) as Any:NSNull()
        data["subscription_ends_at"]=enabled ? formatter.string(from:end) as Any:NSNull()
        _ = try await api.rpc("platform_action",["action":"subscription_save","data":data])
        try await refresh()
    }
    func renew()async {
        renewing=true;defer{renewing=false}
        do{
            let data:[String:Any]=["id":family.id,"months":Int(plan) ?? 0,"payment_status":payment,"request_id":requestID]
            _ = try await api.rpc("platform_action",["action":"renew","data":data])
            requestID=UUID().uuidString;try await refresh();error=""
        }catch{self.error=api.errorText(error)}
    }
    var periodSection:some View {
        Section("فترة الاشتراك"){
            TimelineView(.periodic(from:.now,by:60)){context in Text(subscriptionSummary(record,now:context.date))}
            Toggle("تحديد فترة الاشتراك",isOn:$enabled)
            if enabled{
                DatePicker("من",selection:$start,displayedComponents:[.date,.hourAndMinute])
                DatePicker("إلى",selection:$end,displayedComponents:[.date,.hourAndMinute])
                Text(subscriptionDuration(start,end)).font(.footnote)
            }
            Text("التواريخ بتوقيت الرياض. بعد نهاية الاشتراك يصبح الكيان للاطلاع فقط، ويبقى إيقاف الدخول قرارًا منفصلًا.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    var pricingSection:some View {
        Section("أسعار التجديد بالريال"){
            ForEach(subscriptionPlans,id:\.0){key,label in
                TextField(label,text:Binding(get:{prices[key] ?? ""},set:{prices[key]=$0})).keyboardType(.decimalPad)
            }
            TaskButton(title:"حفظ الفترة والأسعار",symbol:"checkmark"){try await savePeriod()}
        }
    }
    var renewalSection:some View {
        Section("تجديد الاشتراك"){
            Picker("الباقة",selection:$plan){ForEach(subscriptionPlans,id:\.0){key,label in Text(priceLabel(key,label)).tag(key)}}
            Picker("السداد",selection:$payment){Text("تم السداد يدويًا").tag("paid");Text("إعفاء من الرسوم").tag("waived")}
            Text("التجديد يضاف إلى نهاية الاشتراك الساري، أو يبدأ الآن إذا انتهى. لا يجري تحصيل إلكتروني.").font(.footnote)
            Button(renewing ? "جاري التجديد…":"تأكيد وتجديد الاشتراك"){confirm=true}.disabled(priceText.isEmpty || renewing)
            LoadError(text:error)
        }
    }
    var body:some View {
        Form{periodSection;pricingSection;renewalSection}
        .navigationTitle("الاشتراك والتجديد")
        .environment(\.timeZone,TimeZone(identifier:"Asia/Riyadh")!)
        .onAppear{display(family)}
        .task{do{try await refresh()}catch{self.error=api.errorText(error)}}
        .confirmationDialog("تأكيد التجديد",isPresented:$confirm,titleVisibility:.visible){Button("تنفيذ التجديد"){Task{await renew()}}}message:{Text(confirmationText)}
    }
}

func usageBytes(_ value:Int)->String{ByteCountFormatter.string(fromByteCount:Int64(value),countStyle:.file)}
struct TenantOperationsScreen:View {
    @EnvironmentObject private var api:Backend
    let family:Item
    @State private var record=Item()
    @State private var operations=Item()
    @State private var usage=Item()
    @State private var trusted=true
    @State private var kinship=true
    @State private var relations:[String:Bool]=[:]
    @State private var until=Date().addingTimeInterval(86400)
    @State private var reason=""
    @State private var error=""
    @State private var mode=""
    @State private var confirm=false
    @State private var preview:Item?
    func rpc(_ action:String,_ extra:[String:Any]=[:])async throws->Any{try await api.rpc("platform_action",["action":action,"data":extra.merging(["id":family.id]){_,new in new}])}
    func load()async{do{record=Item.items(try await api.rpc("platform_action",["action":"list"])).first{$0.id==family.id} ?? family;operations=Item(try await rpc("operations")as? [String:Any] ?? [:]);usage=Item(try await rpc("usage")as? [String:Any] ?? [:]);trusted=operations.flag("trusted");kinship=operations.flag("kinship");for r in operations.rows("relations"){relations[r.text("code")]=r.flag("allowed")};error=""}catch{self.error=api.errorText(error)}}
    var accessSection:some View {
        Section("الدخول والاشتراك"){
            Text(subscriptionSummary(record));Text("حالة الدخول: "+record.text("login_access"))
            DatePicker("نهاية التعليق · الرياض",selection:$until,in:Date()...,displayedComponents:[.date,.hourAndMinute])
            Button{mode="suspended";confirm=true}label:{Label("تعليق الدخول مؤقتًا",systemImage:"pause.circle")}
            Button(role:.destructive){mode="blocked";confirm=true}label:{Label("إيقاف الدخول حتى إعادة فتحه",systemImage:"hand.raised")}
            Button{mode="allowed";confirm=true}label:{Label("إتاحة الدخول",systemImage:"play.circle")}
        }
    }
    var usageSection:some View {
        Section("استهلاك الكيان"){
            LabeledContent("السجلات · تقدير",value:usageBytes(usage.number("row_bytes_estimate")))
            LabeledContent("الصور والملفات",value:usageBytes(usage.number("file_bytes")))
            Text("\(usage.number("users")) عضو · \(usage.number("news")) خبر · \(usage.number("messages")) رسالة · \(usage.number("groups")) مجموعة")
            Text("تقدير السجلات لا يشمل تخصيص الفهارس والمساحة المشتركة. حدود الاستضافة مشتركة بين الكيانات.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    var policySection:some View {
        Section("استثناءات الخاص"){
            Toggle("التعريف المقبول",isOn:$trusted);Toggle("القرابة المؤكدة",isOn:$kinship)
            ForEach(operations.rows("relations"),id:\.rawCode){r in Toggle(r.text("label"),isOn:Binding(get:{relations[r.text("code")] ?? false},set:{relations[r.text("code")]=$0}))}
            TaskButton(title:"حفظ ضوابط التواصل",symbol:"checkmark"){_ = try await rpc("chat_policy",["trusted":trusted,"kinship":kinship,"relations":relations.filter{$0.value}.map{$0.key}]);await load()}
        }
    }
    var maintenanceSection:some View {
        Section("دخول الصيانة بموافقة مدير الكيان"){
            Text("تصريح صيانة يتيح إدارة الأعضاء والإعدادات والأخبار، لمدة يحددها مدير العائلة بالساعات. لا يشمل قراءة الرسائل الخاصة.").font(.footnote)
            TextField("سبب طلب الصيانة",text:$reason,axis:.vertical)
            TaskButton(title:"إرسال طلب موافقة",symbol:"wrench.and.screwdriver"){_ = try await rpc("maintenance_request",["reason":reason]);reason="";await load()}
            ForEach(operations.rows("maintenance")){r in VStack(alignment:.leading,spacing:8){Text(r.text("reason"));Text(r.text("status")).font(.caption).foregroundStyle(.secondary);if r.text("status")=="approved" && dateValue(r.text("expires_at"))>Date(){Button("دخول الصيانة المصرّح"){preview=r}}}}
        }
    }
    var body:some View {
        Form{LoadError(text:error);accessSection;usageSection;policySection;maintenanceSection}.navigationTitle(family.text("name")).environment(\.timeZone,TimeZone(identifier:"Asia/Riyadh")!).task{await load()}.refreshable{await load()}.confirmationDialog("تأكيد تغيير الدخول",isPresented:$confirm,titleVisibility:.visible){Button("تأكيد"){
            Task{do{var data:[String:Any]=["mode":mode];if mode=="suspended"{data["until"]=ISO8601DateFormatter().string(from:until)};_ = try await rpc("login_access",data);await load()}catch{self.error=api.errorText(error)}}
        }}message:{Text(mode=="allowed" ? "إعادة إتاحة دخول أعضاء الكيان؟":"سيمنع دخول أعضاء هذا الكيان، مع حفظ البيانات.")}.sheet(item:$preview){r in NavigationStack{FamilyAdminDashboard(maintenance:r.id)}}
    }
}
struct FamilyMaintenanceScreen:View {
    @State private var hours=2
    @EnvironmentObject private var api:Backend
    @State private var rows:[Item]=[]
    @State private var error=""
    @State private var selected:Item?
    @State private var action=""
    func load()async{do{rows=Item.items(try await api.action("maintenance_action","list"));error=""}catch{self.error=api.errorText(error)}}
    func choose(_ r:Item,_ operation:String){selected=r;action=operation}
    var body:some View {
        List{Stepper("مدة التصريح: \(hours) ساعة",value:$hours,in:1...72);Text("حدد مدة الصيانة من ساعة إلى 72 ساعة. يتيح التصريح إدارة الأعضاء والإعدادات والأخبار دون الرسائل الخاصة، ويمكن إلغاؤه فورًا.").font(.footnote);LoadError(text:error);ForEach(rows){r in VStack(alignment:.leading,spacing:10){Text(r.text("reason")).font(.headline);Text(r.text("status")).font(.caption);if !r.text("expires_at").isEmpty{Text("ينتهي: "+dateValue(r.text("expires_at")).formatted())};if r.text("status")=="pending"{Button("موافقة بالمدة المحددة"){choose(r,"approve")};Button("رفض",role:.destructive){choose(r,"reject")}}else if r.text("status")=="approved"{Button("إلغاء تصريح الصيانة",role:.destructive){choose(r,"revoke")}}}}}.navigationTitle("طلبات صيانة المنصة").task{await load()}.refreshable{await load()}.confirmationDialog("تأكيد قرار الصيانة",isPresented:Binding(get:{selected != nil},set:{if !$0{selected=nil}}),titleVisibility:.visible){Button("تأكيد"){guard let r=selected else{return};selected=nil;Task{do{_ = try await api.action("maintenance_action",action,["id":r.id,"hours":hours]);await load()}catch{self.error=api.errorText(error)}}}}message:{Text(action=="approve" ? "أوافق على دخول إدارة المنصة إلى لوحة صيانة عائلتي للمدة المحددة، دون قراءة الرسائل الخاصة.":"تأكيد رفض الطلب أو إلغاء التصريح؟")}
    }
}
struct MaintenancePreviewScreen:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss)private var dismiss
    @Environment(\.scenePhase)private var phase
    let family:Item
    let request:Item
    @State private var data=Item()
    @State private var error=""
    var body:some View {
        List{Text(data.text("scope")).font(.footnote);LoadError(text:error);if !data.text("expires_at").isEmpty{Text("ينتهي التصريح: "+dateValue(data.text("expires_at")).formatted())};Section("الأخبار · قراءة فقط"){ForEach(data.rows("news")){p in VStack(alignment:.leading,spacing:8){Text(p.text("title")).font(.headline);Text(p.text("body"))}}};Section("تشخيص الإعدادات"){ForEach([("chat_enabled","الدردشة"),("private_chat_enabled","الخاص"),("restrict_gender_chat","فصل الجنسين"),("journalist_approval","موافقة نشر الصحفي")],id:\.0){key,label in LabeledContent(label,value:data.child("settings").flag(key) ? "مفعّل":"معطّل")}}}.navigationTitle("صيانة "+family.text("name")).toolbar{ToolbarItem(placement:.cancellationAction){Button("خروج"){data=Item();dismiss()}}}.task(id:phase){guard phase == .active else{data=Item();return};while !Task.isCancelled{do{data=Item(try await api.rpc("platform_action",["action":"maintenance_open","data":["id":family.id,"request":request.id]])as? [String:Any] ?? [:]);error="";try await Task.sleep(nanoseconds:15_000_000_000)}catch{data=Item();if !Task.isCancelled{self.error=api.errorText(error)};break}}}.privacySensitive()
    }
}

let billingUnits=[("year","سنة"),("month","شهر"),("week","أسبوع"),("day","يوم")]
func billingPeriod(_ i:Item)->String{String(i.number("duration_count"))+" "+(billingUnits.first{$0.0==i.text("duration_unit")}?.1 ?? "")}
func invoiceMessage(_ i:Item)->String{["منصة العوائل · مطالبة سداد #"+i.text("number"),"العائلة: "+i.text("tenant_name")+" · "+i.text("tenant_code"),"الباقة: "+i.text("plan_name"),"المدة: "+billingPeriod(i),"الإجمالي: "+i.text("amount_sar")+" ريال سعودي","المدة تبدأ بعد السداد أو نهاية الاشتراك الساري.","هذه مطالبة سداد وليست فاتورة ضريبية."].joined(separator:"\n")}
func invoiceShareURL(_ i:Item,whatsapp:Bool)->URL? {
    let text=invoiceMessage(i).addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? ""
    if whatsapp{guard let mobile=try? phone(i.text("contact_phone"))else{return nil};return URL(string:"https://wa.me/"+mobile.replacingOccurrences(of:"+",with:"")+"?text="+text)}
    let email=i.text("contact_email");guard email.contains("@"),!email.contains("\n"),!email.contains("\r")else{return nil}
    let safe=email.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? ""
    return URL(string:"mailto:"+safe+"?subject="+("مطالبة اشتراك "+i.text("number")).addingPercentEncoding(withAllowedCharacters:.alphanumerics)!+"&body="+text)
}
struct PlatformDashboard:View {
    var body:some View{List{Section("إدارة المنصة المستقلة"){NavigationLink("الكيانات العائلية"){TenantPlatformList()};NavigationLink("الباقات والاشتراكات"){BillingPlansScreen()};NavigationLink("الفواتير ومطالبات السداد"){BillingInvoicesScreen(tenant:nil)};NavigationLink("المهل والبريد والحذف التلقائي"){PlatformLifecycleScreen()}}}.navigationTitle("إدارة المنصة")}
}
struct BillingPlansScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var rows:[Item]=[]
    @State private var error=""
    @State private var edit:Item?
    func load()async{do{rows=Item.items(try await api.rpc("platform_action",["action":"plans"]));error=""}catch{self.error=api.errorText(error)}}
    var body:some View{List{Text("حدد المدد والأسعار هنا ثم اختر الباقة في الكيان. المطالبات السابقة تحتفظ بسعرها.").font(.footnote);LoadError(text:error);ForEach(rows){r in Button{edit=r}label:{VStack(alignment:.leading,spacing:6){Text(r.text("name")).font(.headline);Text(billingPeriod(r)+" · "+(r.text("price_sar").isEmpty ? "السعر غير محدد":r.text("price_sar")+" ر.س"));Text(r.flag("enabled") ? "مفعّلة":"معطّلة").font(.caption)}}}}.navigationTitle("الباقات والاشتراكات").toolbar{Button{edit=Item(["id":"new","duration_count":1,"duration_unit":"year"])}label:{Image(systemName:"plus")}}.task{await load()}.sheet(item:$edit){r in NavigationStack{BillingPlanEditor(plan:r){await load()}}}}
}
struct BillingPlanEditor:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss)private var dismiss
    let plan:Item
    let saved:()async->Void
    @State private var name=""
    @State private var count=1
    @State private var unit="year"
    @State private var price=""
    @State private var enabled=false
    var body:some View{Form{TextField("اسم الباقة",text:$name);Stepper("المدة: \(count)",value:$count,in:1...3650);Picker("الوحدة",selection:$unit){ForEach(billingUnits,id:\.0){key,label in Text(label).tag(key)}};TextField("السعر بالريال",text:$price).keyboardType(.decimalPad);Toggle("تفعيل الباقة",isOn:$enabled);TaskButton(title:"حفظ الباقة",symbol:"checkmark"){
        var data:[String:Any]=["name":name,"duration_count":count,"duration_unit":unit,"enabled":enabled]
        if plan.id != "new"{data["id"]=plan.id}
        if price.isEmpty{data["price_sar"]=NSNull()}else{guard let amount=Double(price),amount.isFinite,amount>=0 else{throw FamilyError(text:"تحقق من السعر")};data["price_sar"]=amount}
        _ = try await api.rpc("platform_action",["action":"plan_save","data":data]);await saved();dismiss()
    }}.navigationTitle("تعريف الاشتراك").toolbar{Button("إلغاء"){dismiss()}}.onAppear{name=plan.text("name");count=max(1,plan.number("duration_count"));unit=plan.text("duration_unit");price=plan.text("price_sar");enabled=plan.flag("enabled")}}
}
struct TenantPlanScreen:View {
    @EnvironmentObject private var api:Backend
    let family:Item
    @State private var plans:[Item]=[]
    @State private var selected=""
    @State private var error=""
    @State private var confirm=false
    @State private var requestID=UUID().uuidString
    @State private var showInvoices=false
    func load()async{do{plans=Item.items(try await api.rpc("platform_action",["action":"plans"]));selected=family.text("billing_plan_id")}catch{self.error=api.errorText(error)}}
    var body:some View{Form{Text(subscriptionSummary(family));LoadError(text:error);Picker("الاشتراك",selection:$selected){Text("اختر الباقة").tag("");ForEach(plans.filter{$0.flag("enabled")}){p in Text(p.text("name")+" · "+p.text("price_sar")+" ر.س").tag(p.id)}};Text("التعيين ينشئ مطالبة سداد تلقائيًا. يبدأ التجديد بعد تسجيل استلام السداد، دون تحصيل إلكتروني حاليًا.").font(.footnote);Button("تعيين الباقة وإنشاء المطالبة"){confirm=true}.disabled(selected.isEmpty);NavigationLink("مطالبات الكيان"){BillingInvoicesScreen(tenant:family.id)}}.navigationTitle("اشتراك "+family.text("name")).task{await load()}.confirmationDialog("تأكيد التعيين وإنشاء المطالبة",isPresented:$confirm,titleVisibility:.visible){Button("تأكيد"){Task{do{_ = try await api.rpc("platform_action",["action":"assign_plan","data":["id":family.id,"plan_id":selected,"request_id":requestID]]);requestID=UUID().uuidString;showInvoices=true;error=""}catch{self.error=api.errorText(error)}}}}message:{Text("تُلغى المطالبات السابقة غير المسددة فقط. لا تتغير المدة حتى تسجيل السداد.")}.sheet(isPresented:$showInvoices){NavigationStack{BillingInvoicesScreen(tenant:family.id).toolbar{Button("إغلاق"){showInvoices=false}}}}}
}
struct BillingInvoicesScreen:View {
    @EnvironmentObject private var api:Backend
    let tenant:String?
    @State private var rows:[Item]=[]
    @State private var error=""
    func load()async{do{var data:[String:Any]=[:];if let tenant=tenant{data["id"]=tenant};rows=Item.items(try await api.rpc("platform_action",["action":"invoices","data":data]));error=""}catch{self.error=api.errorText(error)}}
    var body:some View{List{LoadError(text:error);if rows.isEmpty{Text("لا توجد مطالبات سداد")};ForEach(rows){r in InvoiceNativeCard(invoice:r){await load()}}}.navigationTitle("الفواتير والمطالبات").task{await load()}.refreshable{await load()}}
}
struct InvoiceNativeCard:View {
    @EnvironmentObject private var api:Backend
    let invoice:Item
    let changed:()async->Void
    @State private var confirm=false
    @State private var error=""
    var body:some View{VStack(alignment:.leading,spacing:12){Text("مطالبة #"+invoice.text("number")).font(.headline);Text(invoice.text("tenant_name")+" · "+invoice.text("plan_name"));Text(invoice.text("amount_sar")+" ر.س").bold();Text(invoice.text("status")=="paid" ? "مسددة":invoice.text("status")=="void" ? "ملغاة":"بانتظار السداد");Text("مطالبة غير ضريبية. المشاركة تفتح رسالة جاهزة ولا تعني إرسالها.").font(.caption).foregroundStyle(.secondary);if let email=invoiceShareURL(invoice,whatsapp:false){Link("مشاركة بالبريد",destination:email)};if let wa=invoiceShareURL(invoice,whatsapp:true){Link("مشاركة بواتساب",destination:wa)};ShareLink(item:invoiceMessage(invoice)){Label("مشاركة المطالبة",systemImage:"square.and.arrow.up")};if invoice.text("status")=="issued"{Button("تسجيل استلام السداد وتجديد الاشتراك"){confirm=true}};LoadError(text:error)}.padding(.vertical,10).confirmationDialog("هل استلمت السداد فعليًا؟",isPresented:$confirm,titleVisibility:.visible){Button("تأكيد السداد والتجديد"){Task{do{_ = try await api.rpc("platform_action",["action":"invoice_paid","data":["invoice":invoice.id,"confirm":"MANUAL_PAYMENT_RECEIVED"]]);await changed()}catch{self.error=api.errorText(error)}}}}message:{Text(invoice.text("amount_sar")+" ر.س. لا يوجد سحب أو تحصيل إلكتروني مفعّل.")}}
}

struct PlatformLifecycleScreen:View {
 @EnvironmentObject private var api:Backend
 @State private var data=Item()
 @State private var error=""
 func load()async{do{data=Item(try await api.action("platform_lifecycle","status")as? [String:Any] ?? [:]);error=""}catch{self.error=api.errorText(error)}}
 var body:some View{List{LoadError(text:error);Text(data.flag("schedule_active") ? "الفحص التلقائي يعمل كل ساعة":"الفحص التلقائي غير مفعل");Text("رسائل بانتظار الإرسال: \(data.number("pending_mail"))");Text("لا يبدأ حذف الاشتراك المنتهي حتى يرسل بريد التجديد بنجاح ثم تمر 15 يومًا.").font(.footnote);ForEach(data.rows("mail_errors").indices,id:\.self){i in let m=data.rows("mail_errors")[i];Text(m.text("family")+" · "+m.text("error")).font(.caption)};ForEach(data.rows("deletions").indices,id:\.self){i in let j=data.rows("deletions")[i];Text(j.text("family")+" · "+j.text("phase")+" · "+j.text("last_error"))}}.navigationTitle("المهل والبريد والحذف").task{await load()}.refreshable{await load()}}
}
struct PlatformTrialScreen:View {
 @EnvironmentObject private var api:Backend
 let family:Item
 @State private var done=false
 var body:some View{Form{Text(family.text("name")).font(.headline);Text("تجربة مجانية 30 يومًا ثم 30 يومًا للاطلاع. دون اشتراك يحذف الكيان وكل صوره وبياناته نهائيًا.");TaskButton(title:"منح التجربة المجانية",symbol:"calendar.badge.plus"){_ = try await api.action("platform_lifecycle","trial_start",["id":family.id]);done=true}.disabled(done);if done{Text("بدأت التجربة المجانية")}}.navigationTitle("تجربة مجانية")}
}
