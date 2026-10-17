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
struct Brand:View {var body:some View{Image("FamilyLogo").resizable().scaledToFit().frame(width:135,height:42).accessibilityLabel("أخبار العائلة")}}
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
            if (gate.hasSession || api.signedIn) && !gate.unlocked{BiometricLockScreen(gate:gate,api:api)}
            else if api.restoring{LaunchScreen(progress:api.startupProgress)}
            else if !api.signedIn{LoginScreen()}
            else{HomeScreen()}
        }.task{await gate.start(api)}
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
        LoadError(text:api.warning);Text("حسابات العائلة محمية. يتطلب التسجيل تأكيد البريد واعتماد الحساب وفق ضوابط المدير.").font(.footnote).foregroundStyle(.secondary)
    }.padding(24).frame(maxWidth:520).frame(maxWidth:.infinity)}.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).navigationTitle("").task{do{kinship=Item.items(try await api.request("/rest/v1/kinship_options?select=*&enabled=eq.true&for_reference=eq.true&order=generation,label",auth:false));if !kinship.contains(where:{$0.text("code")==relationship}){relationship=kinship.first?.text("code") ?? ""}}catch{}}.alert("تغيير كلمة المرور",isPresented:$recoverySent){Button("حسنًا",role:.cancel){}}message:{Text("أرسلنا رابط التحقق إلى بريدك. افتحه لإكمال تغيير كلمة المرور.")}.toolbar{ToolbarItemGroup(placement:.keyboard){Spacer();Button("تم"){field=nil}}}.alert("تأكيد البريد",isPresented:$sent){Button("حسنًا"){signup=false}}message:{Text("أرسلنا رسالة التأكيد. افتح أحدث رسالة، ثم عد إلى التطبيق وسجل الدخول.")}}}
}
struct HomeScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var selection=0
    @State private var chats=false
    @State private var notifications=false
    var body:some View{TabView(selection:$selection){NavigationStack{if api.active{NewsScreen()}else{VStack(spacing:20){Image(systemName:"person.badge.clock").font(.largeTitle);Text(api.profile.text("status")=="suspended" ? "الحساب موقوف مؤقتًا":"حسابك بانتظار الاعتماد").font(.title3);TaskButton(title:"تحديث حالة الحساب",symbol:"arrow.clockwise"){try await api.loadAccount()};NavigationLink("إكمال ملفي"){ProfileScreen()}}.padding()}}.tabItem{Label("الأخبار",systemImage:"house")}.tag(0)
        if api.active{Color.clear.tabItem{Label("الدردشات",systemImage:"bubble.left.and.bubble.right")}.tag(1)}
        NavigationStack{ProfileScreen()}.tabItem{Label("حسابي",systemImage:"person.crop.circle")}.tag(2)
        NavigationStack{MoreScreen()}.tabItem{Label("المزيد",systemImage:"line.3.horizontal")}.tag(3)
    }.onReceive(NotificationCenter.default.publisher(for:.openFamilyNotifications)){_ in if api.active{chats=false;notifications=true}}.sheet(isPresented:$notifications){NavigationStack{NotificationsScreen()}}.onChange(of:selection){_,value in if value==1{selection=0;chats=true}}.fullScreenCover(isPresented:$chats){NavigationStack{ChatsScreen()}.environmentObject(api)} }
}

struct LaunchScreen:View {
    let progress:Double
    @Environment(\.accessibilityReduceMotion)private var reduceMotion
    @State private var animate=false
    var body:some View {
        ZStack{Color(.systemBackground).ignoresSafeArea();VStack(spacing:28){
            ZStack{Circle().stroke(brandBlue.opacity(0.08),lineWidth:1).frame(width:200,height:200);Circle().trim(from:0,to:0.68).stroke(AngularGradient(colors:[brandBlue,brandPink,brandBlue.opacity(0.1)],center:.center),style:StrokeStyle(lineWidth:3,lineCap:.round)).frame(width:200,height:200).rotationEffect(.degrees(animate && !reduceMotion ? 360:0));Image("AppIconPreview").resizable().scaledToFit().frame(width:120,height:120).scaleEffect(animate && !reduceMotion ? 1.045:0.96)}
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
        hasSession=true;guard !unlocked,!busy else{return}
        let probe=LAContext();var error:NSError?;let available=probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,error:&error);describe(probe)
        if !available{unlocked=true;message="";return} // The password has just been verified by the server.
        await open(api)
    }
    func open(_ api:Backend,automatic:Bool=true)async {
        guard !starting,!busy,!unlocked,hasSession || api.signedIn,!(automatic && automaticAttempted) else{return}
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
