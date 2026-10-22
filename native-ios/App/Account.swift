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
        HubBirthdayForm();Section("بياناتي"){TextField("الاسم الرباعي",text:$full);TextField("رقم الجوال",text:$mobile).keyboardType(.phonePad).disabled(!api.profile.text("phone").isEmpty);Picker("الجنس",selection:$gender){Text("اختر").tag("");Text("ذكر").tag("male");Text("أنثى").tag("female")}.disabled(!api.profile.text("gender").isEmpty);if gender=="female"{TextField("اسم المعرّف أو بداية رقم جواله",text:$reference).task(id:reference){do{try await Task.sleep(nanoseconds:250_000_000);guard !reference.isEmpty else{referees=[];return};let r=Item.items(try await api.action("family_action","referees",["term":reference]));try Task.checkCancellation();referees=r}catch{}};ForEach(referees){p in Button(p.text("display_name")){reference=p.text("display_name");referees=[]}};Picker("صلة القرابة",selection:$relation){Text("اختر").tag("");ForEach(options.filter{$0.flag("for_reference") && $0.flag("enabled") || $0.text("code")==relation},id:\.rawCode){o in Text(o.text("label")).tag(o.text("code"))}}};TaskButton(title:"حفظ بياناتي",symbol:"checkmark"){guard full.split(whereSeparator:{$0.isWhitespace}).count==4 else{throw FamilyError(text:"أدخل الاسم الرباعي.")};_ = try await api.rpc("profile_save",["data":["full_name":full,"display_name":full,"phone":try phone(mobile),"gender":gender,"reference_name":reference,"relationship":relation]]);try await api.loadAccount();notice="حُفظت بياناتك."}}
        Section("الحساب والأمان"){TaskButton(title:"تغيير كلمة المرور عبر البريد",symbol:"key"){try await api.recover();notice="أرسلنا رابط تأكيد البريد لتغيير كلمة المرور."};TextField("البريد الجديد",text:$email).textInputAutocapitalization(.never).keyboardType(.emailAddress);TaskButton(title:"إرسال تأكيد تغيير البريد",symbol:"envelope"){guard email.contains("@") else{throw FamilyError(text:"أدخل البريد الجديد.")};_ = try await api.request("/auth/v1/user?redirect_to="+api.website.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed)!,method:"PUT",body:["email":email]);notice="راجع رسائل التأكيد في البريد القديم والجديد."};TextField("رقم جوال جديد",text:$newPhone).keyboardType(.phonePad);TaskButton(title:"طلب تغيير الجوال من المدير",symbol:"iphone"){_ = try await api.action("account_action","phone_request",["phone":try phone(newPhone)]);newPhone="";notice="وصل طلبك للمدير."}}
        if api.active{Section("نشاطي والعائلة"){NavigationLink("بروفايلي والأخبار المذكور فيها"){MemberScreen(member:api.user.id)};NavigationLink("أخباري وتعليقاتي وإعجاباتي"){ActivityScreen()};NavigationLink("شجرة عائلتي والأسماء المشابهة"){FamilyTreeScreen()}}};if api.profile.flag("endorsements_enabled"){NavigationLink("التعريف بالأعضاء"){EndorsementsScreen()}}
    }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).navigationTitle("حسابي").task{await load()}.onChange(of:photo){_,item in Task{do{guard let data=try await item?.loadTransferable(type:Data.self) else{return};let path=try await api.upload(data,bucket:"profile-images",portrait:false);do{_ = try await api.action("account_action","avatar",["path":path])}catch{_ = try? await api.request("/storage/v1/object/profile-images",method:"DELETE",body:["prefixes":[path]]);throw error};try await api.loadAccount();notice="حُفظت صورة العرض."}catch{self.error=api.errorText(error)}}}}
    func load()async{bio=api.profile.text("bio");full=api.profile.text("full_name");mobile=api.profile.text("phone");gender=api.profile.text("gender");reference=api.profile.text("reference_name");relation=api.profile.text("relationship");do{options=try await api.table("kinship_options",[q("select","*"),q("order","generation,label")])}catch{self.error=api.errorText(error)}}
}
extension Item {var rawCode:String{text("code")}}
struct MemberScreen:View {
    @EnvironmentObject private var api:Backend
    let member:String
    @State private var profile=Item()
    @State private var posts:[Item]=[]
    @State private var scope="mentions"
    @State private var more=true
    @State private var loading=false
    @State private var error=""
    @State private var generation=0
    func call(_ action:String,_ payload:[String:Any]=[:])async throws->Any{try await api.action("member_social",action,payload.merging(["member":member]){_,new in new})}
    func loadProfile()async{do{profile=Item(try await call("profile")as? [String:Any] ?? [:]);error=""}catch{self.error=api.errorText(error)}}
    func loadGrid(reset:Bool)async{generation += 1;let token=generation;let tab=scope;let offset=reset ? 0:posts.count;loading=true;if reset{posts=[]};defer{if token==generation{loading=false}};do{let rows=Item.items(try await call("grid",["scope":tab,"offset":offset]));try Task.checkCancellation();guard token==generation,scope==tab else{return};if reset{posts=rows}else{posts += rows};more=rows.count==30;error=""}catch{if !Task.isCancelled,token==generation{self.error=api.errorText(error)}}}
    var summary:some View{VStack(alignment:.leading,spacing:12){HStack(spacing:22){Avatar(path:profile.text("avatar_path"),name:profile.text("display_name"),size:84);HStack{stat("منشورات","posts");stat("متابعون","followers");stat("يتابع","following_count")}.frame(maxWidth:.infinity)};Text(profile.text("display_name")).font(.subheadline.bold());Text(familyRoleLabels(profile.raw["roles"])).font(.caption).foregroundStyle(brandBlue);if !profile.text("birth_date").isEmpty{Text("تاريخ الميلاد: "+profile.text("birth_date")).font(.caption)};if !profile.text("bio").isEmpty{Text(profile.text("bio")).font(.subheadline).textSelection(.enabled)};if member != api.user.id && !profile.id.isEmpty{TaskButton(title:profile.flag("following") ? "تتابعه ✓":"متابعة",symbol:profile.flag("following") ? "person.badge.minus":"person.badge.plus"){profile=Item(try await call(profile.flag("following") ? "unfollow":"follow")as? [String:Any] ?? [:])}.buttonStyle(.borderedProminent).disabled(api.readOnly);Text("تصلك تنبيهات عند نشره خبرًا أو ذكره في خبر.").font(.caption).foregroundStyle(.secondary)}}.padding(18)}
    func stat(_ label:String,_ key:String)->some View{VStack(spacing:3){Text(String(profile.number(key))).font(.headline);Text(label).font(.caption)}.frame(maxWidth:.infinity)}
    var tabs:some View{HStack(spacing:0){tab("posts","square.grid.3x3","منشوراته");tab("mentions","at","أخبار ذُكر فيها")}.overlay(alignment:.bottom){Rectangle().fill(Color(.separator)).frame(height:0.5)}}
    func tab(_ value:String,_ symbol:String,_ title:String)->some View{Button{scope=value}label:{Label(title,systemImage:symbol).font(.subheadline).frame(maxWidth:.infinity).padding(.vertical,14).foregroundStyle(scope==value ? Color.primary:Color.secondary).overlay(alignment:.bottom){if scope==value{Rectangle().frame(height:2)}}}.buttonStyle(.plain)}
    var grid:some View{LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:3),spacing:2){ForEach(posts){post in NavigationLink{PostDestination(postID:post.id)}label:{MemberPhotoTile(post:post)}.buttonStyle(.plain).accessibilityLabel("فتح الخبر: "+post.text("title"))}}}
    var body:some View{ScrollView{VStack(spacing:0){summary;tabs;LoadError(text:error);grid;if loading{ProgressView().padding()};if posts.isEmpty && !loading{EmptyState(title:"لا توجد أخبار منشورة هنا",symbol:"square.grid.3x3")};if more && !posts.isEmpty{TaskButton(title:"عرض المزيد",symbol:"arrow.down"){await loadGrid(reset:false)}.disabled(loading).padding()}}.frame(maxWidth:720).frame(maxWidth:.infinity)}.navigationTitle(profile.text("display_name").isEmpty ? "ملف العضو":profile.text("display_name")).navigationBarTitleDisplayMode(.inline).task{await loadProfile()}.task(id:scope){await loadGrid(reset:true)}.refreshable{await loadProfile();await loadGrid(reset:true)}.privacySensitive()}
}
struct MemberPhotoTile:View {
    let post:Item
    var body:some View{Rectangle().fill(Color(.secondarySystemBackground)).aspectRatio(1,contentMode:.fit).overlay{GeometryReader{geometry in if let path=post.imagePaths.first{PrivateImage(path:path,bucket:"news-images").frame(width:geometry.size.width,height:geometry.size.height).clipped()}else{Image(systemName:"text.alignright").font(.title).foregroundStyle(brandBlue).frame(width:geometry.size.width,height:geometry.size.height)}}}.overlay(alignment:.topLeading){if post.imagePaths.count>1{Image(systemName:"square.on.square.fill").font(.caption).foregroundStyle(.white).shadow(radius:2).padding(8)}}.clipped()}
}
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
struct MoreScreen:View {@EnvironmentObject private var api:Backend;@State private var logout=false;@State private var wholeTreeVisible=false;var body:some View{List{Section{Brand().frame(maxWidth:.infinity).padding(.vertical,15);Text(api.family.text("name")).font(.headline);Text("أخبارنا تجمعنا").font(.caption).foregroundStyle(.secondary)};if api.active{NewsRequestMenu();NavigationLink("إضافة تطبيق العائلة للشاشة الرئيسية"){FamilyInstallScreen()};HubMenu();if wholeTreeVisible || api.admin{NavigationLink("شجرة العائلة"){WholeFamilyTreeScreen()}};NavigationLink("الإشعارات"){NotificationsScreen()}};if api.writer{NavigationLink("مسوداتي"){NewsScreen(scope:.drafts)}};if api.admin{Section("إدارة العائلة"){NavigationLink("لوحة إدارة العائلة"){FamilyAdminDashboard()};NavigationLink("إدارة الأعضاء"){MembersScreen()};NavigationLink("مراجعة الأخبار"){NewsScreen(scope:.review)};NavigationLink("الأخبار المخفية"){NewsScreen(scope:.hidden)};NavigationLink("الإعلانات"){AdsAdminScreen()};NavigationLink("إعدادات العائلة والدردشة"){SettingsScreen()};NavigationLink("خيارات صلة القرابة"){KinshipAdminScreen()};NavigationLink("طلبات تغيير الجوال"){PhoneRequestsScreen()};NavigationLink("البيانات والمساحة"){StorageScreen()}}};Section{Button("الخروج من الكيان العائلي",role:.destructive){Task{await api.exitFamily()}};Button("تسجيل الخروج من الحساب فقط",role:.destructive){logout=true}}}.scrollIndicators(.hidden).navigationTitle("المزيد").task{if api.active{wholeTreeVisible=Item((try? await api.action("whole_tree","settings"))as? [String:Any] ?? [:]).flag("enabled")}}.confirmationDialog("تسجيل الخروج؟",isPresented:$logout){Button("تسجيل الخروج",role:.destructive){Task{await api.logout()}}}}}
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

