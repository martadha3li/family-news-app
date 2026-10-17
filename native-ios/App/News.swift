import SwiftUI
import PhotosUI

enum NewsScope:String,CaseIterable {case published="الأخبار",drafts="مسوداتي",review="مراجعة الأخبار",hidden="الأخبار المخفية",mentioned="أخبار ذُكرت فيها"}
struct NewsScreen:View {
    @EnvironmentObject private var api:Backend
    var scope:NewsScope = .published
    @State private var posts:[Item]=[],ads:[Item]=[]
    @State private var error=""
    @State private var now=Date()
    @State private var loading=false,more=true
    @State private var editor:Item?,details:Item?
    var body:some View{ScrollView{LazyVStack(spacing:18){if scope == .published{ForEach(activeAds){ad in Button{details=ad}label:{HStack{Image(systemName:ad.text("category")=="death" ? "leaf":"megaphone");Text(ad.text("title")).font(.subheadline.bold());Spacer();Image(systemName:"chevron.left").font(.caption)}.foregroundStyle(adColor(ad)).padding(14).background(adColor(ad).opacity(0.08),in:RoundedRectangle(cornerRadius:14))}.padding(.horizontal)}}
        LoadError(text:error)
        if posts.isEmpty && !loading{EmptyState(title:"لا توجد أخبار هنا بعد",symbol:"newspaper")}
        ForEach(posts){p in NativePost(post:p,edit:{editor=p},refresh:{await load(reset:true)},scope:scope)}
        if loading{ProgressView().padding()}
        if more && !posts.isEmpty{TaskButton(title:"عرض أخبار أقدم",symbol:"arrow.down"){await load(reset:false)}}
    }.padding(.vertical,12).frame(maxWidth:620).frame(maxWidth:.infinity)}.scrollIndicators(.hidden).background(Color(.systemGroupedBackground)).refreshable{await load(reset:true)}.navigationTitle(scope == .published ? "":scope.rawValue).navigationBarTitleDisplayMode(.inline).toolbar{if scope == .published{ToolbarItem(placement:.principal){Brand()}};if api.writer{ToolbarItem(placement:.navigationBarTrailing){Button{editor=Item(["id":"new"])}label:{Image(systemName:"plus.app").font(.title3)}.accessibilityLabel("نشر خبر")}}}.task{await load(reset:true);while !Task.isCancelled{do{try await Task.sleep(nanoseconds:10_000_000_000)}catch{break};now=Date()}}.sheet(item:$editor){post in NavigationStack{PostEditor(post:post.id=="new" ? nil:post){await load(reset:true)}}}.sheet(item:$details){ad in NavigationStack{ScrollView{VStack(alignment:.leading,spacing:20){Text(ad.text("title")).font(.title2.bold());Text(ad.text("body"));Text("حتى \(dateValue(ad.text("ends_at")).formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)}.padding()}.scrollIndicators(.hidden).navigationTitle("تفاصيل الإعلان").toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){details=nil}}}}}}
    var activeAds:[Item]{ads.filter{$0.flag("enabled") && dateValue($0.text("starts_at"))<=now && dateValue($0.text("ends_at"))>now}}
    func adColor(_ ad:Item)->Color{switch ad.text("category"){case "death":return .gray;case "urgent":return .red;case "wedding","donation":return brandPink;default:return brandBlue}}
    func load(reset:Bool)async{if loading{return};loading=true;defer{loading=false};do{var query=[q("select","*,profiles:profiles!posts_author_id_fkey(display_name,avatar_path),likes(count),comments(count)"),q("order","created_at.desc,id.desc"),q("limit","20"),q("offset",reset ? "0":String(posts.count))];switch scope{case .published:query += [q("published","eq.true"),q("deleted_at","is.null")];case .drafts:query += [q("published","eq.false"),q("author_id","eq."+api.user.id),q("deleted_at","is.null")];case .review:query += [q("moderation_status","eq.pending"),q("deleted_at","is.null")];case .hidden:query += [q("deleted_at","not.is.null")];case .mentioned:query += [q("mentioned_member_ids","cs.{"+api.user.id+"}"),q("published","eq.true"),q("deleted_at","is.null")]} ;let rows=try await api.table("posts",query);if reset{posts=rows}else{posts += rows};more=rows.count==20;error="";if scope == .published{ads=try await api.table("announcements",[q("select","*"),q("enabled","eq.true"),q("limit","200"),q("order","starts_at.desc")])}}catch{self.error=api.errorText(error)}}
}
struct NativePost:View {
    @EnvironmentObject private var api:Backend
    let post:Item
    let edit:()->Void
    let refresh:()async->Void
    var scope:NewsScope
    @State private var liked=false
    @State private var count=0
    @State private var comments=false,confirmDelete=false
    @State private var issue=""
    var editable:Bool{api.admin || (api.writer && post.text("author_id")==api.user.id)}
    var body:some View{VStack(alignment:.leading,spacing:0){HStack(spacing:10){Avatar(path:post.child("profiles").text("avatar_path"),name:post.child("profiles").text("display_name"));VStack(alignment:.leading,spacing:3){Text(post.child("profiles").text("display_name")).font(.subheadline.weight(.semibold));Text(dateValue(post.text("created_at")),style:.date).font(.caption2).foregroundStyle(.secondary)};Spacer();if editable{Menu{Button("تعديل الخبر",systemImage:"pencil"){edit()};Button(scope == .hidden ? "استعادة الخبر":"إخفاء الخبر",systemImage:scope == .hidden ? "arrow.uturn.backward":"eye.slash"){Task{do{_ = try await api.table("posts",[q("id","eq."+post.id)],method:"PATCH",body:["deleted_at":scope == .hidden ? NSNull():ISO8601DateFormatter().string(from:Date())]);await refresh()}catch{issue=api.errorText(error)}}};if api.admin{Button("حذف نهائي",systemImage:"trash",role:.destructive){confirmDelete=true}}}label:{Image(systemName:"ellipsis").frame(width:44,height:44)}}}.padding(.horizontal,14).padding(.vertical,10)
        if !post.text("image_path").isEmpty{PrivateImage(path:post.text("image_path"),bucket:"news-images",fill:false).aspectRatio(4/5,contentMode:.fit)}
        HStack(spacing:20){TaskButton(title:String(count),symbol:liked ? "heart.fill":"heart"){if liked{_ = try await api.table("likes",[q("post_id","eq."+post.id),q("user_id","eq."+api.user.id)],method:"DELETE")}else{_ = try await api.table("likes",method:"POST",body:["post_id":post.id,"user_id":api.user.id])};liked.toggle();count += liked ? 1 : -1}.foregroundStyle(liked ? brandPink:Color.primary).accessibilityLabel(liked ? "إلغاء الإعجاب":"إعجاب");Button{comments=true}label:{Label(String(post.rows("comments").first?.number("count") ?? 0),systemImage:"bubble.right")}.accessibilityLabel("تعليقات الخبر");Spacer()}.font(.title3).buttonStyle(.plain).padding(.horizontal,16).padding(.vertical,7)
        VStack(alignment:.leading,spacing:6){Text(post.text("title")).font(.subheadline.bold());Text(post.text("body")).font(.subheadline).lineSpacing(4).textSelection(.enabled);if !post.flag("published"){Text(post.text("moderation_status")=="pending" ? "بانتظار موافقة المدير":"مسودة").font(.caption).foregroundStyle(brandPink)};if scope == .review && api.admin{HStack{TaskButton(title:"اعتماد ونشر",symbol:"checkmark"){_ = try await api.table("posts",[q("id","eq."+post.id)],method:"PATCH",body:["published":true,"moderation_status":"published"]);await refresh()};TaskButton(title:"رفض",symbol:"xmark"){_ = try await api.table("posts",[q("id","eq."+post.id)],method:"PATCH",body:["published":false,"moderation_status":"rejected"]);await refresh()}}.buttonStyle(.bordered)}}.padding(.horizontal,16).padding(.bottom,18)
    }.background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius:14)).sheet(isPresented:$comments){NavigationStack{CommentsScreen(post:post)}}.task(id:post.id){count=post.rows("likes").first?.number("count") ?? 0;do{liked = !(try await api.table("likes",[q("select","user_id"),q("post_id","eq."+post.id),q("user_id","eq."+api.user.id)])).isEmpty}catch{}}
    .alert("حذف الخبر نهائيًا؟",isPresented:$confirmDelete){Button("إلغاء",role:.cancel){};Button("حذف",role:.destructive){Task{do{let rows=try await api.table("posts",[q("id","eq."+post.id)],method:"DELETE");guard !rows.isEmpty else{throw FamilyError(text:"لم يتم حذف الخبر.")};let path=post.text("image_path");if !path.isEmpty{let shared=try await api.table("posts",[q("select","id"),q("image_path","eq."+path),q("limit","1")]);if shared.isEmpty{_ = try? await api.request("/storage/v1/object/news-images",method:"DELETE",body:["prefixes":[path]])}};await refresh()}catch{issue=api.errorText(error)}}}}message:{Text("سيُحذف الخبر وتعليقاته وإعجاباته، ولا يمكن استعادته.")}.alert("تعذّر إكمال الطلب",isPresented:Binding(get:{!issue.isEmpty},set:{if !$0{issue=""}})){Button("حسنًا",role:.cancel){}}message:{Text(issue)}}
}
struct CommentsScreen:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss) private var dismiss
    let post:Item
    @State private var rows:[Item]=[],bodyText="",error=""
    @State private var more=true
    func load(reset:Bool=true)async {
        do {
            let r=try await api.table("comments",[q("select","id,body,author_id,created_at,profiles:profiles!comments_author_id_fkey(display_name)"),q("post_id","eq."+post.id),q("order","created_at.asc,id.asc"),q("limit","50"),q("offset",reset ? "0":String(rows.count))])
            if reset {rows=r} else {rows += r};more=r.count==50;error=""
        } catch {self.error=api.errorText(error)}
    }
    var body:some View {
        List {
            LoadError(text:error)
            ForEach(rows) {r in
                VStack(alignment:.leading,spacing:7) {
                    Text(r.child("profiles").text("display_name")).font(.subheadline.bold())
                    Text(r.text("body")).font(.subheadline)
                    Text(dateValue(r.text("created_at")),style:.date).font(.caption2).foregroundStyle(.secondary)
                }.swipeActions {
                    if api.admin || r.text("author_id")==api.user.id {
                        Button("حذف",role:.destructive) {
                            Task {do {_ = try await api.table("comments",[q("id","eq."+r.id)],method:"DELETE");await load()} catch {self.error=api.errorText(error)}}
                        }
                    }
                }
            }
            if more {TaskButton(title:"تعليقات أقدم"){await load(reset:false)}}
        }.listStyle(.plain).scrollIndicators(.hidden)
        .safeAreaInset(edge:.bottom) {
            HStack {
                TextField("أضف تعليقًا…",text:$bodyText,axis:.vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                TaskButton(title:"",symbol:"paperplane.fill") {
                    let text=bodyText.trimmingCharacters(in:.whitespacesAndNewlines)
                    guard !text.isEmpty,text.count<=2000 else{return}
                    _ = try await api.table("comments",method:"POST",body:["post_id":post.id,"author_id":api.user.id,"body":text]);bodyText="";await load()
                }.disabled(bodyText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityLabel("إرسال التعليق")
            }.padding().background(.bar)
        }.navigationTitle("التعليقات").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItem(placement:.cancellationAction){Button("إغلاق"){dismiss()}}}
        .task {await load()}
    }
}
struct PostEditor:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss) private var dismiss
    let post:Item?
    let saved:()async->Void
    @State private var title:String,bodyText:String,publish:Bool
    @State private var photo:PhotosPickerItem?,imageData:Data?
    @State private var search="",people:[Item]=[],selected:[Item]=[]
    @State private var imageError=""
    init(post:Item?,saved:@escaping ()async->Void){self.post=post;self.saved=saved;_title=State(initialValue:post?.text("title") ?? "");_bodyText=State(initialValue:post?.text("body") ?? "");_publish=State(initialValue:post?.flag("published") ?? true)}
    var body:some View{Form{Section("الخبر"){TextField("عنوان الخبر",text:$title);TextField("التفاصيل",text:$bodyText,axis:.vertical).lineLimit(5...15);Toggle("نشر الخبر الآن",isOn:$publish)};Section("الصورة"){PhotosPicker(selection:$photo,matching:.images){Label("اختيار صورة",systemImage:"photo")}.disabled(post != nil && post?.text("author_id") != api.user.id);if let data=imageData,let img=UIImage(data:data){Image(uiImage:img).resizable().scaledToFit().frame(maxHeight:240)};LoadError(text:imageError);Text("تُضغط الصورة قبل الرفع وتُعرض بإطار 4:5.").font(.caption).foregroundStyle(.secondary)};Section("منشن لأعضاء العائلة"){TextField("ابحث بالاسم",text:$search).task(id:search){do{try await Task.sleep(nanoseconds:250_000_000);try Task.checkCancellation();guard search.count>=2 else{people=[];return};let r=try await api.table("profiles",[q("select","id,display_name"),q("status","eq.active"),q("display_name","ilike.*"+search.replacingOccurrences(of:"*",with:"")+"*"),q("limit","20")]);try Task.checkCancellation();people=r}catch{}};ForEach(people){p in Button{if selected.count<20 && !selected.contains(where:{$0.id==p.id}){selected.append(p)}}label:{Label(p.text("display_name"),systemImage:selected.contains(where:{$0.id==p.id}) ? "checkmark.circle.fill":"at")}};ForEach(selected){p in Button(role:.destructive){selected.removeAll{$0.id==p.id}}label:{Label(p.text("display_name"),systemImage:"minus.circle")}}};Section{TaskButton(title:"حفظ الخبر",symbol:"checkmark"){guard api.writer,title.trimmingCharacters(in:.whitespaces).count>=3,title.count<=250,!bodyText.trimmingCharacters(in:.whitespaces).isEmpty,bodyText.count<=20000 else{throw FamilyError(text:"أدخل عنوانًا صالحًا وتفاصيل الخبر.")};var values:[String:Any]=["title":title,"body":bodyText,"published":publish,"mentioned_member_ids":selected.map(\.id)];var uploaded:String?;do{if let data=imageData{uploaded=try await api.upload(data,bucket:"news-images");values["image_path"]=uploaded};if let p=post{_ = try await api.table("posts",[q("id","eq."+p.id)],method:"PATCH",body:values)}else{values["author_id"]=api.user.id;_ = try await api.table("posts",method:"POST",body:values)}}catch{if let path=uploaded{_ = try? await api.request("/storage/v1/object/news-images",method:"DELETE",body:["prefixes":[path]])};throw error};await saved();dismiss()}.disabled(!api.writer)}}.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).navigationTitle(post==nil ? "خبر جديد":"تعديل الخبر").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("إلغاء"){dismiss()}}}.onChange(of:photo){item in Task{do{guard let data=try await item?.loadTransferable(type:Data.self),data.count<=20*1024*1024,UIImage(data:data) != nil else{throw FamilyError(text:"اختر صورة صالحة أقل من 20 ميجابايت.")};imageData=data;imageError=""}catch{imageError=api.errorText(error)}}}.task{if let ids=post?.raw["mentioned_member_ids"] as? [String],!ids.isEmpty{selected=(try? await api.table("profiles",[q("select","id,display_name"),q("id","in.("+ids.joined(separator:",")+")")])) ?? []}}}
}
