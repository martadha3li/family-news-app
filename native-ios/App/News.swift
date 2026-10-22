import SwiftUI
import PhotosUI
import UIKit

enum NewsScope:String,CaseIterable {case published="الأخبار",drafts="مسوداتي",review="مراجعة الأخبار",hidden="الأخبار المخفية",mentioned="أخبار ذُكرت فيها"}
struct NewsScreen:View {
    @EnvironmentObject private var api:Backend
    var scope:NewsScope = .published
    @State private var posts:[Item]=[]
    @State private var ads:[Item]=[]
    @State private var error=""
    @State private var now=Date()
    @State private var notifications=false
    @State private var loading=false
    @State private var more=true
    @State private var requestNews=false
    @State private var editor:Item?
    @State private var details:Item?
    var body:some View{ScrollView{LazyVStack(spacing:16){
        LoadError(text:error)
        if posts.isEmpty && !loading{EmptyState(title:"لا توجد أخبار هنا بعد",symbol:"newspaper")}
        ForEach(posts){p in NativePost(post:p,edit:{editor=p},refresh:{await load(reset:true)},scope:scope)}
        if loading{ProgressView().padding()}
        if more && !posts.isEmpty{TaskButton(title:"عرض أخبار أقدم",symbol:"arrow.down"){await load(reset:false)}}
    }.padding(.horizontal,5).padding(.vertical,8).frame(maxWidth:620).frame(maxWidth:.infinity)}.scrollIndicators(.hidden).safeAreaInset(edge:.top,spacing:0){if scope == .published && !activeAds.isEmpty{AnnouncementTabs(ads:activeAds,open:{details=$0})}}.background(Color(.systemGroupedBackground)).refreshable{await load(reset:true)}.navigationTitle(scope == .published ? "":scope.rawValue).navigationBarTitleDisplayMode(.inline).toolbar{if scope == .published{ToolbarItem(placement:.principal){Brand()};ToolbarItem(placement:.navigationBarLeading){NotificationBell{notifications=true}}};if api.active{ToolbarItem(placement:.navigationBarTrailing){if api.writer{Menu{Button("طلب نشر خبر"){requestNews=true};Button("نشر خبر مباشر"){editor=Item(["id":"new"])}}label:{Image(systemName:"plus.app").font(.title3)}.accessibilityLabel("إضافة خبر أو طلب نشر")}else{Button{requestNews=true}label:{Image(systemName:"plus.app").font(.title3)}.accessibilityLabel("طلب نشر خبر")}}}}.task{await load(reset:true);while !Task.isCancelled{do{try await Task.sleep(nanoseconds:10_000_000_000)}catch{break};now=Date()}}.sheet(isPresented:$requestNews){NavigationStack{NewNewsRequestScreen().toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){requestNews=false}}}}}.sheet(isPresented:$notifications){NavigationStack{NotificationsScreen()}}.sheet(item:$editor){post in NavigationStack{PostEditor(post:post.id=="new" ? nil:post){await load(reset:true)}}}.sheet(item:$details){ad in NavigationStack{AnnouncementDetails(ad:ad)}}}

    var activeAds:[Item]{ads.filter{!$0.flag("is_popup") && $0.flag("enabled") && dateValue($0.text("starts_at"))<=now && dateValue($0.text("ends_at"))>now}}
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
    @State private var comments=false
    @State private var commentCount=0
    @State private var confirmDelete=false
    @State private var sharedNews:SharedExport?
    @State private var issue=""
    var editable:Bool{api.admin || (api.writer && post.text("author_id")==api.user.id)}
    var body:some View{VStack(alignment:.leading,spacing:0){HStack(spacing:10){NavigationLink{MemberScreen(member:post.text("author_id"))}label:{HStack(spacing:10){Avatar(path:post.child("profiles").text("avatar_path"),name:post.child("profiles").text("display_name"));VStack(alignment:.leading,spacing:3){Text(post.child("profiles").text("display_name")).font(.subheadline.weight(.semibold));Text(dateValue(post.text("created_at")),style:.date).font(.caption2).foregroundStyle(.secondary)}}.foregroundStyle(.primary)}.buttonStyle(.plain);Spacer();if editable{Menu{Button("تعديل الخبر",systemImage:"pencil"){edit()};Button(scope == .hidden ? "استعادة الخبر":"إخفاء الخبر",systemImage:scope == .hidden ? "arrow.uturn.backward":"eye.slash"){Task{do{_ = try await api.table("posts",[q("id","eq."+post.id)],method:"PATCH",body:["deleted_at":scope == .hidden ? NSNull():ISO8601DateFormatter().string(from:Date())]);await refresh()}catch{issue=api.errorText(error)}}};if api.admin{Button("حذف نهائي",systemImage:"trash",role:.destructive){confirmDelete=true}}}label:{Image(systemName:"ellipsis").frame(width:44,height:44)}}}.padding(.horizontal,14).padding(.vertical,10)
        if !post.imagePaths.isEmpty{NewsAlbum(paths:post.imagePaths)}
        HStack(spacing:20){TaskButton(title:"",symbol:liked ? "heart.fill":"heart"){if liked{_ = try await api.table("likes",[q("post_id","eq."+post.id),q("user_id","eq."+api.user.id)],method:"DELETE")}else{_ = try await api.table("likes",method:"POST",body:["post_id":post.id,"user_id":api.user.id])};liked.toggle();count += liked ? 1 : -1}.disabled(api.readOnly).foregroundStyle(liked ? brandPink:Color.primary).accessibilityLabel(liked ? "إلغاء الإعجاب":"إعجاب");Button{withAnimation(.easeInOut(duration:0.2)){comments.toggle()}}label:{Image(systemName:"bubble.right")}.accessibilityLabel("تعليقات الخبر");if post.flag("published") && post.text("deleted_at").isEmpty{TaskButton(title:"",symbol:"paperplane"){let image=try await newsShareImage(post,api:api);sharedNews=SharedExport(items:[image])}.accessibilityLabel("مشاركة الخبر كصورة")};Spacer()}.font(.system(size:24)).buttonStyle(.plain).padding(.horizontal,12).padding(.vertical,6)
        Text("\(count) إعجاب").font(.subheadline.bold()).padding(.horizontal,14).padding(.bottom,4)
        VStack(alignment:.leading,spacing:6){Text(post.text("title")).font(.subheadline.bold());MentionBody(post:post);if scope == .mentioned{NavigationLink("فتح الخبر"){PostDestination(postID:post.id)}.font(.subheadline.bold())};if !post.flag("published"){Text(post.text("moderation_status")=="pending" ? "بانتظار موافقة المدير":"مسودة").font(.caption).foregroundStyle(brandPink)};if scope == .review && api.admin{HStack{TaskButton(title:"اعتماد ونشر",symbol:"checkmark"){_ = try await api.table("posts",[q("id","eq."+post.id)],method:"PATCH",body:["published":true,"moderation_status":"published"]);await refresh()};TaskButton(title:"رفض",symbol:"xmark"){_ = try await api.table("posts",[q("id","eq."+post.id)],method:"PATCH",body:["published":false,"moderation_status":"rejected"]);await refresh()}}.buttonStyle(.bordered)}}.padding(.horizontal,16).padding(.bottom,18)
            if comments{InlineComments(post:post,changed:{commentCount=max(0,commentCount+$0)}).padding(.horizontal,14).padding(.bottom,12).transition(.opacity.combined(with:.move(edge:.top)))}
    }.background{if post.flag("from_request"){Brand().frame(maxWidth:280).opacity(0.075)}}.background(post.flag("from_request") ? brandBlue.opacity(0.035):Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius:4)).overlay{RoundedRectangle(cornerRadius:4).stroke(Color(.separator).opacity(0.18),lineWidth:0.5)}.task(id:post.id){commentCount=post.rows("comments").first?.number("count") ?? 0;count=post.rows("likes").first?.number("count") ?? 0;do{liked = !(try await api.table("likes",[q("select","user_id"),q("post_id","eq."+post.id),q("user_id","eq."+api.user.id)])).isEmpty}catch{}}
    .sheet(item:$sharedNews){NativeShareSheet(export:$0)}
    .alert("حذف الخبر نهائيًا؟",isPresented:$confirmDelete){Button("إلغاء",role:.cancel){};Button("حذف",role:.destructive){Task{do{let rows=try await api.table("posts",[q("id","eq."+post.id)],method:"DELETE");guard !rows.isEmpty else{throw FamilyError(text:"لم يتم حذف الخبر.")};for path in post.imagePaths{let shared=try await api.table("posts",[q("select","id"),q("image_paths","cs.{"+path+"}"),q("limit","1")]);if shared.isEmpty{_ = try? await api.request("/storage/v1/object/news-images",method:"DELETE",body:["prefixes":[path]])}};await refresh()}catch{issue=api.errorText(error)}}}}message:{Text("سيُحذف الخبر وتعليقاته وإعجاباته، ولا يمكن استعادته.")}.alert("تعذّر إكمال الطلب",isPresented:Binding(get:{!issue.isEmpty},set:{if !$0{issue=""}})){Button("حسنًا",role:.cancel){}}message:{Text(issue)}}
}
struct InlineComments:View {
    @EnvironmentObject private var api:Backend
    let post:Item
    let changed:(Int)->Void
    @State private var rows:[Item]=[]
    @State private var text=""
    @State private var error=""
    @State private var more=true
    var body:some View {
        VStack(alignment:.leading,spacing:13){
            Divider();Text("التعليقات").font(.subheadline.bold());LoadError(text:error)
            if rows.isEmpty && error.isEmpty{Text("كن أول من يعلّق على الخبر.").font(.caption).foregroundStyle(.secondary)}
            ForEach(rows){row in HStack(alignment:.top,spacing:9){Avatar(path:row.child("profiles").text("avatar_path"),name:row.child("profiles").text("display_name"),size:30);VStack(alignment:.leading,spacing:4){Text(row.child("profiles").text("display_name")).font(.caption.bold());Text(row.text("body")).font(.subheadline).fixedSize(horizontal:false,vertical:true);Text(dateValue(row.text("created_at")),style:.relative).font(.system(size:10)).foregroundStyle(.secondary)};Spacer(minLength:0);if api.admin || row.text("author_id")==api.user.id{Menu{TaskButton(title:"حذف التعليق",symbol:"trash"){let removed=try await api.table("comments",[q("id","eq."+row.id)],method:"DELETE");if !removed.isEmpty{changed(-1)};await load()}}label:{Image(systemName:"ellipsis").foregroundStyle(.secondary).frame(width:30,height:30)}}}}
            if more{TaskButton(title:"عرض تعليقات أخرى"){await load(reset:false)}.font(.caption)}
            HStack(alignment:.bottom,spacing:8){Avatar(path:api.profile.text("avatar_path"),name:api.profile.text("display_name"),size:30);TextField("أضف تعليقًا…",text:$text,axis:.vertical).lineLimit(1...4).font(.subheadline).padding(10).background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:18));TaskButton(title:"نشر"){let value=text.trimmingCharacters(in:.whitespacesAndNewlines);guard !value.isEmpty,value.count<=2000 else{throw FamilyError(text:"التعليق من حرف إلى 2000 حرف.")};let added=try await api.table("comments",method:"POST",body:["post_id":post.id,"author_id":api.user.id,"body":value]);if !added.isEmpty{changed(1)};text="";await load()}.font(.subheadline.bold()).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}
        }.task{await load()}
    }
    func load(reset:Bool=true)async {
        do{let result=try await api.table("comments",[q("select","id,body,author_id,created_at,profiles:profiles!comments_author_id_fkey(display_name,avatar_path)"),q("post_id","eq."+post.id),q("order","created_at.asc,id.asc"),q("limit","20"),q("offset",reset ? "0":String(rows.count))]);if reset{rows=result}else{rows += result};more=result.count==20;error=""}catch{self.error=api.errorText(error)}
    }
}
struct AnnouncementTabs:View {
    let ads:[Item]
    let open:(Item)->Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow=false
    func color(_ ad:Item)->Color {switch ad.text("category"){case "death":return .gray;case "urgent":return Color(red:0.72,green:0.22,blue:0.25);case "wedding":return Color(red:0.48,green:0.29,blue:0.64);case "donation":return brandPink;default:return brandBlue}}
    func symbol(_ ad:Item)->String{switch ad.text("category"){case "wedding":return "heart.fill";case "death":return "leaf.fill";case "commercial":return "bag.fill";case "urgent":return "exclamationmark.circle.fill";case "donation":return "heart.circle.fill";default:return "megaphone.fill"}}
    var body:some View {
        GeometryReader{geometry in
            let fit=announcementFit(width:Double(geometry.size.width),count:ads.count)
            HStack(spacing:CGFloat(fit.gap)){ForEach(ads){ad in
                let tone=color(ad)
                Button{open(ad)}label:{
                    HStack(spacing:fit.iconsOnly ? 0:4){Image(systemName:symbol(ad)).font(.system(size:CGFloat(fit.icon))).frame(width:CGFloat(fit.icon));if !fit.iconsOnly{Text(ad.text("title").isEmpty ? "إعلان العائلة":ad.text("title")).font(.system(size:CGFloat(max(10,min(14,fit.cell/9))),weight:.semibold)).lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading)}}
                        .padding(.horizontal,fit.iconsOnly ? 0:5).frame(width:CGFloat(fit.cell),height:46)
                        .foregroundStyle(tone).background(tone.opacity(ad.text("category")=="urgent" && !reduceMotion && glow ? 0.28:0.1),in:RoundedRectangle(cornerRadius:10))
                        .overlay{RoundedRectangle(cornerRadius:10).stroke(tone.opacity(glow && ["urgent","donation"].contains(ad.text("category")) && !reduceMotion ? 0.65:0.25),lineWidth:1)}
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(ad.text("title")).accessibilityHint("عرض تفاصيل الإعلان")
            }}.padding(.horizontal,10).padding(.vertical,9)
        }.frame(height:64).background(Color(.systemBackground)).overlay(alignment:.bottom){Divider()}.onAppear{if !reduceMotion{withAnimation(.easeInOut(duration:1.4).repeatForever(autoreverses:true)){glow=true}}}
    }
}
struct NewsAlbum:View {
    let paths:[String]
    @State private var page=0
    var body:some View {
        VStack(spacing:8){
            GeometryReader{geometry in
                TabView(selection:$page){ForEach(Array(paths.enumerated()),id:\.offset){index,path in
                    PrivateImage(path:path,bucket:"news-images",fill:false).frame(width:geometry.size.width,height:geometry.size.height).tag(index)
                }}.tabViewStyle(.page(indexDisplayMode:.never))
                .overlay(alignment:.topTrailing){if paths.count>1{Text("\(page+1) / \(paths.count)").font(.caption.monospacedDigit()).padding(.horizontal,10).padding(.vertical,5).foregroundStyle(.white).background(.black.opacity(0.55),in:Capsule()).padding(12)}}
            }.aspectRatio(4.0/5.0,contentMode:.fit)
            if paths.count>1{HStack(spacing:5){ForEach(paths.indices,id:\.self){index in Button{withAnimation{page=index}}label:{Circle().fill(index==page ? brandBlue:Color.secondary.opacity(0.25)).frame(width:6,height:6).padding(5)}.accessibilityLabel("الصورة \(index+1)")}}}
        }.accessibilityElement(children:.contain).accessibilityLabel("صور الخبر").onChange(of:paths){_,_ in page=min(page,max(0,paths.count-1))}
    }
}
struct EditorPhoto:Identifiable {let id=UUID();var path:String?;var data:Data?}
struct PostEditor:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss) private var dismiss
    let post:Item?
    let saved:()async->Void
    @State private var title:String
    @State private var bodyText:String
    @State private var publish:Bool
    @State private var photos:[PhotosPickerItem]=[]
    @State private var album:[EditorPhoto]
    @State private var loadingPhotos=false
    @State private var saving=false
    @State private var search=""
    @State private var people:[Item]=[]
    @State private var selected:[Item]=[]
    @State private var caret=NSRange(location:0,length:0)
    @State private var inlineMembers:[Item]=[]
    @State private var mentionError=""
    @State private var imageError=""
    var canChangePhotos:Bool{post == nil || post?.text("author_id")==api.user.id}
    init(post:Item?,saved:@escaping ()async->Void){self.post=post;self.saved=saved;_title=State(initialValue:post?.text("title") ?? "");_bodyText=State(initialValue:post?.text("body") ?? "");_publish=State(initialValue:post?.flag("published") ?? true);_album=State(initialValue:(post?.imagePaths ?? []).map{EditorPhoto(path:$0)})}
    var body:some View {
        Form {
            Section("الخبر"){TextField("عنوان الخبر",text:$title);VStack(alignment:.leading,spacing:10){
                    MentionEditor(text:$bodyText,selection:$caret).frame(height:180).accessibilityLabel("تفاصيل الخبر، اكتب @ للإشارة لعضو")
                    if mentionToken(bodyText,caret:caret.location) != nil{MentionSuggestions(people:inlineMembers,issue:mentionError){person in chooseMention(person)}}
                }.task(id:bodyText+String(caret.location)){do{guard let token=mentionToken(bodyText,caret:caret.location) else{inlineMembers=[];mentionError="";return};try await Task.sleep(nanoseconds:180_000_000);try Task.checkCancellation();let result=Item.items(try await api.rpc("mention_search",["term":token.term]));try Task.checkCancellation();inlineMembers=result;mentionError=""}catch{if !Task.isCancelled{mentionError=api.errorText(error)}}};Toggle("نشر الخبر الآن",isOn:$publish)}
            Section("صور الخبر · \(album.count) / ٥"){
                ForEach(Array(album.enumerated()),id:\.element.id){index,photo in
                    VStack{Group{if let data=photo.data,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFit()}else if let path=photo.path{PrivateImage(path:path,bucket:"news-images",fill:false)}}.frame(height:160)
                        if canChangePhotos{HStack{Text("الصورة \(index+1)");Spacer();Button{album.swapAt(index,index-1)}label:{Image(systemName:"arrow.up")}.disabled(index==0).accessibilityLabel("تقديم الصورة");Button{album.swapAt(index,index+1)}label:{Image(systemName:"arrow.down")}.disabled(index==album.count-1).accessibilityLabel("تأخير الصورة");Button(role:.destructive){album.removeAll{$0.id==photo.id}}label:{Image(systemName:"trash")}.accessibilityLabel("إزالة الصورة")}.buttonStyle(.borderless)}
                    }
                }
                if album.count<5 && canChangePhotos{PhotosPicker(selection:$photos,maxSelectionCount:5-album.count,selectionBehavior:.ordered,matching:.images){Label("إضافة صور",systemImage:"photo.on.rectangle.angled")}.disabled(loadingPhotos)}
                if loadingPhotos{ProgressView("تجهيز الصور…")}
                LoadError(text:imageError)
                Text("حتى ٥ صور. إطار موحّد 4:5 بدقة تصل إلى 1080 × 1350، مع ضغط الصور والسحب بينها.").font(.caption).foregroundStyle(.secondary)
            }
            Section("منشن لأعضاء العائلة"){
                TextField("@ أو بداية الاسم — الأقارب أولًا",text:$search).task(id:search){do{try await Task.sleep(nanoseconds:250_000_000);try Task.checkCancellation();let r=Item.items(try await api.rpc("mention_search",["term":search.replacingOccurrences(of:"@",with:"")]));try Task.checkCancellation();people=r}catch{}}
                ForEach(people){p in Button{if selected.count<20 && !selected.contains(where:{$0.id==p.id}){selected.append(p)}}label:{Label(p.text("display_name"),systemImage:selected.contains(where:{$0.id==p.id}) ? "checkmark.circle.fill":"at")}}
                ForEach(selected){p in Button(role:.destructive){selected.removeAll{$0.id==p.id}}label:{Label(p.text("display_name"),systemImage:"minus.circle")}}
            }
            Section{TaskButton(title:"حفظ الخبر",symbol:"checkmark"){try await save()}.disabled(!api.writer || loadingPhotos || saving)}
        }.disabled(saving).scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).navigationTitle(post==nil ? "خبر جديد":"تعديل الخبر").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("إلغاء"){dismiss()}.disabled(saving)}}.interactiveDismissDisabled(saving || loadingPhotos)
        .onChange(of:photos){_,items in
            guard !items.isEmpty else{return};loadingPhotos=true
            Task{defer{loadingPhotos=false;photos=[]};do{var additions:[EditorPhoto]=[];for item in items.prefix(5-album.count){guard let data=try await item.loadTransferable(type:Data.self),data.count<=20*1024*1024,UIImage(data:data) != nil else{throw FamilyError(text:"اختر صورًا صالحة أقل من 20 ميجابايت لكل صورة.")};additions.append(EditorPhoto(data:data))};album += additions;imageError=""}catch{imageError=api.errorText(error)}}
        }.task{if let ids=post?.raw["mentioned_member_ids"] as? [String],!ids.isEmpty{selected=(try? await api.table("profiles",[q("select","id,display_name"),q("id","in.("+ids.joined(separator:",")+")")])) ?? []}}
    }
    func chooseMention(_ person:Item){
        guard selected.contains(where:{$0.id==person.id}) || selected.count<20 else{mentionError="الحد الأقصى 20 عضوًا.";return}
        guard let token=mentionToken(bodyText,caret:caret.location) else{return}
        let insertion="@"+person.text("display_name")+" "
        bodyText=(bodyText as NSString).replacingCharacters(in:token.range,with:insertion);caret=NSRange(location:token.range.location+(insertion as NSString).length,length:0)
        if !selected.contains(where:{$0.id==person.id}){selected.append(person)};inlineMembers=[]
    }
    func save()async throws {
        guard api.writer,title.trimmingCharacters(in:.whitespaces).count>=3,title.count<=250,!bodyText.trimmingCharacters(in:.whitespaces).isEmpty,bodyText.count<=20000,album.count<=5 else{throw FamilyError(text:"أدخل عنوانًا صالحًا وتفاصيل الخبر، وبحد أقصى ٥ صور.")}
        saving=true;defer{saving=false};var uploaded:[String]=[];var paths:[String]=[]
        do{
            for photo in album{if let path=photo.path{paths.append(path)}else if let data=photo.data{let path=try await api.upload(data,bucket:"news-images");uploaded.append(path);paths.append(path)}}
            var values:[String:Any]=["title":title,"body":bodyText,"published":publish,"mentioned_member_ids":selected.map(\.id),"image_paths":paths,"image_path":paths.first.map{$0 as Any} ?? NSNull()]
            let rows:[Item];if let post=post{rows=try await api.table("posts",[q("id","eq."+post.id)],method:"PATCH",body:values)}else{values["author_id"]=api.user.id;rows=try await api.table("posts",method:"POST",body:values)}
            guard !rows.isEmpty else{throw FamilyError(text:"لم يتم حفظ الخبر. حدّث صلاحيات الحساب وأعد المحاولة.")}
        }catch{if !uploaded.isEmpty{_ = try? await api.request("/storage/v1/object/news-images",method:"DELETE",body:["prefixes":uploaded])};throw error}
        for path in post?.imagePaths ?? [] where !paths.contains(path){if let shared=try? await api.table("posts",[q("select","id"),q("image_paths","cs.{"+path+"}"),q("limit","1")]),shared.isEmpty{_ = try? await api.request("/storage/v1/object/news-images",method:"DELETE",body:["prefixes":[path]])}}
        await saved();dismiss()
    }
}

