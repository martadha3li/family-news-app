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
    var summary:some View{VStack(alignment:.leading,spacing:12){HStack(spacing:22){Avatar(path:profile.text("avatar_path"),name:profile.text("display_name"),size:84);HStack{stat("منشورات","posts");stat("متابعون","followers");stat("يتابع","following_count")}.frame(maxWidth:.infinity)};Text(profile.text("display_name")).font(.subheadline.bold());if !profile.text("bio").isEmpty{Text(profile.text("bio")).font(.subheadline).textSelection(.enabled)};if member != api.user.id && !profile.id.isEmpty{TaskButton(title:profile.flag("following") ? "تتابعه ✓":"متابعة",symbol:profile.flag("following") ? "person.badge.minus":"person.badge.plus"){profile=Item(try await call(profile.flag("following") ? "unfollow":"follow")as? [String:Any] ?? [:])}.buttonStyle(.borderedProminent).disabled(api.readOnly);Text("تصلك تنبيهات عند نشره خبرًا أو ذكره في خبر.").font(.caption).foregroundStyle(.secondary)}}.padding(18)}
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
struct MoreScreen:View {@EnvironmentObject private var api:Backend;@State private var logout=false;@State private var wholeTreeVisible=false;var body:some View{List{Section{Brand().frame(maxWidth:.infinity).padding(.vertical,15);Text(api.family.text("name")).font(.headline);Text("أخبارنا تجمعنا").font(.caption).foregroundStyle(.secondary)};if api.active{if wholeTreeVisible || api.admin{NavigationLink("شجرة العائلة"){WholeFamilyTreeScreen()}};NavigationLink("الإشعارات"){NotificationsScreen()}};if api.writer{NavigationLink("مسوداتي"){NewsScreen(scope:.drafts)}};if api.admin{Section("إدارة العائلة"){NavigationLink("لوحة إدارة العائلة"){FamilyAdminDashboard()};NavigationLink("إدارة الأعضاء"){MembersScreen()};NavigationLink("مراجعة الأخبار"){NewsScreen(scope:.review)};NavigationLink("الأخبار المخفية"){NewsScreen(scope:.hidden)};NavigationLink("الإعلانات"){AdsAdminScreen()};NavigationLink("إعدادات العائلة والدردشة"){SettingsScreen()};NavigationLink("خيارات صلة القرابة"){KinshipAdminScreen()};NavigationLink("طلبات تغيير الجوال"){PhoneRequestsScreen()};NavigationLink("البيانات والمساحة"){StorageScreen()}}};Section{Button("الخروج من الكيان العائلي",role:.destructive){Task{await api.exitFamily()}};Button("تسجيل الخروج من الحساب فقط",role:.destructive){logout=true}}}.scrollIndicators(.hidden).navigationTitle("المزيد").task{if api.active{wholeTreeVisible=Item((try? await api.action("whole_tree","settings"))as? [String:Any] ?? [:]).flag("enabled")}}.confirmationDialog("تسجيل الخروج؟",isPresented:$logout){Button("تسجيل الخروج",role:.destructive){Task{await api.logout()}}}}}
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
