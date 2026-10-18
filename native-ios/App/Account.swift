import SwiftUI
import PhotosUI

struct ProfileScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var full=""
    @State private var bio=""
    @State private var mobile=""
    @State private var gender=""
    @State private var reference=""
    @State private var relation=""
    @State private var email=""
    @State private var newPhone=""
    @State private var search=""
    @State private var error=""
    @State private var notice=""
    @State private var options:[Item]=[]
    @State private var referees:[Item]=[]
    @State private var photo:PhotosPickerItem?
    var body:some View{Form{Section{VStack(spacing:10){Avatar(path:api.profile.text("avatar_path"),name:api.profile.text("display_name"),size:88);PhotosPicker(selection:$photo,matching:.images){Label("تغيير صورة العرض",systemImage:"camera")};Text(api.profile.text("display_name")).font(.headline);Text(api.user.text("email")).font(.caption).foregroundStyle(.secondary);Text(api.active ? "عضو معتمد":"بانتظار الاعتماد").font(.caption).foregroundStyle(brandBlue)}.frame(maxWidth:.infinity).padding(.vertical,10)};LoadError(text:error);if !notice.isEmpty{Text(notice).foregroundStyle(brandBlue)}
        Section("نبذة عني · Bio"){TextField("اكتب نبذة قصيرة عنك…",text:$bio,axis:.vertical).lineLimit(3...6);Text("\(bio.count) / 300").font(.caption).foregroundStyle(bio.count>300 ? Color.red:Color.secondary);TaskButton(title:"حفظ النبذة",symbol:"checkmark"){guard bio.count<=300 else{throw FamilyError(text:"النبذة 300 حرف كحد أقصى.")};_ = try await api.action("account_action","bio",["bio":bio]);try await api.loadAccount();notice="حُفظت النبذة."}}
        Section("بياناتي"){TextField("الاسم الرباعي",text:$full);TextField("رقم الجوال",text:$mobile).keyboardType(.phonePad).disabled(!api.profile.text("phone").isEmpty);Picker("الجنس",selection:$gender){Text("اختر").tag("");Text("ذكر").tag("male");Text("أنثى").tag("female")}.disabled(!api.profile.text("gender").isEmpty);if gender=="female"{TextField("اسم المعرّف أو بداية رقم جواله",text:$reference).task(id:reference){do{try await Task.sleep(nanoseconds:250_000_000);guard !reference.isEmpty else{referees=[];return};let r=Item.items(try await api.action("family_action","referees",["term":reference]));try Task.checkCancellation();referees=r}catch{}};ForEach(referees){p in Button(p.text("display_name")){reference=p.text("display_name");referees=[]}};Picker("صلة القرابة",selection:$relation){Text("اختر").tag("");ForEach(options.filter{$0.flag("for_reference") && $0.flag("enabled") || $0.text("code")==relation},id:\.rawCode){o in Text(o.text("label")).tag(o.text("code"))}}};TaskButton(title:"حفظ بياناتي",symbol:"checkmark"){guard full.split(whereSeparator:{$0.isWhitespace}).count==4 else{throw FamilyError(text:"أدخل الاسم الرباعي.")};_ = try await api.rpc("profile_save",["data":["full_name":full,"display_name":full,"phone":try phone(mobile),"gender":gender,"reference_name":reference,"relationship":relation]]);try await api.loadAccount();notice="حُفظت بياناتك."}}
        Section("الحساب والأمان"){TaskButton(title:"تغيير كلمة المرور عبر البريد",symbol:"key"){try await api.recover();notice="أرسلنا رابط تأكيد البريد لتغيير كلمة المرور."};TextField("البريد الجديد",text:$email).textInputAutocapitalization(.never).keyboardType(.emailAddress);TaskButton(title:"إرسال تأكيد تغيير البريد",symbol:"envelope"){guard email.contains("@") else{throw FamilyError(text:"أدخل البريد الجديد.")};_ = try await api.request("/auth/v1/user?redirect_to="+api.website.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed)!,method:"PUT",body:["email":email]);notice="راجع رسائل التأكيد في البريد القديم والجديد."};TextField("رقم جوال جديد",text:$newPhone).keyboardType(.phonePad);TaskButton(title:"طلب تغيير الجوال من المدير",symbol:"iphone"){_ = try await api.action("account_action","phone_request",["phone":try phone(newPhone)]);newPhone="";notice="وصل طلبك للمدير."}}
        if api.active{Section("نشاطي والعائلة"){NavigationLink("أخبار ذُكرت فيها"){NewsScreen(scope:.mentioned)};NavigationLink("أخباري وتعليقاتي وإعجاباتي"){ActivityScreen()};NavigationLink("شجرة عائلتي والأسماء المشابهة"){FamilyTreeScreen()}}};if api.profile.flag("endorsements_enabled"){NavigationLink("التعريف بالأعضاء"){EndorsementsScreen()}}
    }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).navigationTitle("حسابي").task{await load()}.onChange(of:photo){_,item in Task{do{guard let data=try await item?.loadTransferable(type:Data.self) else{return};let path=try await api.upload(data,bucket:"profile-images",portrait:false);do{_ = try await api.action("account_action","avatar",["path":path])}catch{_ = try? await api.request("/storage/v1/object/profile-images",method:"DELETE",body:["prefixes":[path]]);throw error};try await api.loadAccount();notice="حُفظت صورة العرض."}catch{self.error=api.errorText(error)}}}}
    func load()async{bio=api.profile.text("bio");full=api.profile.text("full_name");mobile=api.profile.text("phone");gender=api.profile.text("gender");reference=api.profile.text("reference_name");relation=api.profile.text("relationship");do{options=try await api.table("kinship_options",[q("select","*"),q("order","generation,label")])}catch{self.error=api.errorText(error)}}
}
extension Item {var rawCode:String{text("code")}}
struct MemberScreen:View {@EnvironmentObject private var api:Backend;let member:String;@State private var profile=Item()
    @State private var error="";var body:some View{VStack(spacing:20){Avatar(path:profile.text("avatar_path"),name:profile.text("display_name"),size:100);Text(profile.text("display_name")).font(.title3.bold());if !profile.text("bio").isEmpty{Text(profile.text("bio")).font(.body).multilineTextAlignment(.center).textSelection(.enabled)};Text(profile.text("role")=="admin" ? "مدير":profile.text("role")=="journalist" ? "صحفي":"عضو").foregroundStyle(.secondary);LoadError(text:error);Spacer()}.padding().navigationTitle("ملف العضو").task{do{profile=Item(try await api.action("account_action","directory_profile",["member":member]) as? [String:Any] ?? [:])}catch{self.error=api.errorText(error)}}}}