struct SharedExport:Identifiable {let id=UUID();let items:[Any];var files:[URL]=[]}
struct NativeShareSheet:UIViewControllerRepresentable {
 let export:SharedExport
 func makeUIViewController(context:Context)->UIActivityViewController{let controller=UIActivityViewController(activityItems:export.items,applicationActivities:nil);controller.completionWithItemsHandler={_,_,_,_ in for file in export.files{try? FileManager.default.removeItem(at:file)}};return controller}
 func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
}
struct WholeTreeLayout {
 let nodes:[Item];let edges:[Item];var points:[String:CGPoint]=[:];var labels:[String:String]=[:];var size=CGSize(width:760,height:600)
 init(_ data:Item){nodes=data.rows("nodes");edges=data.rows("edges");var adjacency:[String:[(String,Int)]]=[:];let names=Dictionary(uniqueKeysWithValues:nodes.map{($0.id,$0.text("name"))});for n in nodes{adjacency[n.id]=[]};for e in edges{let a=e.text("owner"),b=e.text("member"),g=e.number("generation");guard adjacency[a] != nil,adjacency[b] != nil else{continue};adjacency[a,default:[]].append((b,g));adjacency[b,default:[]].append((a,-g));labels[b,default:""] += (labels[b,default:""].isEmpty ? "":"، ")+e.text("label")+" لـ "+(names[a] ?? "")};var seen=Set<String>();var components:[([String],[String:Int])]=[];var isolated:[String]=[]
 for n in nodes where !seen.contains(n.id){var queue=[n.id],levels=[n.id:0],cursor=0;seen.insert(n.id);while cursor<queue.count{let id=queue[cursor];cursor += 1;for(next,delta)in adjacency[id] ?? []{if levels[next]==nil{levels[next]=(levels[id] ?? 0)+delta;seen.insert(next);queue.append(next)}}};if queue.count==1{isolated += queue}else{components.append((queue,levels))}}
 if !isolated.isEmpty{components.append((isolated,Dictionary(uniqueKeysWithValues:isolated.map{($0,0)})))};var y:CGFloat=40;var columns=1
 for(ids,levels)in components{for level in Set(levels.values).sorted(){let row=ids.filter{levels[$0]==level};columns=max(columns,min(8,row.count));for(i,id)in row.enumerated(){points[id]=CGPoint(x:30+CGFloat(i%8)*230,y:y+CGFloat(i/8)*125)};y += CGFloat((row.count+7)/8)*125+55};y += 35};size=CGSize(width:max(760,60+CGFloat(columns)*230),height:max(600,y+30))
 }
}
struct WholeFamilyTreeScreen:View {
 @EnvironmentObject private var api:Backend
 @State private var data=Item()
 @State private var layout=WholeTreeLayout(Item())
 @State private var error=""
 @State private var enabled=false
 @State private var owner=""
 @State private var member=""
 @State private var relation=""
 @State private var shared:SharedExport?
 func call(_ action:String,_ payload:[String:Any]=[:])async throws->Any{try await api.action("whole_tree",action,payload)}
 func load()async{do{data=Item(try await call("get")as? [String:Any] ?? [:]);layout=WholeTreeLayout(data);enabled=data.flag("public_enabled");error=""}catch{data=Item();self.error=api.errorText(error)}}
 var chart:some View{ScrollView([.horizontal,.vertical]){ZStack(alignment:.topLeading){Canvas{context,_ in for edge in layout.edges{if let a=layout.points[edge.text("owner")],let b=layout.points[edge.text("member")]{var line=Path();line.move(to:CGPoint(x:a.x+105,y:a.y+45));line.addCurve(to:CGPoint(x:b.x+105,y:b.y+45),control1:CGPoint(x:a.x+105,y:(a.y+b.y)/2+45),control2:CGPoint(x:b.x+105,y:(a.y+b.y)/2+45));context.stroke(line,with:.color(brandBlue.opacity(0.45)),lineWidth:2)}}}.frame(width:layout.size.width,height:layout.size.height);ForEach(layout.nodes){node in if let point=layout.points[node.id]{VStack(spacing:6){NavigationLink{MemberScreen(member:node.id)}label:{Text(node.text("name")).font(.subheadline.bold()).multilineTextAlignment(.center)}.buttonStyle(.plain);Text(layout.labels[node.id] ?? "لم تُحدد صلة قرابة").font(.caption2).foregroundStyle(.secondary).lineLimit(2)}.padding(10).frame(width:210,height:90).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(brandBlue.opacity(0.25))).environment(\.layoutDirection,.rightToLeft).offset(x:point.x,y:point.y)}}}.frame(width:layout.size.width,height:layout.size.height)}.frame(height:460).environment(\.layoutDirection,.leftToRight)}
 var settings:some View{Section("إدارة الشجرة"){Toggle("عرض الشجرة لجميع الأعضاء بالقائمة",isOn:$enabled);TaskButton(title:"حفظ خيار العرض",symbol:"checkmark"){_ = try await call("enable",["enabled":enabled])}.disabled(api.readOnly);Picker("صاحب العلاقة",selection:$owner){Text("اختر").tag("");ForEach(data.rows("nodes")){n in Text(n.text("name")).tag(n.id)}};Picker("القريب",selection:$member){Text("اختر").tag("");ForEach(data.rows("nodes")){n in Text(n.text("name")).tag(n.id)}};Picker("القريب بالنسبة لصاحب العلاقة",selection:$relation){Text("اختر").tag("");ForEach(data.rows("options"),id:\.rawCode){o in Text(o.text("label")).tag(o.text("code"))}};Text("مثال: صاحب العلاقة أحمد، والقريب علي، والصلة أب تعني أن عليًا أبو أحمد.").font(.caption);TaskButton(title:"اعتماد الصلة",symbol:"person.2.badge.plus"){_ = try await call("link",["owner":owner,"member":member,"relation":relation]);await load()}.disabled(api.readOnly || owner.isEmpty || member.isEmpty || relation.isEmpty)}}
 func edgeDescription(_ e:Item)->String{let memberName=layout.nodes.first{$0.id==e.text("member")}?.text("name") ?? "";let ownerName=layout.nodes.first{$0.id==e.text("owner")}?.text("name") ?? "";return memberName+" · "+e.text("label")+" لـ "+ownerName}
 var links:some View{Section("الروابط المؤكدة"){ForEach(layout.edges.indices,id:\.self){i in let e=layout.edges[i];VStack(alignment:.leading){Text(edgeDescription(e)).font(.caption);TaskButton(title:"إزالة الصلة",symbol:"trash"){_ = try await call("unlink",["owner":e.text("owner"),"member":e.text("member")]);await load()}.disabled(api.readOnly)}}}}
 var body:some View{List{LoadError(text:error);if !data.raw.isEmpty{Section{Text(data.text("name")).font(.headline);Text("\(layout.nodes.count) عضو · \(layout.edges.count) صلة مؤكدة");Text("الأعضاء غير المرتبطين يظهرون منفصلين. لا نفترض صلات قرابة من الأسماء.").font(.caption);chart};if data.flag("admin"){Section("التصدير"){TaskButton(title:"حفظ PDF بمقاس A3",symbol:"doc"){shared=try treePDF(layout,title:data.text("name"))};TaskButton(title:"صور للجوال والمشاركة",symbol:"square.and.arrow.up"){shared=try treeMobileImages(layout,title:data.text("name"))}}};if data.flag("admin"){settings;links}}}.navigationTitle("شجرة العائلة الكاملة").task{await load()}.refreshable{await load()}.sheet(item:$shared,onDismiss:{if let current=shared{for file in current.files{try? FileManager.default.removeItem(at:file)}};shared=nil}){NativeShareSheet(export:$0)}}
}
func drawWholeTree(_ graph:WholeTreeLayout,title:String,context:CGContext,bounds:CGRect,top:CGFloat,scale:CGFloat,page:Int,pages:Int){UIColor.white.setFill();context.fill(bounds);let paragraph=NSMutableParagraphStyle();paragraph.alignment = .right;paragraph.baseWritingDirection = .rightToLeft;func text(_ value:String,_ rect:CGRect,_ size:CGFloat,_ bold:Bool=false){(value as NSString).draw(in:rect,withAttributes:[.font:bold ? UIFont.boldSystemFont(ofSize:size):UIFont.systemFont(ofSize:size),.foregroundColor:UIColor(red:0.07,green:0.22,blue:0.28,alpha:1),.paragraphStyle:paragraph])};text("شجرة "+title,CGRect(x:25,y:18,width:bounds.width-50,height:40),22,true);text("الصفحة \(page) / \(pages) · الصلات المؤكدة فقط",CGRect(x:25,y:bounds.height-35,width:bounds.width-50,height:25),14);context.saveGState();context.clip(to:CGRect(x:0,y:70,width:bounds.width,height:bounds.height-115));context.translateBy(x:0,y:70-top*scale);context.scaleBy(x:scale,y:scale);context.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.5).cgColor);context.setLineWidth(2);for edge in graph.edges{if let a=graph.points[edge.text("owner")],let b=graph.points[edge.text("member")]{context.move(to:CGPoint(x:a.x+105,y:a.y+45));context.addCurve(to:CGPoint(x:b.x+105,y:b.y+45),control1:CGPoint(x:a.x+105,y:(a.y+b.y)/2+45),control2:CGPoint(x:b.x+105,y:(a.y+b.y)/2+45));context.strokePath()}};for n in graph.nodes{guard let p=graph.points[n.id]else{continue};let rect=CGRect(origin:p,size:CGSize(width:210,height:90));context.setFillColor(UIColor(red:0.93,green:0.97,blue:0.98,alpha:1).cgColor);context.fill(rect);context.setStrokeColor(UIColor.systemGray3.cgColor);context.stroke(rect);text(n.text("name"),CGRect(x:p.x+10,y:p.y+12,width:190,height:46),18,true);text(graph.labels[n.id] ?? "لم تُحدد صلة",CGRect(x:p.x+10,y:p.y+62,width:190,height:24),12)};context.restoreGState()}
func treePDF(_ graph:WholeTreeLayout,title:String)throws->SharedExport{let bounds=CGRect(x:0,y:0,width:1190.55,height:841.89),scale=bounds.width/graph.size.width,step=(bounds.height-115)/scale-110,count=max(1,Int(ceil(graph.size.height/step)));guard count<=150 else{throw FamilyError(text:"الشجرة كبيرة جدًا للتصدير دفعة واحدة")};let file=FileManager.default.temporaryDirectory.appendingPathComponent("family-tree-"+UUID().uuidString+".pdf");try UIGraphicsPDFRenderer(bounds:bounds).writePDF(to:file){renderer in for i in 0..<count{renderer.beginPage();drawWholeTree(graph,title:title,context:renderer.cgContext,bounds:bounds,top:CGFloat(i)*step,scale:scale,page:i+1,pages:count)}};return SharedExport(items:[file],files:[file])}
func treeMobileImages(_ graph:WholeTreeLayout,title:String)throws->SharedExport{let bounds=CGRect(x:0,y:0,width:1440,height:2560),scale=bounds.width/graph.size.width,step=(bounds.height-115)/scale-110,count=max(1,Int(ceil(graph.size.height/step)));guard count<=150 else{throw FamilyError(text:"الشجرة كبيرة جدًا للتصدير دفعة واحدة")};var files:[URL]=[];do{for i in 0..<count{try autoreleasepool{let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true;let image=UIGraphicsImageRenderer(bounds:bounds,format:format).image{ctx in drawWholeTree(graph,title:title,context:ctx.cgContext,bounds:bounds,top:CGFloat(i)*step,scale:scale,page:i+1,pages:count)};guard let bytes=image.jpegData(compressionQuality:0.9)else{throw FamilyError(text:"تعذّر إنشاء الصورة")};let file=FileManager.default.temporaryDirectory.appendingPathComponent("family-tree-\(i+1)-"+UUID().uuidString+".jpg");try bytes.write(to:file);files.append(file)}}}catch{for file in files{try? FileManager.default.removeItem(at:file)};throw error};return SharedExport(items:files,files:files)}