struct MentionEditor:UIViewRepresentable {
    @Binding var text:String
    @Binding var selection:NSRange
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeUIView(context:Context)->UITextView {
        let view=UITextView();view.delegate=context.coordinator;view.font=UIFont.preferredFont(forTextStyle:.body);view.adjustsFontForContentSizeCategory=true;view.backgroundColor = .secondarySystemBackground;view.layer.cornerRadius=10;view.textContainerInset=UIEdgeInsets(top:12,left:10,bottom:12,right:10);view.textAlignment = .natural;view.semanticContentAttribute = .forceRightToLeft;view.accessibilityLabel="تفاصيل الخبر، اكتب @ للإشارة لعضو";view.keyboardDismissMode = .interactive;view.text=text;return view
    }
    func updateUIView(_ view:UITextView,context:Context){context.coordinator.parent=self;if view.text != text{view.text=text;let length=(text as NSString).length;view.selectedRange=NSRange(location:min(selection.location,length),length:0)}}
    @MainActor final class Coordinator:NSObject,UITextViewDelegate {
        var parent:MentionEditor
        init(_ parent:MentionEditor){self.parent=parent}
        func textViewDidChange(_ view:UITextView){parent.text=view.text;parent.selection=view.selectedRange}
        func textViewDidChangeSelection(_ view:UITextView){if parent.selection != view.selectedRange{parent.selection=view.selectedRange}}
    }
}
struct MentionSuggestions:View {
    let people:[Item]
    let issue:String
    let choose:(Item)->Void
    var body:some View {
        VStack(alignment:.leading,spacing:0){Text("أقارب شجرتك أولًا، ثم بقية الأعضاء").font(.caption).foregroundStyle(.secondary).padding(9)
            if !issue.isEmpty{LoadError(text:issue)}else if people.isEmpty{Text("لا توجد أسماء مطابقة").font(.caption).padding(9)}
            ScrollView{LazyVStack(spacing:0){ForEach(people){person in Button{choose(person)}label:{HStack(spacing:9){Avatar(path:person.text("avatar_path"),name:person.text("display_name"),size:30);VStack(alignment:.leading,spacing:3){Text(person.text("display_name")).font(.subheadline);if !person.text("relation_label").isEmpty{Text(person.text("relation_label")).font(.caption).foregroundStyle(.secondary)}};Spacer();Image(systemName:"at").font(.caption)}.padding(9).contentShape(Rectangle())}.buttonStyle(.plain);Divider()}}}.frame(maxHeight:210)
        }.background(Color(.secondarySystemBackground),in:RoundedRectangle(cornerRadius:10))
    }
}