struct ActivityScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var data=Item()
    @State private var error=""
    let kinds=["posts","comments","mentions","likes"]
    func title(_ key:String)->String{switch key{case "posts":return "أخباري";case "comments":return "أخبار علّقت عليها";case "mentions":return "أخبار ذُكرت فيها";default:return "إعجاباتي"}}
    var body:some View {
        List {
            LoadError(text:error)
            ForEach(kinds,id:\.self){key in
                Section(title(key)){
                    ForEach(data.rows(key)){row in
                        NavigationLink{PostDestination(postID:row.text("post_id").isEmpty ? row.id:row.text("post_id"))}label:{
                            VStack(alignment:.leading,spacing:7){
                                Text(row.text("title")).font(.headline)
                                if !row.text("body").isEmpty{Text(row.text("body")).font(.subheadline).lineLimit(2)}
                                Text(dateValue(row.text("created_at")),style:.date).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if data.rows(key).isEmpty{Text("لا توجد أخبار هنا بعد").font(.footnote).foregroundStyle(.secondary)}
                }
            }
        }.scrollIndicators(.hidden).navigationTitle("نشاطي").task{do{data=Item(try await api.action("account_action","history") as? [String:Any] ?? [:])}catch{self.error=api.errorText(error)}}
    }
}
struct PostDestination:View {
    @EnvironmentObject private var api:Backend
    let postID:String
    @State private var post:Item?
    @State private var loading=true
    @State private var error=""
    var body:some View{Group{if loading{ProgressView()}else if let post=post{NotificationPost(post:post)}else{VStack{EmptyState(title:"الخبر لم يعد متاحًا",symbol:"newspaper");LoadError(text:error)}}}.navigationTitle("الخبر").navigationBarTitleDisplayMode(.inline).task(id:postID){loading=true;defer{loading=false};do{post=(try await api.table("posts",[q("select","*,profiles:profiles!posts_author_id_fkey(display_name,avatar_path),likes(count),comments(count)"),q("id","eq."+postID),q("deleted_at","is.null")])).first}catch{post=nil;self.error=api.errorText(error)}}}
}
struct MoreScreen:View {@EnvironmentObject private var api:Backend;@State private var logout=false;var body:some View{List{Section{Brand().frame(maxWidth:.infinity).padding(.vertical,15);Text(api.family.text("name")).font(.headline);Text("أخبارنا تجمعنا").font(.caption).foregroundStyle(.secondary)};if api.active{NavigationLink("الإشعارات"){NotificationsScreen()}};if api.writer{NavigationLink("مسوداتي"){NewsScreen(scope:.drafts)}};if api.admin{Section("إدارة العائلة"){NavigationLink("إدارة الأعضاء"){MembersScreen()};NavigationLink("مراجعة الأخبار"){NewsScreen(scope:.review)};NavigationLink("الأخبار المخفية"){NewsScreen(scope:.hidden)};NavigationLink("الإعلانات"){AdsAdminScreen()};NavigationLink("إعدادات العائلة والدردشة"){SettingsScreen()};NavigationLink("خيارات صلة القرابة"){KinshipAdminScreen()};NavigationLink("طلبات تغيير الجوال"){PhoneRequestsScreen()};NavigationLink("البيانات والمساحة"){StorageScreen()}}};if api.platformAdmin{NavigationLink("إدارة الكيانات العائلية"){TenantPlatformList()}};Section{Button("الخروج من الكيان العائلي",role:.destructive){Task{await api.exitFamily()}};Button("تسجيل الخروج من الحساب فقط",role:.destructive){logout=true}}}.scrollIndicators(.hidden).navigationTitle("المزيد").confirmationDialog("تسجيل الخروج؟",isPresented:$logout){Button("تسجيل الخروج",role:.destructive){Task{await api.logout()}}}}}
struct FamilyTreeScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var links:[Item]=[]
    @State private var known:[Item]=[]
    @State private var pending:[Item]=[]
    @State private var similar:[Item]=[]
    @State private var options:[Item]=[]
    @State private var matches:[Item]=[]
    @State private var term=""
    @State private var relation:[String:String]=[:]
    @State private var error=""
    var levels:[Int]{Array(Set([0]+links.map{$0.number("generation")})).sorted()}
    func load()async{do{links=Item.items(try await api.action("family_action","tree"));known=Item.items(try await api.action("family_action","trusted"));pending=Item.items(try await api.action("family_action","kinship_requests"));similar=Item.items(try await api.action("family_action","similar"));options=try await api.table("kinship_options",[q("select","*"),q("enabled","eq.true"),q("order","generation,label")]);error=""}catch{self.error=api.errorText(error)}}
    var generations:some View {
        ForEach(levels,id:\.self){level in
            VStack(spacing:14){
                if level != levels.first{Rectangle().fill(brandBlue.opacity(0.35)).frame(width:2,height:22)}
                Text(level<0 ? "الأصول · الجيل \(-level)":level>0 ? "الفروع · الجيل \(level)":"العائلة · جيلي").font(.caption.bold()).foregroundStyle(brandBlue)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12){
                    if level==0{FamilyPersonCard(person:api.profile,label:"أنا",canChat:false).overlay(RoundedRectangle(cornerRadius:22).stroke(brandBlue,lineWidth:2))}
                    ForEach(links.filter{$0.number("generation")==level}){p in
                        VStack(spacing:8){FamilyPersonCard(person:p,label:p.text("label"),canChat:p.flag("can_chat"));Text(p.flag("confirmed") ? "✓ قرابة مؤكدة":"بانتظار التأكيد").font(.caption2).foregroundStyle(p.flag("confirmed") ? .green:.secondary);TaskButton(title:"إزالة العلاقة",symbol:"minus.circle"){_ = try await api.action("family_action","unlink",["member":p.id]);await load()}.font(.caption).disabled(api.readOnly)}
                    }
                }
            }
        }
    }
    var requests:some View {
        VStack(alignment:.leading,spacing:12){Text("طلبات تأكيد القرابة").font(.headline);ForEach(pending){p in VStack(alignment:.leading,spacing:10){Text(p.text("display_name")+" · "+p.text("label"));HStack{TaskButton(title:"تأكيد القرابة",symbol:"checkmark"){_ = try await api.action("family_action","confirm_link",["owner":p.id]);await load()};TaskButton(title:"رفض",symbol:"xmark"){_ = try await api.action("family_action","reject_link",["owner":p.id]);await load()}}.disabled(api.readOnly)}}}
    }
    func candidate(_ p:Item)->some View {
        VStack(alignment:.leading,spacing:10){HStack{Avatar(path:p.text("avatar_path"),name:p.text("display_name"));Text(p.text("display_name")).font(.subheadline.bold())};Picker("صلة القرابة",selection:Binding(get:{relation[p.id] ?? ""},set:{relation[p.id]=$0})){Text("اختر").tag("");ForEach(options,id:\.rawCode){o in Text(o.text("label")).tag(o.text("code"))}};TaskButton(title:"إضافة وطلب تأكيد",symbol:"person.badge.plus"){guard let selected=relation[p.id],!selected.isEmpty else{throw FamilyError(text:"حدد صلة القرابة")};_ = try await api.action("family_action","link",["member":p.id,"relation":selected]);await load()}.disabled(api.readOnly)}.padding().background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:18))
    }
    var body:some View {
        ScrollView{VStack(spacing:24){Text("أجيال تجمعنا · استثناء التواصل يتطلب تعريفًا مقبولًا أو تأكيد القرابة. تشابه الأسماء وحده ليس إثباتًا.").font(.footnote).foregroundStyle(.secondary);LoadError(text:error);generations;Text("الأعضاء الذين عرّفتهم أو عرّفوك").font(.headline);LazyVGrid(columns:[GridItem(.adaptive(minimum:145))]){ForEach(known){p in FamilyPersonCard(person:p,label:"تعريف مقبول",canChat:p.flag("can_chat"))}};requests;TextField("ابحث عن قريب بالاسم أو رقم الجوال",text:$term).textFieldStyle(.roundedBorder).task(id:term){do{try await Task.sleep(nanoseconds:220_000_000);let found=Item.items(try await api.action("family_action","find_relative",["term":term]));try Task.checkCancellation();matches=found}catch{}};ForEach(matches){p in candidate(p)};Text("اقتراحات الأسماء · ٧٠٪ أو أكثر").font(.headline);ForEach(similar){p in candidate(p)}}.padding()}.background(Color(.systemGroupedBackground)).navigationTitle("شجرة عائلتي").task{await load()}
    }
}
struct FamilyPersonCard:View {
    @EnvironmentObject private var api:Backend
    let person:Item
    let label:String
    let canChat:Bool
    @State private var room:Room?
    var body:some View {
        VStack(spacing:10){NavigationLink{MemberScreen(member:person.id)}label:{VStack(spacing:8){Avatar(path:person.text("avatar_path"),name:person.text("display_name"),size:60);Text(person.text("display_name")).font(.subheadline.bold()).multilineTextAlignment(.center)}}.buttonStyle(.plain);Text(label).font(.caption).foregroundStyle(brandBlue);if canChat{TaskButton(title:"خاص",symbol:"bubble.left.and.bubble.right"){guard let thread=try await api.rpc("chat_open",["other":person.id])as? String else{throw FamilyError(text:"الدردشة غير متاحة")};room=Room(id:thread,title:person.text("display_name"),thread:thread,avatar:person.text("avatar_path"),peer:person.id)}.buttonStyle(.bordered)}}.padding(16).frame(maxWidth:.infinity).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:22)).fullScreenCover(item:$room){r in NavigationStack{ChatRoom(room:r).toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){room=nil}}}}}
    }
}
struct EndorsementsScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var term=""
    @State private var results:[Item]=[]
    @State private var requests:[Item]=[]
    @State private var error=""
    @State private var confirm:Item?
    @State private var offer:Item?
    func load()async{do{requests=Item.items(try await api.action("endorse_action","list"));error=""}catch{self.error=api.errorText(error)}}
    var body:some View{List{LoadError(text:error);Section(api.active ? "ابحث عن عضو ينتظر الاعتماد":"اختر عضوًا معتمدًا يعرفك"){TextField("الاسم أو الجوال أو البريد",text:$term).task(id:term){do{try await Task.sleep(nanoseconds:300_000_000);guard term.count>=3 else{results=[];return};let r=Item.items(try await api.action("endorse_action",api.active ? "search":"sponsors",["term":term]));try Task.checkCancellation();results=r}catch{if !Task.isCancelled{self.error=api.errorText(error)}}};ForEach(results){p in Button(p.text("display_name")){offer=p}}};Section("طلبات التعريف"){ForEach(requests){r in VStack(alignment:.leading,spacing:9){Text(r.text("display_name")).font(.headline);Text("المعرّف: "+r.text("sponsor_name"));Text(r.text("status")=="pending" ? "بانتظار الموافقة":r.text("status")=="approved" ? "تم التعريف":"مرفوض").font(.caption).foregroundStyle(.secondary);if r.text("sponsor_id")==api.user.id && r.text("status")=="pending"{Text(r.text("full_name"));Text(r.text("phone"));Text(r.text("email"));Text(r.text("gender")=="female" ? "أنثى":"ذكر");Text("المعرّف المسجل: "+r.text("reference_name")+" · "+r.text("relationship"));Button("أعرف هذا العضو وأوافق على تفعيله"){confirm=r};TaskButton(title:"لا أعرفه · رفض",symbol:"xmark"){_ = try await api.action("endorse_action","reject",["id":r.id]);await load()}}}}}}.navigationTitle("التعريف بالأعضاء").task{await load()}.confirmationDialog("إرسال طلب تعريف؟",isPresented:Binding(get:{offer != nil},set:{if !$0{offer=nil}})){Button("إرسال الطلب"){guard let p=offer else{return};offer=nil;Task{do{_ = try await api.action("endorse_action",api.active ? "offer":"request",["member":p.id]);await load()}catch{self.error=api.errorText(error)}}}}.confirmationDialog("أؤكد معرفتي الشخصية بهذا العضو وصحة بياناته وأوافق على تفعيل حسابه",isPresented:Binding(get:{confirm != nil},set:{if !$0{confirm=nil}})){Button("تأكيد المعرفة والتفعيل"){guard let r=confirm else{return};confirm=nil;Task{do{_ = try await api.action("endorse_action","approve",["id":r.id,"confirm":true]);await load()}catch{self.error=api.errorText(error)}}}}}
}