func familyRoleLabels(_ value:Any?)->String{let roles=value as? [String] ?? [];let names=["admin":"مدير العائلة","journalist":"صحفي","auditor":"مدقق","member":"عضو"];return roles.filter{$0 != "member" || roles.count==1}.sorted().map{names[$0] ?? $0}.joined(separator:" · ")}
struct HubMenu:View{
 @EnvironmentObject private var api:Backend
 @State private var info=Item()
 var body:some View{Section("مجتمع العائلة"){NavigationLink("البحث عن عضو ومتابعته"){HubDirectoryScreen(team:false)};NavigationLink("إدارة الكيان العائلي"){HubDirectoryScreen(team:true)};if info.flag("enabled"){NavigationLink("الساحة الحرة"){FreeSquareScreen()}};if info.flag("reviewer"){NavigationLink("طلبات التفعيل · \(info.number("pending"))"){HubActivationScreen()}}}.task{await load()}.onReceive(Timer.publish(every:30,on:.main,in:.common).autoconnect()){_ in Task{await load()}}}
 func load()async{if let value=try? await api.action("community_hub","self")as? [String:Any]{info=Item(value)}}
}
struct HubDirectoryScreen:View{
 @EnvironmentObject private var api:Backend
 let team:Bool
 @State private var term=""
 @State private var rows:[Item]=[]
 @State private var error=""
 @State private var generation=0
 var body:some View{List{LoadError(text:error);ForEach(rows){p in HStack{NavigationLink{MemberScreen(member:p.id)}label:{HStack{Avatar(path:p.text("avatar_path"),name:p.text("display_name"),size:44);VStack(alignment:.leading){Text(p.text("display_name"));Text(familyRoleLabels(p.raw["roles"])).font(.caption).foregroundStyle(.secondary)}}};if p.id != api.user.id && !team{TaskButton(title:p.flag("following") ? "تتابعه ✓":"متابعة",symbol:"person.badge.plus"){_ = try await api.action("member_social",p.flag("following") ? "unfollow":"follow",["member":p.id]);await load()}.disabled(api.readOnly)}}};if rows.isEmpty{Text(team ? "لم يحدد فريق الإدارة بعد.":"ابحث عن عضو بالاسم من أول حرف.").foregroundStyle(.secondary)}}.navigationTitle(team ? "إدارة الكيان العائلي":"الأعضاء والمتابعة").searchable(text:$term,prompt:"اسم العضو").task(id:term){do{try await Task.sleep(nanoseconds:250_000_000);try Task.checkCancellation();await load()}catch{}}.refreshable{await load()}}
 func load()async{generation += 1;let n=generation;do{if !team && term.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{rows=[];return};let data=Item.items(try await api.action("community_hub",team ? "team":"search",["term":term]));guard n==generation,!Task.isCancelled else{return};rows=team && !term.isEmpty ? data.filter{$0.text("display_name").contains(term)}:data;error=""}catch{if n==generation{self.error=api.errorText(error)}}}
}
struct HubBirthdayForm:View{
 @EnvironmentObject private var api:Backend
 @State private var date=Date()
 @State private var hasDate=false
 @State private var visible=false
 @State private var roles=""
 @State private var notice=""
 var body:some View{Section("الميلاد والصلاحيات"){Text(roles).foregroundStyle(brandBlue);Toggle("إضافة تاريخ الميلاد",isOn:$hasDate);if hasDate{DatePicker("تاريخ الميلاد",selection:$date,in:Date(timeIntervalSince1970:-2208988800)...Date(),displayedComponents:.date);Toggle("إظهاره لأعضاء العائلة",isOn:$visible)};Text("التاريخ المخفي يظهر لك ولمدير العائلة فقط.").font(.caption).foregroundStyle(.secondary);TaskButton(title:"حفظ تاريخ الميلاد",symbol:"calendar"){let f=DateFormatter();f.calendar=Calendar(identifier:.gregorian);f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";let value:Any=hasDate ? f.string(from:date):NSNull();_ = try await api.action("community_hub","birth_save",["birth_date":value,"visible":visible]);notice="حُفظ تاريخ الميلاد والخصوصية."}.disabled(api.readOnly);if !notice.isEmpty{Text(notice)}}.task{do{let d=Item(try await api.action("community_hub","self")as? [String:Any] ?? [:]);roles=familyRoleLabels(d.raw["roles"]);visible=d.flag("birth_visible");let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";if let v=f.date(from:d.text("birth_date")){date=v;hasDate=true}}catch{notice=api.errorText(error)}}}
}
struct HubActivationScreen:View{
 @EnvironmentObject private var api:Backend
 @State private var rows:[Item]=[]
 @State private var error=""
 var body:some View{List{LoadError(text:error);ForEach(rows){p in VStack(alignment:.leading,spacing:10){Text(p.text("display_name")).font(.headline);Text(p.text("email"));Text(p.flag("email_confirmed") ? "البريد مؤكد":"ينتظر تأكيد البريد");Text("المعرّف: "+p.text("reference_name")+" · "+p.text("relationship"));Text("الجنس: "+(p.text("gender")=="female" ? "أنثى":"ذكر"));TaskButton(title:"اعتماد وتفعيل العضو",symbol:"person.badge.shield.checkmark"){_ = try await api.action("community_hub","activate",["member":p.id]);await load()}.disabled(api.readOnly || !p.flag("email_confirmed"))}};if rows.isEmpty && error.isEmpty{Text("لا توجد طلبات تفعيل.")}}.navigationTitle("طلبات التفعيل").task{await load()}.refreshable{await load()}}
 func load()async{do{rows=Item.items(try await api.action("community_hub","pending"));error=""}catch{rows=[];self.error=api.errorText(error)}}
}
struct HubRolesForm:View{
 @EnvironmentObject private var api:Backend
 let member:String
 @State private var data=Item()
 @State private var manager=false
 @State private var journalist=false
 @State private var auditor=false
 @State private var notice=""
 var body:some View{Section("الصلاحيات المتعددة وبيانات العضو"){Text("الميلاد: "+(data.text("birth_date").isEmpty ? "غير مسجل":data.text("birth_date")));Text("الاسم الرباعي: "+data.text("full_name"));Text("الجوال: "+data.text("phone"));Text("المعرّف: "+data.text("reference_name")+" · "+data.text("relationship"));Toggle("مدير العائلة",isOn:$manager);Toggle("صحفي",isOn:$journalist);Toggle("مدقق طلبات التفعيل",isOn:$auditor);TaskButton(title:"حفظ الصلاحيات المتعددة",symbol:"person.badge.key"){var roles:[String]=[];if manager{roles.append("admin")};if journalist{roles.append("journalist")};if auditor{roles.append("auditor")};_ = try await api.action("community_hub","roles",["member":member,"roles":roles.isEmpty ? ["member"]:roles]);notice="حُفظت الصلاحيات."}.disabled(api.readOnly || member==api.user.id);Text(notice)}.task{do{data=Item(try await api.action("community_hub","details",["member":member])as? [String:Any] ?? [:]);let roles=data.raw["roles"]as? [String] ?? [];manager=roles.contains("admin");journalist=roles.contains("journalist");auditor=roles.contains("auditor")}catch{notice=api.errorText(error)}}}
}
struct HubSquareSetting:View{
 @EnvironmentObject private var api:Backend
 @State private var enabled=false
 @State private var notice=""
 var body:some View{Section("الساحة الحرة"){Toggle("تشغيل الساحة الحرة لجميع الأعضاء",isOn:$enabled);TaskButton(title:"حفظ إعداد الساحة",symbol:"checkmark"){_ = try await api.action("community_hub","enable",["enabled":enabled]);notice="حُفظ الإعداد."}.disabled(api.readOnly);Text(notice)}.task{if let d=try? await api.action("community_hub","self")as? [String:Any]{enabled=Item(d).flag("enabled")}}}
}
struct FreeSquareScreen:View{
 @EnvironmentObject private var api:Backend
 @State private var rows:[Item]=[]
 @State private var bodyText=""
 @State private var mentions:[Item]=[]
 @State private var error=""
 @State private var more=false
 var body:some View{ScrollView{LazyVStack(spacing:14){LoadError(text:error);VStack(alignment:.leading){Text("الساحة الحرة").font(.title2.bold());TextField("شارك فكرة أو افتح نقاشًا…",text:$bodyText,axis:.vertical).lineLimit(3...8).textFieldStyle(.roundedBorder);SquareMentionPicker(text:$bodyText,selected:$mentions);TaskButton(title:"نشر",symbol:"paperplane"){_ = try await api.action("community_hub","publish",["body":bodyText,"mentions":mentions.map(\.id)]);bodyText="";mentions=[];await load(reset:true)}.disabled(api.readOnly || bodyText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || bodyText.count>5000)}.padding();ForEach(rows){p in SquarePostCard(post:p){await load(reset:true)}};if more{TaskButton(title:"منشورات أقدم",symbol:"arrow.down"){await load(reset:false)}}}.frame(maxWidth:720).frame(maxWidth:.infinity).padding(.horizontal,10)}.navigationTitle("الساحة الحرة").task{await load(reset:true)}.refreshable{await load(reset:true)}}
 func load(reset:Bool)async{do{let payload:[String:Any]=reset ? [:]:["before":rows.last?.id ?? ""];let result=Item.items(try await api.action("community_hub","feed",payload));if reset{rows=result}else{rows += result};more=result.count==30;error=""}catch{rows=[];self.error=api.errorText(error)}}
}
struct SquarePostCard:View{
 @EnvironmentObject private var api:Backend
 let post:Item
 let reload:()async->Void
 @State private var showComments=false
 @State private var deleteConfirm=false
 var body:some View{VStack(alignment:.leading,spacing:12){HStack{NavigationLink{MemberScreen(member:post.text("author_id"))}label:{HStack{Avatar(path:post.text("avatar_path"),name:post.text("display_name"),size:38);Text(post.text("display_name")).font(.subheadline.bold())}};Spacer();if api.admin || post.text("author_id")==api.user.id{Button(role:.destructive){deleteConfirm=true}label:{Image(systemName:"trash")}.disabled(api.readOnly)}};Text(post.text("body")).font(.system(size:17)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading);ForEach(post.rows("mentions")){m in NavigationLink("@"+m.text("display_name")){MemberScreen(member:m.id)}.font(.subheadline)};Text(post.text("created_at").replacingOccurrences(of:"T",with:" ").prefix(16)).font(.caption).foregroundStyle(.secondary);ScrollView(.horizontal){HStack{ForEach(["👍","❤️","😂","😮","😢","🙏"],id:\.self){emoji in TaskButton(title:emoji+" "+String(post.child("reactions").number(emoji)),symbol:post.text("my_reaction")==emoji ? "checkmark":""){_ = try await api.action("community_hub","react",["post":post.id,"emoji":post.text("my_reaction")==emoji ? "":emoji]);await reload()}.disabled(api.readOnly)}}};DisclosureGroup("التعليقات · \(post.number("comments"))",isExpanded:$showComments){if showComments{SquareComments(post:post.id)}}}.padding(16).background(Color(.systemBackground),in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(Color(.separator).opacity(0.3))).confirmationDialog("حذف المنشور وتعليقاته؟",isPresented:$deleteConfirm){Button("حذف",role:.destructive){Task{do{_ = try await api.action("community_hub","delete",["post":post.id]);await reload()}catch{}}}}}
}
struct SquareComments:View {
 @EnvironmentObject private var api:Backend
 let post:String
 @State private var rows:[Item]=[]
 @State private var text=""
 @State private var error=""
 @State private var more=false
 var body:some View {
  VStack(alignment:.leading,spacing:12) {
   LoadError(text:error)
   ForEach(rows) { r in
    VStack(alignment:.leading) {
     NavigationLink(r.text("display_name")){MemberScreen(member:r.text("author_id"))}.font(.caption.bold())
     Text(r.text("body")).textSelection(.enabled)
     if api.admin || r.text("author_id")==api.user.id {
      TaskButton(title:"حذف التعليق",symbol:"trash") {
       _ = try await api.action("community_hub","comment_delete",["post":post,"comment":r.id])
       await load(reset:true)
      }.disabled(api.readOnly)
     }
    }
   }
   if more{TaskButton(title:"تعليقات أخرى",symbol:"arrow.down"){await load(reset:false)}}
   TextField("اكتب تعليقك…",text:$text,axis:.vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
   TaskButton(title:"تعليق",symbol:"paperplane") {
    _ = try await api.action("community_hub","comment",["post":post,"body":text])
    text=""
    await load(reset:true)
   }.disabled(api.readOnly || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count>2000)
  }.task{await load(reset:true)}
 }
 func load(reset:Bool)async {
  do {
   let after=reset ? "0":rows.last?.id ?? "0"
   let result=Item.items(try await api.action("community_hub","comments",["post":post,"after":after]))
   if reset{rows=result}else{rows += result}
   more=result.count==100
   error=""
  } catch {rows=[];self.error=api.errorText(error)}
 }
}


struct FamilyInstallScreen:View {
 @EnvironmentObject private var api:Backend
 @Environment(\.openURL) private var openURL
 var link:URL?{var c=URLComponents(string:api.website);c?.path="/family/"+api.family.text("code")+"/";c?.queryItems=[URLQueryItem(name:"install",value:"1")];c?.fragment=nil;return c?.url}
 var body:some View{ScrollView{VStack(spacing:22){Brand().frame(maxWidth:300);Text("تطبيق "+api.family.text("name")).font(.title2.bold());Text("أيقونة مستقلة باسم العائلة وشعارها تفتح هذا الكيان مباشرة.").multilineTextAlignment(.center);Button{if let link{openURL(link)}}label:{Label("فتح Safari لإضافة أيقونة العائلة",systemImage:"square.and.arrow.up").frame(maxWidth:.infinity).padding()}.buttonStyle(.borderedProminent);Text("١. افتح صفحة العائلة في Safari.\n٢. اضغط مشاركة ثم إضافة إلى الشاشة الرئيسية.\n٣. فعّل فتح كتطبيق ويب، وتأكد من اسم العائلة ثم اضغط إضافة.").frame(maxWidth:.infinity,alignment:.leading).lineSpacing(10);Text("يتطلب الآيفون موافقتك لإضافة الأيقونة. قد يطلب تطبيق العائلة تسجيل الدخول أول مرة؛ لا تُنقل كلمة المرور أو جلسة الحساب عبر الرابط.").font(.footnote).foregroundStyle(.secondary)}.padding(24)}.navigationTitle("تطبيق العائلة")}
}
struct FamilyInstallInvitation:View {
 @EnvironmentObject private var api:Backend
 @State private var visible=false
 var body:some View{Group{if visible{HStack{NavigationLink{FamilyInstallScreen()}label:{Label("أضف أيقونة "+api.family.text("name"),systemImage:"plus.app").font(.subheadline)};Spacer();Button{visible=false;UserDefaults.standard.set(true,forKey:"family-install-offered-"+api.family.id)}label:{Image(systemName:"xmark.circle.fill").foregroundStyle(.secondary)}.accessibilityLabel("لاحقًا")}.padding(12).background(.regularMaterial)}}.task(id:api.family.id){visible=api.active && !UserDefaults.standard.bool(forKey:"family-install-offered-"+api.family.id)}}
}

func renderRequestedNews(_ pattern:String,_ fields:[String:String])->String {
 guard let regex=try? NSRegularExpression(pattern:"\\{(subject|newborn|bride_father|details|requester)\\}")else{return pattern}
 var output=pattern
 for match in regex.matches(in:pattern,range:NSRange(pattern.startIndex...,in:pattern)).reversed(){
  if let keyRange=Range(match.range(at:1),in:pattern),let range=Range(match.range,in:output){output.replaceSubrange(range,with:fields[String(pattern[keyRange])] ?? "")}
 }
 return output
}
func newsRequestStatus(_ value:String)->String {return ["pending":"بانتظار المراجعة","approved":"تم الاعتماد","published":"منشور","pending_manager":"بانتظار موافقة المدير","post_rejected":"لم يعتمد المدير النشر","rejected":"مرفوض","cancelled":"ملغى"][value] ?? value}
struct NewsRequestMenu:View {
 @EnvironmentObject private var api:Backend
 @State private var meta=Item()
 var body:some View{Section("طلبات الأخبار"){NavigationLink("طلب نشر خبر"){NewNewsRequestScreen()};NavigationLink("طلبات أخباري"){NewsRequestsScreen(review:false)};if meta.flag("writer"){NavigationLink("مراجعة طلبات الأخبار · \(meta.number("pending"))"){NewsRequestsScreen(review:true)};NavigationLink("سجل مراجعة واعتماد الأخبار"){NewsRequestHistoryScreen()}};if meta.flag("admin"){NavigationLink("أنواع الأخبار وصياغتها"){NewsTemplatesScreen()}}}.task{await load()}.onReceive(Timer.publish(every:30,on:.main,in:.common).autoconnect()){_ in Task{await load()}}}
 func load()async{if let raw=try? await api.action("news_request_action","meta")as? [String:Any]{meta=Item(raw)}}
}
struct RequestPreview:View {
 let title:String
 let text:String
 var body:some View{VStack(spacing:16){Text(title).font(.title3.bold());Text(text).lineSpacing(8).multilineTextAlignment(.center).frame(maxWidth:.infinity)}.padding(24).background{Brand().frame(maxWidth:260).opacity(0.075)}.background(brandBlue.opacity(0.04),in:RoundedRectangle(cornerRadius:18))}
}
struct NewNewsRequestScreen:View {
 @EnvironmentObject private var api:Backend
 @State private var templates:[Item]=[]
 @State private var selected=""
 @State private var subject=""
 @State private var newborn=""
 @State private var bride=""
 @State private var details=""
 @State private var requestPhotos:[RequestPhoto]=[]
 @State private var selectedRequestPhotos:[PhotosPickerItem]=[]
 @State private var smartPhoto=true
 @State private var processingPhotos=false
 @State private var requestID=UUID().uuidString
 @State private var notice=""
 @State private var error=""
 var template:Item{templates.first{$0.id==selected} ?? Item()}
 var body:some View {
  Form {
   LoadError(text:error)
   if templates.isEmpty{Text("لم يضف مدير العائلة أنواع الأخبار وصيغها بعد.")}
   else {
    Picker("عنوان الخبر / نوع الخبر",selection:$selected){ForEach(templates){t in Text(t.text("name")).tag(t.id)}}
    TextField("اسم صاحب الخبر · المعني بالخبر",text:$subject)
    if template.text("kind")=="newborn"{TextField("اسم المولود",text:$newborn)}
    if template.text("kind")=="marriage"{TextField("كريمة من · اسم والد العروس",text:$bride)}
    TextField("تفاصيل أخرى",text:$details,axis:.vertical).lineLimit(3...8)
    Section("صور الخبر · حتى خمس صور") {
     Toggle("القص الذكي حول الوجه",isOn:$smartPhoto).disabled(processingPhotos)
     Text("يمكنك تعطيل القص لإبقاء الصورة كاملة. المعالجة داخل الجهاز، والمعاينة قبل الإرسال.").font(.caption)
     if requestPhotos.count<5{PhotosPicker(selection:$selectedRequestPhotos,maxSelectionCount:5-requestPhotos.count,matching:.images){Label("إضافة صور للخبر",systemImage:"photo.on.rectangle")}.disabled(processingPhotos)}
     if processingPhotos{ProgressView("تجهيز الصور…")}
     ForEach(requestPhotos){p in VStack{if let image=UIImage(data:p.prepared){Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:260)};Text(p.cropped ? "تم القص حول الوجه":"الصورة كاملة").font(.caption);Button("إزالة الصورة"){requestPhotos.removeAll{$0.id==p.id}}.disabled(processingPhotos)}}
    }
    Section("معاينة الخبر"){RequestPreview(title:template.text("name"),text:renderRequestedNews(template.text("body"),["subject":subject,"newborn":newborn,"bride_father":bride,"details":details,"requester":api.profile.text("display_name")]))}
    TaskButton(title:"إرسال الطلب للصحفيين والمدير",symbol:"paperplane") {
     guard !processingPhotos else{throw FamilyError(text:"انتظر تجهيز الصور.")}
     var paths:[String]=[]
     do{for photo in requestPhotos{paths.append(try await api.upload(photo.prepared,bucket:"news-images",smartCrop:false))};_ = try await api.action("news_request_action","submit",["request_id":requestID,"template":selected,"subject":subject,"newborn":newborn,"bride_father":bride,"details":details,"image_paths":paths,"smart_crop_enabled":smartPhoto])}catch{if !paths.isEmpty{_ = try? await api.request("/storage/v1/object/news-images",method:"DELETE",body:["prefixes":paths])};throw error}
     requestPhotos=[]

     notice="وصل طلبك للصحفيين ومدير العائلة.";requestID=UUID().uuidString;subject="";newborn="";bride="";details=""
    }.disabled(api.readOnly || processingPhotos || subject.trimmingCharacters(in:.whitespaces).isEmpty)
   }
   if !notice.isEmpty{Text(notice).foregroundStyle(brandBlue);NavigationLink("متابعة طلباتي"){NewsRequestsScreen(review:false)}}
  }.onChange(of:selectedRequestPhotos){_,items in Task{await addRequestPhotos(items)}}.onChange(of:smartPhoto){_,_ in Task{await reprocessRequestPhotos()}}.navigationTitle("طلب نشر خبر").task{do{templates=Item.items(try await api.action("news_request_action","templates")).filter{$0.flag("enabled")};selected=templates.first?.id ?? ""}catch{self.error=api.errorText(error)}}
 }
 func addRequestPhotos(_ items:[PhotosPickerItem])async{guard !items.isEmpty,!processingPhotos else{return};processingPhotos=true;defer{processingPhotos=false;selectedRequestPhotos=[]};do{for item in items{guard requestPhotos.count<5,let data=try await item.loadTransferable(type:Data.self)else{continue};let result=try prepareSmartNewsPhoto(data,enabled:smartPhoto);requestPhotos.append(RequestPhoto(original:data,prepared:result.data,cropped:result.cropped));await Task.yield()}}catch{self.error=api.errorText(error)}}
 func reprocessRequestPhotos()async{guard !processingPhotos else{return};processingPhotos=true;defer{processingPhotos=false};do{for i in requestPhotos.indices{let result=try prepareSmartNewsPhoto(requestPhotos[i].original,enabled:smartPhoto);requestPhotos[i].prepared=result.data;requestPhotos[i].cropped=result.cropped;await Task.yield()}}catch{self.error=api.errorText(error)}}

}
struct NewsRequestsScreen:View {
 @EnvironmentObject private var api:Backend
 let review:Bool
 @State private var rows:[Item]=[]
 @State private var error=""
 @State private var more=false
 var body:some View{List{LoadError(text:error);ForEach(rows){r in VStack(alignment:.leading,spacing:12){Text(r.text("title")).font(.headline);Text(r.text("requester_name")+" · "+newsRequestStatus(r.text("display_status"))).font(.caption);RequestPreview(title:r.text("title"),text:r.text("rendered_body"));ForEach(r.raw["image_paths"]as? [String] ?? [],id:\.self){path in PrivateImage(path:path,bucket:"news-images").frame(height:220).clipped()};if !r.text("locked_name").isEmpty && dateValue(r.text("lock_expires_at"))>Date(){Text("الخبر تحت مراجعة العضو "+r.text("locked_name")).font(.caption).foregroundStyle(.orange)};if !r.text("reviewer_name").isEmpty{Text("راجعه / اعتمده: "+r.text("reviewer_name")+" · "+dateValue(r.text("reviewed_at")).formatted()).font(.caption)};if !r.text("review_note").isEmpty{Text("ملاحظة المراجع: "+r.text("review_note"))};if !r.text("post_id").isEmpty{NavigationLink("فتح الخبر"){PostDestination(postID:r.text("post_id"))}};if r.text("status")=="pending"{if review{NavigationLink("حجز ومراجعة الخبر"){NewsRequestReviewScreen(request:r)}.disabled(api.readOnly || (!api.admin && !r.text("locked_by").isEmpty && r.text("locked_by") != api.user.id && dateValue(r.text("lock_expires_at"))>Date()))}else{TaskButton(title:"إلغاء الطلب",symbol:"xmark"){_ = try await api.action("news_request_action","cancel",["id":r.id]);await load(reset:true)}.disabled(api.readOnly)}}}};if more{TaskButton(title:"طلبات أقدم",symbol:"arrow.down"){await load(reset:false)}};if rows.isEmpty && error.isEmpty{Text("لا توجد طلبات.")}}.navigationTitle(review ? "مراجعة طلبات الأخبار":"طلبات أخباري").task{await load(reset:true)}.refreshable{await load(reset:true)}}
 func load(reset:Bool)async{do{let result=Item.items(try await api.action("news_request_action","list",["review":review,"offset":reset ? 0:rows.count]));if reset{rows=result}else{rows += result};more=result.count==30;error=""}catch{self.error=api.errorText(error)}}
}
struct NewsRequestReviewScreen:View {
 @EnvironmentObject private var api:Backend
 @Environment(\.dismiss)private var dismiss
 let request:Item
 @State private var title=""
 @State private var text=""
 @State private var term=""
 @State private var results:[Item]=[]
 @State private var chosen:[Item]=[]
 @State private var mentionRequester=false
 @State private var note=""
 @State private var publishedPost=""
 @State private var notice=""
 @State private var finished=false
 @State private var claimed=false
 @State private var lockError=""
 var body:some View {
  Form {
   if !lockError.isEmpty{LoadError(text:lockError)}
   if finished{Text(notice);if !publishedPost.isEmpty{NavigationLink("فتح الخبر"){PostDestination(postID:publishedPost)}}}
   else {
    Text("طالب الخبر: "+request.text("requester_name"))
    Text(claimed ? "الطلب محجوز لك. يتحرر بعد 15 دقيقة دون نشاط.":"جاري حجز المراجعة…").font(.caption).foregroundStyle(.orange)
    ForEach(request.raw["image_paths"]as? [String] ?? [],id:\.self){path in PrivateImage(path:path,bucket:"news-images").frame(height:260).clipped()}
    Text(request.flag("smart_crop_enabled") ? "القص الذكي مسموح من صاحب الطلب":"صاحب الطلب أوقف القص الذكي").font(.caption)
    TextField("عنوان النشر",text:$title).disabled(!claimed)
    TextField("الصيغة النهائية",text:$text,axis:.vertical).lineLimit(6...16).disabled(!claimed)
    RequestPreview(title:title,text:text)
    Toggle("منشن مباشر لطالب الخبر",isOn:$mentionRequester)
    Section("إضافة منشن لأعضاء العائلة") {
     TextField("الاسم أو رقم الجوال أو @الاسم",text:$term)
     ForEach(results){p in Button(p.text("display_name")){if !chosen.contains(where:{$0.id==p.id}) && chosen.count<20{chosen.append(p)};term="";results=[]}}
     ForEach(chosen){p in Button("✕ "+p.text("display_name")){chosen.removeAll{$0.id==p.id}}}
    }
    Text("تطبق موافقة المدير على أخبار الصحفي وفق إعدادات العائلة.").font(.caption).foregroundStyle(.secondary)
    TaskButton(title:"حفظ مسودة المراجعة",symbol:"square.and.arrow.down"){_ = try await api.action("news_request_action","draft",reviewPayload());notice="حُفظت المسودة باسمك."}.disabled(api.readOnly || !claimed)
    TaskButton(title:"ترك المراجعة وإتاحة الطلب",symbol:"lock.open"){_ = try await api.action("news_request_action","release",["id":request.id]);dismiss()}.disabled(!claimed)
    TaskButton(title:"اعتماد وإرسال للنشر",symbol:"checkmark") {
     let result=Item(try await api.action("news_request_action","approve",["id":request.id,"title":title,"body":text,"mention_requester":mentionRequester,"mentions":chosen.map{$0.id}])as? [String:Any] ?? [:])
     finished=true;publishedPost=result.flag("published") ? result.text("post_id"):"";notice=result.flag("published") ? "اعتمد الخبر ونُشر.":"وصل الخبر إلى المدير للموافقة النهائية."
    }.disabled(api.readOnly || !claimed)
    Section("رفض الطلب") {TextField("سبب الرفض (اختياري)",text:$note);TaskButton(title:"رفض الطلب",symbol:"xmark"){_ = try await api.action("news_request_action","reject",["id":request.id,"note":note]);finished=true;notice="رُفض الطلب."}.disabled(api.readOnly || !claimed)}
   }
  }.navigationTitle("مراجعة الخبر").task{await claimRequest()}.onReceive(Timer.publish(every:60,on:.main,in:.common).autoconnect()){_ in if claimed && !finished{Task{do{_ = try await api.action("news_request_action","renew",["id":request.id])}catch{claimed=false;lockError=api.errorText(error)}}}}.task(id:term){do{try await Task.sleep(nanoseconds:250_000_000);let query=term.hasPrefix("@") ? String(term.dropFirst()):term;if query.isEmpty{results=[];return};let rows=Item.items(try await api.action("news_request_action","mention_search",["term":query]));try Task.checkCancellation();results=rows}catch{}}
 }
 func reviewPayload()->[String:Any]{["id":request.id,"title":title,"body":text,"mention_requester":mentionRequester,"mentions":chosen.map{$0.id}]}
 func claimRequest()async{do{let response=Item(try await api.action("news_request_action","claim",["id":request.id])as? [String:Any] ?? [:]);let draft=response.child("review_draft");title=draft.text("title").isEmpty ? request.text("title"):draft.text("title");text=draft.text("body").isEmpty ? request.text("rendered_body"):draft.text("body");mentionRequester=draft.flag("mention_requester");if let ids=draft.raw["mentions"]as? [String],!ids.isEmpty{chosen=try await api.table("profiles",[q("select","id,display_name"),q("id","in.("+ids.joined(separator:",")+")")])};claimed=true;lockError=""}catch{claimed=false;lockError=api.errorText(error)}}

}
struct NewsTemplatesScreen:View {
 @EnvironmentObject private var api:Backend
 @State private var rows:[Item]=[]
 @State private var error=""
 @State private var editing:Item?
 var body:some View{List{LoadError(text:error);Button("＋ إضافة نوع خبر وصياغته"){editing=Item(["id":"new"])};ForEach(rows){t in Button{editing=t}label:{VStack(alignment:.leading,spacing:8){Text(t.text("name")+(t.flag("enabled") ? "":" · موقوف")).font(.headline);Text(t.text("body")).font(.caption)}}}}.navigationTitle("أنواع الأخبار والصيغ").task{await load()}.sheet(item:$editing){t in NavigationStack{NewsTemplateEditor(template:t){await load()}}}}
 func load()async{do{rows=Item.items(try await api.action("news_request_action","templates"));error=""}catch{self.error=api.errorText(error)}}
}
struct NewsTemplateEditor:View {
 @EnvironmentObject private var api:Backend
 @Environment(\.dismiss)private var dismiss
 let template:Item
 let saved:()async->Void
 @State private var name=""
 @State private var kind="general"
 @State private var pattern=""
 @State private var templateSelection=NSRange(location:0,length:0)
 @State private var enabled=true
 let fields=[("subject","اسم صاحب الخبر"),("newborn","اسم المولود"),("bride_father","كريمة من"),("details","تفاصيل أخرى"),("requester","اسم طالب الخبر")]
 var body:some View {
  Form {
   TextField("١. اسم نوع الخبر الظاهر بالقائمة",text:$name)
   Picker("نوع الخبر",selection:$kind){Text("عام").tag("general");Text("مولود جديد").tag("newborn");Text("عقد قران").tag("marriage")}
   Text("٢. اكتب الصيغة واضغط موضع ظهور بيانات الطلب، ثم اختر الحقل أدناه لإدراجه في نفس المكان.").font(.subheadline)
   TemplatePatternEditor(text:$pattern,selection:$templateSelection).frame(minHeight:190).accessibilityLabel("صياغة الخبر وتحديد مواضع البيانات")
   Section("٣. إدراج بيانات الطلب عند المؤشر"){ForEach(fields,id:\.0){key,label in Button("＋ "+label){insertField(key)}}}
   Toggle("إتاحة النوع للأعضاء",isOn:$enabled)
   RequestPreview(title:name,text:renderRequestedNews(pattern,["subject":"أحمد علي","newborn":"علي","bride_father":"محمد حسن","details":"تفاصيل الخبر هنا","requester":"طالب الخبر"]))
   TaskButton(title:"حفظ وإضافة النوع لقائمة الأخبار",symbol:"checkmark") {
    var payload:[String:Any]=["name":name,"kind":kind,"body":pattern,"enabled":enabled]
    if template.id != "new"{payload["id"]=template.id}
    _ = try await api.action("news_request_action","template_save",payload)
    await saved();dismiss()
   }.disabled(api.readOnly)
  }.navigationTitle("نوع الخبر وصياغته").toolbar{Button("إغلاق"){dismiss()}}.onAppear{name=template.text("name");kind=template.text("kind").isEmpty ? "general":template.text("kind");pattern=template.text("body").isEmpty ? "تتقدم العائلة بالتهنئة إلى {subject}\n{details}":template.text("body");enabled=template.id=="new" || template.flag("enabled")}
 }
 func insertField(_ key:String){let value=NSMutableString(string:pattern);let start=min(max(0,templateSelection.location),value.length);let length=min(max(0,templateSelection.length),value.length-start);let token="{"+key+"}";value.replaceCharacters(in:NSRange(location:start,length:length),with:token);pattern=value as String;templateSelection=NSRange(location:start+(token as NSString).length,length:0)}

}