struct MentionBody:View {
    @EnvironmentObject private var api:Backend
    let post:Item
    @State private var members:[Item]=[]
    @State private var viewed:Item?
    var text:AttributedString {
        let body=post.text("body");var result=AttributedString(body)
        for mention in memberMentionRanges(body,members:members){if let range=Range(mention.range,in:body),let start=AttributedString.Index(range.lowerBound,within:result),let end=AttributedString.Index(range.upperBound,within:result){result[start..<end].link=URL(string:"familynews://member/"+mention.id);result[start..<end].foregroundColor=brandBlue}}
        return result
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8){Text(text).font(.subheadline).lineSpacing(4).textSelection(.enabled)
            if !members.isEmpty{ViewThatFits(in:.horizontal){HStack(spacing:8){ForEach(members.prefix(3)){member in memberButton(member)}};VStack(alignment:.leading,spacing:6){ForEach(members.prefix(3)){member in memberButton(member)}}};if members.count>3{Menu("و\(members.count-3) أعضاء آخرين"){ForEach(members.dropFirst(3)){member in Button(member.text("display_name")){viewed=member}}}}}
        }.environment(\.openURL,OpenURLAction{url in if url.scheme=="familynews",url.host=="member",let member=members.first(where:{$0.id==url.lastPathComponent}){viewed=member;return .handled};return .discarded})
        .task(id:String(describing:post.raw["mentioned_member_ids"])){guard let ids=post.raw["mentioned_member_ids"] as? [String],!ids.isEmpty else{members=[];return};members=(try? await api.table("profiles",[q("select","id,display_name"),q("id","in.("+ids.joined(separator:",")+")"),q("status","eq.active")])) ?? []}
        .sheet(item:$viewed){member in NavigationStack{MemberScreen(member:member.id).toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){viewed=nil}}}}}
    }
    func memberButton(_ member:Item)->some View{Button("@"+member.text("display_name")){viewed=member}.font(.caption.weight(.semibold)).buttonStyle(.plain).foregroundStyle(brandBlue).lineLimit(1)}
}

