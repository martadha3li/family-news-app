import SwiftUI
import PhotosUI
import UIKit

@main struct FamilyNewsApp: App {
    @StateObject private var api=Backend()
    var body:some Scene {WindowGroup {RootScreen().environmentObject(api).environment(\.layoutDirection,.rightToLeft).environment(\.locale,Locale(identifier:"ar_SA")).tint(brandBlue)}}
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
    @Environment(\.scenePhase) private var phase
    var body:some View{Group{if api.restoring{ProgressView("جاري فتح أخبار العائلة…")}else if !api.signedIn{LoginScreen()}else{HomeScreen()}}.task{await api.restore()}.onChange(of:phase){value in if value == .active,api.signedIn{Task{do{try await api.loadAccount()}catch{api.warning=api.errorText(error)}}}}}
}
struct LoginScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var email=""
    @State private var password=""
    @State private var signup=false
    @State private var full="",mobile="",gender="male",reference="",relationship="father",sponsor=""
    @State private var sent=false
    @FocusState private var field:Int?
    var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading,spacing:22){Brand().frame(maxWidth:.infinity).padding(.top,30);VStack(alignment:.leading,spacing:8){Text(signup ? "مكانك بيننا":"أهلًا بعودتك").font(.largeTitle.bold());Text("أخبار العائلة ومناسباتها… أقرب إليك.").foregroundStyle(.secondary)};Picker("نوع الدخول",selection:$signup){Text("تسجيل الدخول").tag(false);Text("حساب جديد").tag(true)}.pickerStyle(.segmented)
        VStack(spacing:16){TextField("البريد الإلكتروني",text:$email).keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($field,equals:0).submitLabel(.next).onSubmit{field=1};SecureField("كلمة المرور",text:$password).textContentType(signup ? .newPassword:.password).focused($field,equals:1).submitLabel(.go)}.textFieldStyle(.roundedBorder)
        if signup{Group{TextField("الاسم الرباعي",text:$full).textContentType(.name);TextField("رقم الجوال",text:$mobile).keyboardType(.phonePad);Picker("الجنس",selection:$gender){Text("ذكر").tag("male");Text("أنثى").tag("female")};if gender=="female"{TextField("اسم المعرّف من العائلة (رباعي)",text:$reference);Picker("صلة القرابة",selection:$relationship){Text("أب").tag("father");Text("زوج").tag("husband");Text("أخ").tag("brother");Text("عم").tag("uncle");Text("خال").tag("maternal_uncle")}};TextField("اسم المعرّف أو جواله (اختياري)",text:$sponsor)}.textFieldStyle(.roundedBorder)}
        TaskButton(title:signup ? "إنشاء حساب":"تسجيل الدخول",symbol:"arrow.left"){field=nil;if signup{guard full.split(whereSeparator:{$0.isWhitespace}).count==4 else{throw FamilyError(text:"أدخل الاسم الرباعي.")};if gender=="female" && reference.trimmingCharacters(in:.whitespaces).isEmpty{throw FamilyError(text:"أدخل اسم المعرّف.")};try await api.signup(email:email,password:password,details:["display_name":full,"full_name":full,"phone":try phone(mobile),"gender":gender,"reference_name":gender=="female" ? reference:"","relationship":gender=="female" ? relationship:"","sponsor_hint":sponsor]);sent=true;password=""}else{try await api.login(email:email,password:password);password=""}}.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth:.infinity)
        LoadError(text:api.warning);Text("حسابات العائلة محمية. يتطلب التسجيل تأكيد البريد واعتماد الحساب وفق ضوابط المدير.").font(.footnote).foregroundStyle(.secondary)
    }.padding(24).frame(maxWidth:520).frame(maxWidth:.infinity)}.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).navigationTitle("").toolbar{ToolbarItemGroup(placement:.keyboard){Spacer();Button("تم"){field=nil}}}.alert("تأكيد البريد",isPresented:$sent){Button("حسنًا"){signup=false}}message:{Text("أرسلنا رسالة التأكيد. افتح أحدث رسالة، ثم عد إلى التطبيق وسجل الدخول.")}}}
}
struct HomeScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var selection=0
    @State private var chats=false
    var body:some View{TabView(selection:$selection){NavigationStack{if api.active{NewsScreen()}else{VStack(spacing:20){Image(systemName:"person.badge.clock").font(.largeTitle);Text(api.profile.text("status")=="suspended" ? "الحساب موقوف مؤقتًا":"حسابك بانتظار الاعتماد").font(.title3);TaskButton(title:"تحديث حالة الحساب",symbol:"arrow.clockwise"){try await api.loadAccount()};NavigationLink("إكمال ملفي"){ProfileScreen()}}.padding()}}.tabItem{Label("الأخبار",systemImage:"house")}.tag(0)
        Color.clear.tabItem{Label("الدردشات",systemImage:"bubble.left.and.bubble.right")}.tag(1)
        NavigationStack{ProfileScreen()}.tabItem{Label("حسابي",systemImage:"person.crop.circle")}.tag(2)
        NavigationStack{MoreScreen()}.tabItem{Label("المزيد",systemImage:"line.3.horizontal")}.tag(3)
    }.onChange(of:selection){value in if value==1{selection=0;chats=true}}.fullScreenCover(isPresented:$chats){NavigationStack{ChatsScreen()}.environmentObject(api)} }
}