struct TemplatePatternEditor:UIViewRepresentable {
 @Binding var text:String
 @Binding var selection:NSRange
 func makeCoordinator()->Coordinator{Coordinator(self)}
 func makeUIView(context:Context)->UITextView{let view=UITextView();view.font=UIFont.preferredFont(forTextStyle:.body);view.adjustsFontForContentSizeCategory=true;view.backgroundColor=UIColor.secondarySystemBackground;view.layer.cornerRadius=12;view.textContainerInset=UIEdgeInsets(top:12,left:12,bottom:12,right:12);view.textAlignment = .right;view.delegate=context.coordinator;return view}
 func updateUIView(_ view:UITextView,context:Context){context.coordinator.updating=true;defer{context.coordinator.updating=false};context.coordinator.parent=self;if view.text != text{view.text=text};let start=min(max(0,selection.location),(text as NSString).length);let length=min(max(0,selection.length),(text as NSString).length-start);let range=NSRange(location:start,length:length);if view.selectedRange != range{view.selectedRange=range}}
 class Coordinator:NSObject,UITextViewDelegate {
  var parent:TemplatePatternEditor
  var updating=false
  init(_ parent:TemplatePatternEditor){self.parent=parent}
  func textViewDidChange(_ view:UITextView){guard !updating else{return};parent.text=view.text;parent.selection=view.selectedRange}
  func textViewDidChangeSelection(_ view:UITextView){guard !updating else{return};if parent.selection != view.selectedRange{parent.selection=view.selectedRange}}
 }
}

