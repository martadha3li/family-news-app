import SwiftUI
import UIKit

struct Room:Identifiable,Hashable {
    var id:String
    var title:String
    var thread:String?
    var group:String?
    var avatar:String=""
    var owner:String=""
    var open=true
    var peer:String=""
}
struct ChatsScreen:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var threads:[Item]=[]
    @State private var groups:[Item]=[]
    @State private var results:[Item]=[]
    @State private var settings=Item()
    @State private var search=""
    @State private var error=""
    @State private var create=false
    @State private var destination:Room?
    @State private var filter="الكل"
    let filters=["الكل","الخاصة","المجموعات","الأحداث"]
    var body:some View{List{
        ScrollView(.horizontal){HStack(spacing:8){ForEach(filters,id:\.self){item in Button{filter=item}label:{Text(item).font(.subheadline.weight(filter==item ? .semibold:.regular)).padding(.horizontal,15).padding(.vertical,8).foregroundStyle(filter==item ? chatAccent:Color.secondary).background(filter==item ? chatAccent.opacity(0.13):Color(.secondarySystemBackground),in:Capsule())}.buttonStyle(.plain)}}}.scrollIndicators(.hidden).listRowSeparator(.hidden)
        LoadError(text:error);if !settings.flag("chat_enabled"){EmptyState(title:"الدردشة موقوفة من المدير",symbol:"bubble.left.and.exclamationmark.bubble.right")}else{
        if !search.isEmpty{Section("نتائج البحث"){ForEach(results){person in TaskButton(title:person.text("display_name"),symbol:"person.crop.circle"){let value=try await api.rpc("chat_open",["other":person.id]);guard let thread=value as? String else{throw FamilyError(text:"تعذّر فتح المحادثة.")};destination=Room(id:thread,title:person.text("display_name"),thread:thread,avatar:person.text("avatar_path"),peer:person.id)}};if results.isEmpty{Text("لا توجد أسماء مطابقة").foregroundStyle(.secondary)}}}
        if settings.flag("public_chat_enabled") && filter=="الكل"{NavigationLink(value:Room(id:"public",title:"دردشة العائلة العامة")){Label("دردشة العائلة العامة",systemImage:"person.3.fill").padding(.vertical,8)}}
        if filter=="الكل" || filter=="الخاصة"{Section("محادثاتي"){ForEach(threads){t in NavigationLink(value:Room(id:t.id,title:t.text("display_name"),thread:t.id,avatar:t.text("avatar_path"),peer:t.text("member_id"))){HStack(spacing:12){Avatar(path:t.text("avatar_path"),name:t.text("display_name"),size:54);VStack(alignment:.leading,spacing:5){Text(t.text("display_name")).font(.system(size:17,weight:.semibold));Text(t.text("last_body").isEmpty ? "ابدأ المحادثة":t.text("last_body")).lineLimit(1).font(.system(size:14)).foregroundStyle(.secondary)};Spacer();if !t.text("last_at").isEmpty{Text(dateValue(t.text("last_at")),style:.time).font(.caption2).foregroundStyle(.secondary)}}.padding(.vertical,5)}};if threads.isEmpty{Text("ابحث عن أحد أفراد العائلة لبدء محادثة.").font(.footnote).foregroundStyle(.secondary)}}
        }
        if filter != "الخاصة"{Section("المجموعات والأحداث"){ForEach(groups.filter{filter=="الكل" || (filter=="المجموعات" ? $0.text("kind") != "event":$0.text("kind")=="event")}){g in NavigationLink(value:Room(id:g.id,title:g.text("title"),group:g.id,owner:g.text("owner_id"),open:g.flag("open_now"))){Label{VStack(alignment:.leading){Text(g.text("title"));if g.text("kind")=="event"{Text(g.flag("open_now") ? "الحدث جارٍ":"خارج موعد الحدث").font(.caption).foregroundStyle(.secondary)}}}icon:{Image(systemName:g.text("kind")=="event" ? "calendar":"person.3")}.padding(.vertical,8)}}}
        }
        if settings.flag("restrict_gender_chat"){Text("تظهر الأسماء والمحادثات المسموح بها وفق ضوابط المدير.").font(.caption).foregroundStyle(.secondary)}
    }}.listStyle(.plain).listRowSpacing(0).scrollContentBackground(.hidden).background(Color(.systemBackground)).tint(chatAccent).scrollIndicators(.hidden).searchable(text:$search,prompt:"الاسم الأول أو رقم الجوال").navigationTitle("الدردشات").navigationBarTitleDisplayMode(.large).toolbar{ToolbarItem(placement:.cancellationAction){Button("الأخبار"){dismiss()}};if api.admin || settings.flag("allow_groups"){ToolbarItem(placement:.navigationBarTrailing){Button{create=true}label:{Image(systemName:"square.and.pencil")}.accessibilityLabel("إنشاء مجموعة")}}}.navigationDestination(for:Room.self){room in ChatRoom(room:room)}.navigationDestination(item:$destination){room in ChatRoom(room:room)}.sheet(isPresented:$create){NavigationStack{CreateGroupScreen{room in create=false;destination=room;Task{await load()}}}}.refreshable{await load()}.task{await load();while !Task.isCancelled{do{try await Task.sleep(nanoseconds:7_000_000_000)}catch{break};if phase == .active && api.active{await load()}}}.task(id:search){do{try await Task.sleep(nanoseconds:250_000_000);try Task.checkCancellation();let term=search.trimmingCharacters(in:.whitespacesAndNewlines);guard !term.isEmpty else{results=[];return};let data=try await api.rpc("chat_search",["term":term]);try Task.checkCancellation();results=Item.items(data)}catch{if !Task.isCancelled{self.error=api.errorText(error)}}}}
    func load()async{do{settings=(try await api.table("family_settings",[q("select","*"),q("id","eq.true")])).first ?? Item();guard settings.flag("chat_enabled") else{threads=[];groups=[];results=[];return};threads=Item.items(try await api.rpc("chat_list"));groups=Item.items(try await api.action("group_action","list"));error=""}catch{threads=[];groups=[];results=[];self.error=api.errorText(error)}}
}
struct ChatRoom:View {
    @EnvironmentObject private var api:Backend
    @EnvironmentObject private var alerts:NativeNotifications
    @Environment(\.scenePhase) private var phase
    let room:Room
    @State private var messages:[Item]=[]
    @State private var bodyText=""
    @State private var error=""
    @State private var search=""
    @State private var searchMode=false
    @State private var more=true
    @State private var sending=false
    @State private var loading=false
    @State private var details=false
    @State private var reply:Item?
    @State private var editing:Item?
    @State private var deleting:Item?
    @State private var open=true
    @FocusState private var focused:Bool
    var body:some View{VStack(spacing:0){if searchMode{TextField("بحث في الرسائل",text:$search).textFieldStyle(.roundedBorder).padding(10)};LoadError(text:error)
        ScrollViewReader{proxy in ScrollView{LazyVStack(spacing:4){if more && search.isEmpty{TaskButton(title:"رسائل أقدم",symbol:"arrow.up"){await load(older:true)}};if messages.isEmpty{Text("ابدأ الحديث بكلمة طيبة.").font(.footnote).foregroundStyle(.secondary).padding(30)};ForEach(Array(messages.enumerated()),id:\.element.id){index,m in
            if index==0 || !Calendar.current.isDate(dateValue(messages[index-1].text("created_at")),inSameDayAs:dateValue(m.text("created_at"))){Text(dateValue(m.text("created_at")).formatted(date:.abbreviated,time:.omitted)).font(.caption.weight(.medium)).padding(.horizontal,12).padding(.vertical,6).background(Color(.secondarySystemBackground).opacity(0.95),in:Capsule()).padding(.vertical,9)}
            MessageBubble(message:m,mine:m.text("sender_id")==api.user.id,showSender:room.thread==nil).id(m.id).contextMenu{Button("نسخ",systemImage:"doc.on.doc"){UIPasteboard.general.string=m.text("body")};if m.text("deleted_at").isEmpty{Button("رد",systemImage:"arrowshape.turn.up.left"){reply=m;focused=true};if m.text("sender_id")==api.user.id{Button("تعديل",systemImage:"pencil"){editing=m};Button("حذف للجميع",systemImage:"trash",role:.destructive){deleting=m}}}}};Color.clear.frame(height:1).id("latest")}.padding(12)}.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively).background(ChatWallpaper()).onChange(of:messages.last?.id){_,_ in if !loading{withAnimation{proxy.scrollTo("latest",anchor:.bottom)}}}}
    }.safeAreaInset(edge:.bottom){VStack(spacing:0){if let r=reply{HStack{VStack(alignment:.leading){Text(r.text("display_name")).font(.caption.bold());Text(r.text("body")).lineLimit(2).font(.caption)};Spacer();Button{reply=nil}label:{Image(systemName:"xmark.circle")}}.padding(12).background(brandBlue.opacity(0.08))};if open{HStack(alignment:.bottom,spacing:10){TextField("رسالة",text:$bodyText,axis:.vertical).lineLimit(1...5).padding(11).background(Color(.systemBackground),in:RoundedRectangle(cornerRadius:22)).focused($focused);TaskButton(title:"",symbol:"paperplane.fill"){let text=bodyText.trimmingCharacters(in:.whitespacesAndNewlines);guard !text.isEmpty,text.count<=2000 else{throw FamilyError(text:"الرسالة من حرف إلى 2000 حرف.")};if let r=reply{_ = try await api.action("message_action","reply_send",["id":r.raw["id"] ?? r.id,"message":text])}else if let group=room.group{_ = try await api.action("group_action","send",["id":group,"message":text])}else{_ = try await api.rpc("chat_send",["thread":room.thread.map { $0 as Any } ?? NSNull(),"message":text])};bodyText="";reply=nil;await load()}.disabled(bodyText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).padding(8).foregroundStyle(.white).background(chatAccent,in:Circle()).accessibilityLabel("إرسال الرسالة")}.padding(10)}else{Text("المحادثة غير متاحة حاليًا وفق الإعدادات أو موعد الحدث.").font(.footnote).padding()}}.background(.bar)}.navigationTitle("").navigationBarTitleDisplayMode(.inline).toolbarBackground(Color(.systemBackground),for:.navigationBar).toolbarBackground(.visible,for:.navigationBar).toolbar{ToolbarItem(placement:.principal){HStack(spacing:9){Avatar(path:room.avatar,name:room.title,size:36);VStack(alignment:.leading,spacing:2){Text(room.title).font(.system(size:16,weight:.semibold)).lineLimit(1);Text(room.thread != nil ? "محادثة خاصة":(room.group != nil ? "مجموعة العائلة":"دردشة العائلة العامة")).font(.system(size:11)).foregroundStyle(.secondary)}}};ToolbarItemGroup(placement:.navigationBarTrailing){Button{searchMode.toggle();if !searchMode{search=""}}label:{Image(systemName:"magnifyingglass")}.accessibilityLabel("بحث في المحادثة");if room.group != nil{Button{details=true}label:{Image(systemName:"info.circle")}}else if !room.peer.isEmpty{NavigationLink{MemberScreen(member:room.peer)}label:{Image(systemName:"person.crop.circle")}}}}.sheet(isPresented:$details){NavigationStack{GroupDetails(room:room)}}.sheet(item:$editing){m in NavigationStack{MessageEditor(message:m){await load()}}}.confirmationDialog("حذف الرسالة للجميع؟",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("حذف",role:.destructive){guard let m=deleting else{return};deleting=nil;Task{do{_ = try await api.action("message_action","delete",["id":m.raw["id"] ?? m.id]);await load()}catch{self.error=api.errorText(error)}}}}.onAppear{alerts.visibleThread=room.thread ?? ""}.onDisappear{alerts.visibleThread=""}.task{open=room.open;await load();while !Task.isCancelled{do{try await Task.sleep(nanoseconds:5_000_000_000)}catch{break};if phase == .active && search.isEmpty{await load()}}}.task(id:search){do{try await Task.sleep(nanoseconds:250_000_000);try Task.checkCancellation();if search.isEmpty{await load();return};let p:[String:Any]=["thread":room.thread.map { $0 as Any } ?? NSNull(),"group":room.group.map { $0 as Any } ?? NSNull(),"term":search];let r=Item.items(try await api.action("message_action","search",p));try Task.checkCancellation();messages=r}catch{if !Task.isCancelled{self.error=api.errorText(error)}}}}
    func load(older:Bool=false)async{guard api.active else{return};do{let before:Any=older ? (messages.first?.raw["id"] ?? NSNull()):NSNull();let data:Any;if let group=room.group{data=try await api.action("group_action","read",["id":group,"before_id":before])}else{data=try await api.rpc("chat_read",["thread":room.thread.map { $0 as Any } ?? NSNull(),"before_id":before])};let r=Item.items(data);loading=older;if older{let known=Set(messages.map(\.id));messages=r.filter{!known.contains($0.id)}+messages;more=r.count==50}else if search.isEmpty{if messages.count>50,let last=messages.last, r.contains(where:{$0.id==last.id}){let fresh=Dictionary(uniqueKeysWithValues:r.map{($0.id,$0)});messages=messages.map{fresh[$0.id] ?? $0};let known=Set(messages.map(\.id));messages += r.filter{!known.contains($0.id)}}else{messages=r;more=r.count==50}};loading=false;error="";open=true}catch{open=false;messages=[];self.error=api.errorText(error)}}
}
let chatAccent=Color(UIColor{trait in trait.userInterfaceStyle == .dark ? UIColor(red:0.25,green:0.8,blue:0.6,alpha:1):UIColor(red:0.03,green:0.48,blue:0.35,alpha:1)})
struct ChatWallpaper:View {
    @Environment(\.colorScheme)private var scheme
    var body:some View {Canvas{context,size in
        context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(scheme == .dark ? Color(red:0.06,green:0.09,blue:0.1):Color(red:0.94,green:0.92,blue:0.88)))
        for row in stride(from:0,to:Int(size.height)+50,by:62){for column in stride(from:0,to:Int(size.width)+50,by:62){let x=CGFloat(column)+(row%124==0 ? 0:20);let y=CGFloat(row);var path=Path();path.addRoundedRect(in:CGRect(x:x,y:y,width:18,height:14),cornerSize:CGSize(width:5,height:5));context.stroke(path,with:.color(Color.secondary.opacity(0.055)),lineWidth:1)}}
    }}
}
struct MessageBubble:View {
    let message:Item
    let mine:Bool
    var showSender=true
    @Environment(\.colorScheme)private var scheme
    var body:some View {
        HStack(alignment:.bottom,spacing:0){if mine{Spacer(minLength:50)}
            VStack(alignment:.leading,spacing:4){
                if !mine && showSender{Text(message.text("display_name")).font(.caption.weight(.semibold)).foregroundStyle(chatAccent)}
                if !message.text("reply_excerpt").isEmpty{Text(message.text("reply_excerpt")).font(.caption).lineLimit(3).padding(8).frame(maxWidth:.infinity,alignment:.leading).background(chatAccent.opacity(0.07),in:RoundedRectangle(cornerRadius:6)).overlay(alignment:.leading){RoundedRectangle(cornerRadius:2).fill(chatAccent).frame(width:3)}}
                Text(message.text("body")).font(.system(size:16)).lineSpacing(2).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:4){Spacer(minLength:10);if !message.text("edited_at").isEmpty{Text("تم التعديل")};Text(dateValue(message.text("created_at")),style:.time);if mine{Image(systemName:"checkmark").font(.system(size:9,weight:.semibold)).accessibilityLabel("أُرسلت")}}.font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(.horizontal,10).padding(.vertical,7).background(mine ? (scheme == .dark ? Color(red:0.02,green:0.29,blue:0.23):Color(red:0.85,green:0.98,blue:0.81)):Color(.systemBackground),in:UnevenRoundedRectangle(topLeadingRadius:mine ? 10:3,bottomLeadingRadius:10,bottomTrailingRadius:10,topTrailingRadius:mine ? 3:10)).shadow(color:.black.opacity(0.035),radius:1,y:1)
            if !mine{Spacer(minLength:50)}
        }.padding(.vertical,1).privacySensitive()
    }
}
struct MessageEditor:View {@EnvironmentObject private var api:Backend;@Environment(\.dismiss)private var dismiss;let message:Item;let saved:()async->Void;@State private var text="";var body:some View{Form{TextField("الرسالة",text:$text,axis:.vertical).lineLimit(3...10);TaskButton(title:"حفظ التعديل",symbol:"checkmark"){guard !text.trimmingCharacters(in:.whitespaces).isEmpty,text.count<=2000 else{return};_ = try await api.action("message_action","edit",["id":message.raw["id"] ?? message.id,"message":text]);await saved();dismiss()};Text("التعديل خلال 15 دقيقة من الإرسال.").font(.caption)}.navigationTitle("تعديل الرسالة").toolbar{ToolbarItem(placement:.cancellationAction){Button("إلغاء"){dismiss()}}}.task{text=message.text("body")}}}
struct CreateGroupScreen:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss)private var dismiss
    let created:(Room)->Void
    @State private var title=""
    @State private var term=""
    @State private var kind="group"
    @State private var members:[Item]=[]
    @State private var results:[Item]=[]
    @State private var start=Date()
    @State private var end=Date().addingTimeInterval(3600)
    var body:some View{Form{Section{TextField("اسم المجموعة",text:$title);if api.admin{Picker("النوع",selection:$kind){Text("مجموعة").tag("group");Text("حدث محدد").tag("event")}};if kind=="event"{DatePicker("البداية",selection:$start);DatePicker("النهاية",selection:$end)}};Section("إضافة أعضاء"){TextField("الاسم أو رقم الجوال",text:$term).task(id:term){do{try await Task.sleep(nanoseconds:250_000_000);guard !term.isEmpty else{results=[];return};let r=Item.items(try await api.rpc("chat_search",["term":term]));try Task.checkCancellation();results=r}catch{}};ForEach(results){p in Button{if members.contains(where:{$0.id==p.id}){members.removeAll{$0.id==p.id}}else if members.count<200{members.append(p)}}label:{Label(p.text("display_name"),systemImage:members.contains(where:{$0.id==p.id}) ? "checkmark.circle.fill":"circle")}};Text("المحددون: \(members.count)").font(.caption)};Section{TaskButton(title:"إنشاء",symbol:"plus"){guard title.count>=3,title.count<=100 else{throw FamilyError(text:"اسم المجموعة من 3 إلى 100 حرف.")};var p:[String:Any]=["title":title,"kind":kind,"members":members.map(\.id)];if kind=="event"{guard end>start else{throw FamilyError(text:"نهاية الحدث بعد بدايته.")};p["starts_at"]=ISO8601DateFormatter().string(from:start);p["ends_at"]=ISO8601DateFormatter().string(from:end)};guard let id=try await api.action("group_action","create",p) as? String else{throw FamilyError(text:"تعذّر إنشاء المجموعة.")};created(Room(id:id,title:title,group:id,owner:api.user.id));dismiss()}}}.scrollIndicators(.hidden).navigationTitle("محادثة جديدة").toolbar{ToolbarItem(placement:.cancellationAction){Button("إلغاء"){dismiss()}}}}
}
struct GroupDetails:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss) private var dismiss
    let room:Room
    @State private var members:[Item]=[]
    @State private var results:[Item]=[]
    @State private var term=""
    @State private var error=""
    var manager:Bool {api.admin || room.owner==api.user.id}
    func load()async {
        do {members=Item.items(try await api.action("group_action","members",["id":room.id]));error=""}
        catch {self.error=api.errorText(error)}
    }
    var body:some View {
        List {
            LoadError(text:error)
            Section("الأعضاء") {
                ForEach(members) {p in
                    NavigationLink {MemberScreen(member:p.id)} label: {Text(p.text("display_name"))}
                    .swipeActions {
                        if manager && p.id != room.owner {
                            Button("إزالة",role:.destructive) {
                                Task {do {_ = try await api.action("group_action","remove",["id":room.id,"member":p.id]);await load()} catch {self.error=api.errorText(error)}}
                            }
                        }
                    }
                }
            }
            if manager {
                Section("إضافة عضو") {
                    TextField("الاسم أو رقم الجوال",text:$term)
                        .task(id:term) {
                            do {
                                try await Task.sleep(nanoseconds:250_000_000)
                                guard !term.isEmpty else{results=[];return}
                                let r=Item.items(try await api.rpc("chat_search",["term":term]));try Task.checkCancellation();results=r
                            } catch {}
                        }
                    ForEach(results) {p in
                        TaskButton(title:p.text("display_name"),symbol:"person.badge.plus") {
                            _ = try await api.action("group_action","add",["id":room.id,"member":p.id]);await load()
                        }
                    }
                }
            }
            if room.owner != api.user.id {
                TaskButton(title:"مغادرة المجموعة",symbol:"rectangle.portrait.and.arrow.right") {
                    _ = try await api.action("group_action","leave",["id":room.id]);dismiss()
                }
            }
        }.navigationTitle(room.title)
        .toolbar {ToolbarItem(placement:.cancellationAction){Button("إغلاق"){dismiss()}}}
        .task {await load()}
    }
}
