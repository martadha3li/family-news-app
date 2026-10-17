import SwiftUI
import UserNotifications
import UIKit

extension Notification.Name {static let openFamilyNotifications=Notification.Name("openFamilyNotifications")}
@MainActor final class NativeNotifications:NSObject,ObservableObject,UNUserNotificationCenterDelegate {
    @Published var items:[Item]=[]
    @Published var unread=0
    @Published var error=""
    @Published var permission="لم تُفعّل التنبيهات بعد"
    @Published var newsEnabled=true
    @Published var privateEnabled=true
    @Published var visibleThread=""
    private var owner=""
    private var cursor=Date.distantPast
    private var readAt=Date.distantPast
    private var through=""
    private var busy=false
    override init(){super.init();UNUserNotificationCenter.current().delegate=self}
    func configure(_ user:String){guard owner != user else{return};reset();owner=user;let defaults=UserDefaults.standard;newsEnabled=defaults.object(forKey:"news-alerts-"+user) as? Bool ?? true;privateEnabled=defaults.object(forKey:"private-alerts-"+user) as? Bool ?? true}
    func savePreferences(){guard !owner.isEmpty else{return};UserDefaults.standard.set(newsEnabled,forKey:"news-alerts-"+owner);UserDefaults.standard.set(privateEnabled,forKey:"private-alerts-"+owner)}
    func reset(){owner="";items=[];unread=0;error="";cursor = .distantPast;readAt = .distantPast;through="";visibleThread="";UNUserNotificationCenter.current().removeAllPendingNotificationRequests();UNUserNotificationCenter.current().removeAllDeliveredNotifications();Task{try? await UNUserNotificationCenter.current().setBadgeCount(0)}}
    func enable()async throws {let allowed=try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]);await updatePermission();if !allowed{throw FamilyError(text:"السماح بالإشعارات مغلق. يمكنك تفعيله من إعدادات الآيفون > الإشعارات > أخبار العائلة.")}}
    func updatePermission()async {let settings=await UNUserNotificationCenter.current().notificationSettings();switch settings.authorizationStatus{case .authorized,.provisional,.ephemeral:permission="التنبيهات مفعّلة أثناء فتح التطبيق";case .denied:permission="الإشعارات غير مسموحة من إعدادات الجهاز";default:permission="لم تُفعّل التنبيهات بعد"}}
    func refresh(_ api:Backend,markRead:Bool=false)async {
        guard api.active,!busy else{return};configure(api.user.id);let identity=owner;busy=true;defer{busy=false}
        do{
            let payload:[String:Any]=markRead && !through.isEmpty ? ["through":through]:[:]
            let data=Item(try await api.action("native_notifications",markRead && !through.isEmpty ? "read":"list",payload) as? [String:Any] ?? [:])
            guard api.active,api.user.id==identity,owner==identity else{return}
            let next=data.rows("items");let latest=dateValue(data.text("server_at"));let previous=cursor
            items=next;readAt=dateValue(data.text("read_at"));through=data.text("server_at");cursor=latest;unread=next.filter{dateValue($0.text("created_at"))>readAt}.count;error=""
            if UIApplication.shared.applicationState == .active,previous != .distantPast,!markRead {
                let fresh=next.filter{dateValue($0.text("created_at"))>previous && dateValue($0.text("created_at"))>readAt}
                let hasNews=newsEnabled && fresh.contains{$0.text("kind")=="news"}
                let hasMessages=privateEnabled && fresh.contains{$0.text("kind")=="private" && $0.text("thread_id") != visibleThread}
                if hasNews || hasMessages {
                    let content=UNMutableNotificationContent();content.title="أخبار العائلة";content.body=hasNews && hasMessages ? "لديك أخبار جديدة ورسائل واردة":(hasMessages ? "لديك رسالة خاصة جديدة":"نُشر خبر جديد للعائلة");content.sound = .default;content.badge=NSNumber(value:unread);content.userInfo=["open":"notifications"]
                    guard owner==identity,api.active,UIApplication.shared.applicationState == .active else{return}
                    try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"family-update-"+UUID().uuidString,content:content,trigger:nil))
                }
            }
            guard owner==identity,api.active else{return};try? await UNUserNotificationCenter.current().setBadgeCount(unread)
        }catch{if owner==identity{items=[];unread=0;self.error=api.errorText(error);UNUserNotificationCenter.current().removeAllDeliveredNotifications();try? await UNUserNotificationCenter.current().setBadgeCount(0)}}
    }
    func isUnread(_ item:Item)->Bool {dateValue(item.text("created_at"))>readAt}
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification)async -> UNNotificationPresentationOptions {[.banner,.sound,.badge]}
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse)async {await MainActor.run{NotificationCenter.default.post(name:.openFamilyNotifications,object:nil)}}
}
struct NotificationBell:View {
    @EnvironmentObject private var alerts:NativeNotifications
    let open:()->Void
    var body:some View {
        Button(action:open){
            Image(systemName:"bell").font(.title3).frame(width:44,height:44)
                .overlay(alignment:.topTrailing){if alerts.unread>0{Text(alerts.unread>99 ? "99+":String(alerts.unread)).font(.system(size:10,weight:.bold)).padding(4).foregroundStyle(.white).background(brandPink,in:Capsule())}}
        }.accessibilityLabel("الإشعارات، \(alerts.unread) غير مقروءة")
    }
}
struct NotificationsScreen:View {
    @EnvironmentObject private var api:Backend
    @EnvironmentObject private var alerts:NativeNotifications
    @Environment(\.dismiss) private var dismiss
    @State private var news:Item?
    @State private var room:Room?
    @State private var issue=""
    var body:some View {
        List{
            Section("تنبيهات الجهاز"){
                TaskButton(title:"تفعيل الإشعارات",symbol:"bell.badge"){try await alerts.enable()}
                Text(alerts.permission).font(.caption).foregroundStyle(.secondary)
                Toggle("الأخبار الجديدة",isOn:$alerts.newsEnabled).onChange(of:alerts.newsEnabled){_,_ in alerts.savePreferences()}
                Toggle("الرسائل الخاصة",isOn:$alerts.privateEnabled).onChange(of:alerts.privateEnabled){_,_ in alerts.savePreferences()}
                Text("تصل التنبيهات في هذه النسخة أثناء فتح التطبيق. تبقى الأخبار والرسائل غير المقروءة في هذه القائمة عند عودتك.").font(.caption).foregroundStyle(.secondary)
                Button("إعدادات إشعارات الآيفون"){if let url=URL(string:UIApplication.openNotificationSettingsURLString){UIApplication.shared.open(url)}}
            }
            Section("الإشعارات"){
                LoadError(text:alerts.error);LoadError(text:issue)
                if alerts.items.isEmpty && alerts.error.isEmpty{Text("لا توجد إشعارات بعد").foregroundStyle(.secondary)}
                ForEach(alerts.items){item in Button{Task{await open(item)}}label:{HStack(spacing:12){Image(systemName:item.text("kind")=="news" ? "newspaper":"bubble.left.fill").foregroundStyle(brandBlue).frame(width:28);VStack(alignment:.leading,spacing:5){Text(item.text("kind")=="news" ? item.text("title"):"رسالة خاصة من "+item.text("title")).font(.subheadline.weight(alerts.isUnread(item) ? .bold:.regular)).foregroundStyle(.primary);Text(dateValue(item.text("created_at")),style:.relative).font(.caption).foregroundStyle(.secondary)};Spacer();if alerts.isUnread(item){Circle().fill(brandPink).frame(width:7,height:7)}}.padding(.vertical,6)}}
            }
        }.listStyle(.insetGrouped).scrollIndicators(.hidden).navigationTitle("الإشعارات").navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){dismiss()}};ToolbarItem(placement:.navigationBarTrailing){TaskButton(title:"قراءة الكل"){await alerts.refresh(api,markRead:true)}}}
        .task{await alerts.refresh(api);await alerts.updatePermission()}.refreshable{await alerts.refresh(api)}
        .sheet(item:$news){post in NavigationStack{NotificationPost(post:post)}}
        .fullScreenCover(item:$room){r in NavigationStack{ChatRoom(room:r).toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){room=nil}}}}}
    }
    func open(_ item:Item)async {
        do{if item.text("kind")=="news"{let rows=try await api.table("posts",[q("select","*,profiles:profiles!posts_author_id_fkey(display_name,avatar_path),likes(count),comments(count)"),q("id","eq."+item.text("post_id")),q("published","eq.true"),q("deleted_at","is.null")]);guard let post=rows.first else{throw FamilyError(text:"هذا الخبر لم يعد متاحًا.")};news=post}else{_ = try await api.rpc("chat_read",["thread":item.text("thread_id")]);room=Room(id:item.text("thread_id"),title:item.text("title"),thread:item.text("thread_id"),avatar:item.text("avatar_path"),peer:item.text("member_id"))};issue=""}catch{issue=api.errorText(error)}
    }
}
struct NotificationPost:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss)private var dismiss
    @State var post:Item
    @State private var edit=false
    @State private var error=""
    var body:some View{ScrollView{LoadError(text:error);if !post.id.isEmpty{NativePost(post:post,edit:{edit=true},refresh:{await reload()},scope:.published)}}.scrollIndicators(.hidden).navigationTitle("الخبر").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("إغلاق"){dismiss()}}}.sheet(isPresented:$edit){NavigationStack{PostEditor(post:post){await reload()}}}}
    func reload()async{do{let rows=try await api.table("posts",[q("select","*,profiles:profiles!posts_author_id_fkey(display_name,avatar_path),likes(count),comments(count)"),q("id","eq."+post.id)]);post=rows.first ?? Item()}catch{post=Item();self.error=api.errorText(error)}}
}