struct RequestPhoto:Identifiable{let id=UUID().uuidString;let original:Data;var prepared:Data;var cropped:Bool}
struct NewsRequestHistoryScreen:View {
 @EnvironmentObject private var api:Backend
 @State private var rows:[Item]=[]
 @State private var more=false
 @State private var error=""
 let names=["submitted":"إرسال الطلب","claimed":"حجز المراجعة","manager_takeover":"تولي المراجعة بواسطة المدير","draft_saved":"حفظ مسودة","released":"ترك المراجعة","approved":"اعتماد الخبر","published":"نشر الخبر","published_legacy":"نشر سابق","sent_for_approval":"إرسال لموافقة المدير","rejected":"رفض الطلب","cancelled":"إلغاء الطلب"]
 var body:some View{List{LoadError(text:error);ForEach(rows){r in VStack(alignment:.leading,spacing:8){Text(r.text("title")).font(.headline);Text((names[r.text("event")] ?? r.text("event"))+" · "+r.text("actor_name"));Text(dateValue(r.text("created_at")),format:.dateTime.year().month().day().hour().minute()).font(.caption);if !r.text("post_id").isEmpty{NavigationLink("فتح الخبر"){PostDestination(postID:r.text("post_id"))}}}};if more{TaskButton(title:"سجل أقدم",symbol:"arrow.down"){await load(reset:false)}}}.navigationTitle("سجل مراجعة واعتماد الأخبار").task{await load(reset:true)}.refreshable{await load(reset:true)}}
 func load(reset:Bool)async{do{let result=Item.items(try await api.action("news_request_action","history",["offset":reset ? 0:rows.count]));if reset{rows=result}else{rows += result};more=result.count==50;error=""}catch{self.error=api.errorText(error)}}
}