struct AnnouncementDetails:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss)private var dismiss
    let ad:Item
    @State private var contact=Item()
    @State private var room:Room?
    @State private var loading=false
    @State private var error=""
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:20){
            Text(ad.text("title")).font(.title2.bold());Text(ad.text("body")).font(.body).textSelection(.enabled)
            Text("حتى \(dateValue(ad.text("ends_at")).formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)
            if loading{ProgressView("تحميل جهة التواصل…")}
            LoadError(text:error)
            if !contact.id.isEmpty{Divider();if contact.id==api.user.id{Label("أنت المعني بهذا الإعلان",systemImage:"person.crop.circle").font(.subheadline).foregroundStyle(.secondary)}else{
                TaskButton(title:"تواصل مع @"+contact.text("display_name"),symbol:"bubble.left.and.bubble.right.fill"){
                    guard let thread=try await api.rpc("chat_open",["other":contact.id]) as? String else{throw FamilyError(text:"تعذّر فتح المحادثة.")}
                    room=Room(id:thread,title:contact.text("display_name"),thread:thread,avatar:contact.text("avatar_path"),peer:contact.id)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }}
        }.padding()}.scrollIndicators(.hidden).navigationTitle("تفاصيل الإعلان").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){dismiss()}}}
        .task{let id=ad.text("contact_member_id");guard !id.isEmpty else{return};loading=true;defer{loading=false};do{contact=Item(try await api.action("account_action","directory_profile",["member":id]) as? [String:Any] ?? [:])}catch{self.error="جهة التواصل لم تعد متاحة."}}
        .fullScreenCover(item:$room){value in NavigationStack{ChatRoom(room:value).toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){room=nil}}}}}
    }
}

// Loaded once after account unlock; server controls per-account frequency and opt-out.
struct PopupCampaign:Identifiable {let ad:Item;let image:UIImage;var id:String{ad.id}}
struct PopupAdvertisement:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss)private var dismiss
    @Environment(\.scenePhase)private var phase
    let campaign:PopupCampaign
    @State private var remaining=0
    @State private var hidden=false
    @State private var warning=""
    var body:some View {
        ZStack{Color.black.ignoresSafeArea();Image(uiImage:campaign.image).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityLabel(campaign.ad.text("title"))}
        .safeAreaInset(edge:.top){HStack{Text("إعلان دعائي · \(remaining) ث").font(.caption.weight(.semibold));Spacer();Button{dismiss()}label:{Image(systemName:"xmark").font(.title3.bold()).frame(width:48,height:48)}.accessibilityLabel("إغلاق الإعلان فورًا")}.foregroundStyle(.white).padding(.horizontal,16).background(.black.opacity(0.75))}
        .safeAreaInset(edge:.bottom){VStack{Toggle("عدم إظهار هذا الإعلان مرة أخرى",isOn:$hidden).tint(brandPink);if !warning.isEmpty{Text(warning).font(.caption)}}.foregroundStyle(.white).padding(20).background(.black.opacity(0.85))}
        .onChange(of:hidden){_,value in
            let key="promo-hidden-"+api.user.id+"-"+campaign.id;UserDefaults.standard.set(value,forKey:key)
            Task{do{_ = try await api.rpc("promo_hide",["ad_id":Int(campaign.id) ?? 0,"hide":value]);warning=""}catch{warning="تعذّر مزامنة التفضيل. حُفظ على هذا الجهاز."}}
        }
        .task{remaining=max(1,campaign.ad.number("display_seconds"));while remaining>0{do{try await Task.sleep(nanoseconds:1_000_000_000)}catch{return};if phase == .active{remaining-=1}};dismiss()}
        .privacySensitive()
    }
}