struct SquareMentionPicker:View{
 @EnvironmentObject private var api:Backend
 @Binding var text:String
 @Binding var selected:[Item]
 @State private var term=""
 @State private var rows:[Item]=[]
 var body:some View{VStack(alignment:.leading){TextField("@ ابحث عن عضو للمنشن",text:$term);ForEach(selected){m in Button("@"+m.text("display_name")+" ×"){selected.removeAll{$0.id==m.id}}.font(.caption)};ForEach(rows.prefix(10)){m in Button(m.text("display_name")){guard selected.count<30 else{return};selected.append(m);text += " @"+m.text("display_name");term="";rows=[]}}}.task(id:term){do{try await Task.sleep(nanoseconds:220_000_000);guard !term.isEmpty else{rows=[];return};let result=Item.items(try await api.action("community_hub","search",["term":term]));try Task.checkCancellation();rows=result.filter{m in !selected.contains{$0.id==m.id}}}catch{}}}
}
struct FamilyPauseControl:View{
 @EnvironmentObject private var api:Backend
 @State private var confirm=false
 var body:some View{Form{Text("يوقف دخول جميع أعضاء العائلة مؤقتًا. يمكنك إعادة التشغيل من شاشة الإيقاف.");Button("إيقاف الكيان بالكامل",role:.destructive){confirm=true}}.navigationTitle("إيقاف الكيان").confirmationDialog("إيقاف دخول جميع الأعضاء؟",isPresented:$confirm){Button("إيقاف الكيان",role:.destructive){Task{do{_ = try await api.rpc("family_pause",["paused":true]);try await api.loadAccount()}catch{api.warning=api.errorText(error)}}}}}
}
struct FamilyPausedScreen:View{
 @EnvironmentObject private var api:Backend
 var body:some View{NavigationStack{VStack(spacing:24){Brand();Image(systemName:"pause.circle").font(.system(size:48));Text("تم ايقاف الكيان بالكامل مؤقتاً").font(.title3).multilineTextAlignment(.center);if api.family.flag("can_resume"){TaskButton(title:"إعادة تشغيل الكيان",symbol:"play.circle"){_ = try await api.rpc("family_pause",["paused":false]);try await api.loadAccount()};NavigationLink("الدعم الفني"){SupportScreen()}};TaskButton(title:"تحديث الحالة",symbol:"arrow.clockwise"){try await api.loadAccount()};TaskButton(title:"تسجيل الخروج",symbol:"rectangle.portrait.and.arrow.right"){await api.logout()}}.padding()}}
}
struct SupportScreen:View{
 @EnvironmentObject private var api:Backend
 var platform=false
 @State private var rows:[Item]=[]
 @State private var subject=""
 @State private var detail=""
 @State private var error=""
 func call(_ action:String,_ payload:[String:Any]=[:])async throws->Any{var p=payload;p["platform"]=platform;return try await api.action("support_action",action,p)}
 func load()async{do{rows=Item.items(try await call("list"));error=""}catch{self.error=api.errorText(error)}}
 var body:some View{List{LoadError(text:error);if !platform{Section("طلب دعم جديد"){TextField("عنوان الطلب",text:$subject);TextField("اشرح المشكلة…",text:$detail,axis:.vertical).lineLimit(3...8);TaskButton(title:"إرسال طلب الدعم",symbol:"paperplane"){_ = try await call("create",["subject":subject,"body":detail]);subject="";detail="";await load()}.disabled(subject.count<3 || subject.count>200 || detail.isEmpty || detail.count>5000)}};ForEach(rows){t in NavigationLink{SupportThreadScreen(ticket:t,platform:platform)}label:{VStack(alignment:.leading,spacing:6){Text(t.text("subject")).font(.headline);if platform{Text(t.text("family_name")+" · "+t.text("family_code"))};Text(t.text("status")=="closed" ? "مغلق":"مفتوح").font(.caption);Text(t.flag("last_from_platform") ? "آخر رد من إدارة المنصة":"آخر رسالة من مدير العائلة").font(.caption).foregroundStyle(.secondary)}}}}.navigationTitle("الدعم الفني").task{await load()}.refreshable{await load()}.onReceive(Timer.publish(every:15,on:.main,in:.common).autoconnect()){_ in Task{await load()}}}
}
struct SupportThreadScreen:View{
 @EnvironmentObject private var api:Backend
 let ticket:Item
 var platform=false
 @State private var rows:[Item]=[]
 @State private var text=""
 @State private var error=""
 @State private var more=false
 func call(_ action:String,_ payload:[String:Any]=[:])async throws->Any{var p=payload;p["ticket"]=ticket.id;p["platform"]=platform;return try await api.action("support_action",action,p)}
 func load(reset:Bool)async{do{let result=Item.items(try await call("messages",["after":reset ? "0":rows.last?.id ?? "0"]));if reset{rows=result}else{rows += result};more=result.count==100;error=""}catch{self.error=api.errorText(error)}}
 var body:some View{ScrollView{LazyVStack(alignment:.leading,spacing:12){LoadError(text:error);ForEach(rows){m in VStack(alignment:.leading,spacing:8){Text(m.flag("from_platform") ? "إدارة المنصة":"مدير العائلة").font(.caption.bold());Text(m.text("body")).textSelection(.enabled);Text(m.text("created_at").replacingOccurrences(of:"T",with:" ").prefix(16)).font(.caption2).foregroundStyle(.secondary)}.padding().frame(maxWidth:.infinity,alignment:.leading).background(m.flag("from_platform") ? brandBlue.opacity(0.12):Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:14))};if more{TaskButton(title:"رسائل أخرى",symbol:"arrow.down"){await load(reset:false)}};TextField("اكتب ردك…",text:$text,axis:.vertical).lineLimit(2...8).textFieldStyle(.roundedBorder);TaskButton(title:"إرسال الرد",symbol:"paperplane"){_ = try await call("reply",["body":text]);text="";await load(reset:true)}.disabled(text.isEmpty || text.count>5000);TaskButton(title:"إغلاق الطلب",symbol:"checkmark"){_ = try await call("close")}}.padding()}.navigationTitle(ticket.text("subject")).task{await load(reset:true)}.refreshable{await load(reset:true)}.onReceive(Timer.publish(every:10,on:.main,in:.common).autoconnect()){_ in if !more{Task{await load(reset:false)}}}}
}