@MainActor func newsShareImage(_ post:Item,api:Backend)async throws->UIImage {
 guard post.flag("published"),post.text("deleted_at").isEmpty else{throw FamilyError(text:"المشاركة للأخبار المنشورة والمتاحة فقط")}
 var cover:UIImage?
 if let path=post.imagePaths.first{cover=UIImage(data:try await api.signedData(bucket:"news-images",path:path))}
 let paragraph=NSMutableParagraphStyle();paragraph.alignment = .right;paragraph.baseWritingDirection = .rightToLeft
 let titleAttributes:[NSAttributedString.Key:Any]=[.font:UIFont.boldSystemFont(ofSize:36),.paragraphStyle:paragraph,.foregroundColor:UIColor.black]
 let bodyAttributes:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:28),.paragraphStyle:paragraph,.foregroundColor:UIColor.black]
 let titleHeight=(post.text("title")as NSString).boundingRect(with:CGSize(width:960,height:12000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:titleAttributes,context:nil).height+20
 let bodyHeight=(post.text("body")as NSString).boundingRect(with:CGSize(width:960,height:12000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:bodyAttributes,context:nil).height+20
 let height:CGFloat=230+(cover==nil ? 0:1130)+titleHeight+bodyHeight+100
 guard height<15000 else{throw FamilyError(text:"نص الخبر طويل جدًا لتصديره كصورة واحدة")}
 let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
 return UIGraphicsImageRenderer(size:CGSize(width:1080,height:height),format:format).image{ctx in
 UIColor.white.setFill();ctx.fill(CGRect(x:0,y:0,width:1080,height:height));var y:CGFloat=160
 let familyName=api.family.text("name").isEmpty ? "منصة العوائل":api.family.text("name")
 (familyName as NSString).draw(in:CGRect(x:320,y:35,width:700,height:48),withAttributes:[.font:UIFont.boldSystemFont(ofSize:32),.foregroundColor:UIColor(red:0.07,green:0.22,blue:0.28,alpha:1),.paragraphStyle:paragraph])
 (post.child("profiles").text("display_name")as NSString).draw(in:CGRect(x:320,y:90,width:700,height:38),withAttributes:[.font:UIFont.systemFont(ofSize:24),.foregroundColor:UIColor.darkGray,.paragraphStyle:paragraph])
 let logo=tenantLogo(api.family) ?? UIImage(named:api.family.text("code")=="01" ? "FamilyLogo":"PlatformLogo")
 if let logo{let scale=min(220/logo.size.width,100/logo.size.height);logo.draw(in:CGRect(x:60,y:30,width:logo.size.width*scale,height:logo.size.height*scale))}
 if let image=cover{UIColor(white:0.96,alpha:1).setFill();ctx.fill(CGRect(x:0,y:y,width:1080,height:1080));let scale=min(1080/image.size.width,1080/image.size.height);image.draw(in:CGRect(x:(1080-image.size.width*scale)/2,y:y+(1080-image.size.height*scale)/2,width:image.size.width*scale,height:image.size.height*scale));y += 1130}
 (post.text("title")as NSString).draw(in:CGRect(x:60,y:y,width:960,height:titleHeight),withAttributes:titleAttributes);y += titleHeight+15
 (post.text("body")as NSString).draw(in:CGRect(x:60,y:y,width:960,height:bodyHeight),withAttributes:bodyAttributes)
 let footer="خبر رقم "+post.id+" · "+dateValue(post.text("created_at")).formatted(date:.numeric,time:.omitted)
 (footer as NSString).draw(in:CGRect(x:60,y:height-55,width:960,height:40),withAttributes:[.font:UIFont.systemFont(ofSize:22),.foregroundColor:UIColor.darkGray,.paragraphStyle:paragraph])
 }
}
