import SwiftUI
import UIKit
import PhotosUI

struct SettingsScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var values:[String:Bool]=[:]
    @State private var families=""
    @State private var oldFamilies:[String]=[]
    @State private var error=""
    @State private var saved=false
    let fields:[(String,String)]=[("chat_enabled","تشغيل الدردشة"),("public_chat_enabled","الدردشة العامة"),("private_chat_enabled","الدردشة الخاصة"),("restrict_gender_chat","منع الدردشة بين الجنسين"),("trusted_chat_enabled","استثناء التعريف المقبول في الخاص"),("kinship_chat_enabled","استثناء القرابة المؤكدة في الخاص"),("allow_groups","السماح للأعضاء بإنشاء مجموعات"),("journalist_approval","أخبار الصحفي تتطلب موافقة المدير"),("endorsements_enabled","التعريف بالأعضاء"),("auto_activate","اعتماد تلقائي عند مطابقة العائلة وتأكيد البريد")]
    var body:some View{Form{LoadError(text:error);Section{NavigationLink("طلبات صيانة المنصة"){FamilyMaintenanceScreen()};NavigationLink("طلبات تأكيد القرابة"){KinshipReviewScreen()}};Section("الصلاحيات"){ForEach(fields,id:\.0){key,label in Toggle(label,isOn:Binding(get:{values[key] ?? false},set:{values[key]=$0}))}};Section("العوائل المسموح بها"){TextField("عائلة واحدة في كل سطر",text:$families,axis:.vertical).lineLimit(4...10);Text("تُراجع الصلاحيات في قاعدة البيانات لكل طلب. تشابه الاسم وحده ليس إثبات نسب.").font(.caption).foregroundStyle(.secondary)};TaskButton(title:"حفظ الإعدادات",symbol:"checkmark"){guard api.admin else{return};let names=Array(Set(families.split(separator:"\n").map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}));guard names.allSatisfy({$0.count>=2 && $0.count<=80 && !$0.contains(where:{$0.isWhitespace})}) else{throw FamilyError(text:"كل عائلة اسم واحد من 2 إلى 80 حرفًا.")};for n in oldFamilies where !names.contains(n){_ = try await api.table("allowed_families",[q("name","eq."+n)],method:"DELETE")};for n in names where !oldFamilies.contains(n){_ = try await api.table("allowed_families",method:"POST",body:["name":n])};_ = try await api.table("family_settings",[q("id","eq.true")],method:"PATCH",body:values);oldFamilies=names;saved=true}}.scrollIndicators(.hidden).navigationTitle("ضوابط العائلة").task{do{let s=(try await api.table("family_settings",[q("select","*"),q("id","eq.true")])).first ?? Item();for (key,_) in fields{values[key]=s.flag(key)};oldFamilies=try await api.table("allowed_families",[q("select","name"),q("order","name")]).map{$0.text("name")};families=oldFamilies.joined(separator:"\n")}catch{self.error=api.errorText(error)}}.alert("تم حفظ الإعدادات",isPresented:$saved){Button("حسنًا",role:.cancel){}}}
}
struct MembersScreen:View {@EnvironmentObject private var api:Backend;@State private var rows:[Item]=[]
    @State private var term=""
    @State private var error="";var filtered:[Item]{rows.filter{term.isEmpty || $0.text("display_name").localizedStandardContains(term)}};var body:some View{List{LoadError(text:error);ForEach(filtered){p in NavigationLink{MemberAdminEditor(member:p)}label:{HStack{Avatar(path:p.text("avatar_path"),name:p.text("display_name"));VStack(alignment:.leading){Text(p.text("display_name"));Text(p.flag("is_root") ? "المدير الرئيسي":p.text("status")=="active" ? "معتمد":p.text("status")=="suspended" ? "موقوف":"بانتظار الاعتماد").font(.caption).foregroundStyle(.secondary)}}}}}.scrollIndicators(.hidden).searchable(text:$term,prompt:"البحث بالاسم").navigationTitle("إدارة الأعضاء").task{do{rows=[];for offset in stride(from:0,to:2000,by:500){let page=try await api.table("profiles",[q("select","id,display_name,status,role,is_root,avatar_path"),q("order","created_at.desc"),q("limit","500"),q("offset",String(offset))]);rows += page;if page.count<500{break}}}catch{self.error=api.errorText(error)}}}}
struct MemberAdminEditor:View {@EnvironmentObject private var api:Backend;let member:Item;@State private var role="member"
    @State private var status="pending"
    @State private var details=Item()
    @State private var notice="";var protected:Bool{member.flag("is_root") || member.id==api.user.id};var body:some View{Form{Text(member.text("display_name")).font(.headline);if protected{Text("هذا الحساب محمي من تغيير الدور أو الإيقاف من هذه الشاشة.").font(.footnote)};Picker("الصلاحية",selection:$role){Text("مدير").tag("admin");Text("صحفي").tag("journalist");Text("عضو").tag("member")}.disabled(protected);Picker("الحالة",selection:$status){Text("معتمد").tag("active");Text("قيد المراجعة").tag("pending");Text("موقوف").tag("suspended")}.disabled(protected);TaskButton(title:"حفظ",symbol:"checkmark"){_ = try await api.table("profiles",[q("id","eq."+member.id)],method:"PATCH",body:["role":role,"status":status]);notice="تم الحفظ."}.disabled(protected);Text(notice).foregroundStyle(brandBlue);Section("بيانات التسجيل"){ForEach(["full_name","email","phone","reference_name","relationship"],id:\.self){key in Text(details.text(key)).textSelection(.enabled)}}}.navigationTitle("بيانات العضو").task{role=member.text("role");status=member.text("status");details=Item((try? await api.rpc("member_detail",["member":member.id])) as? [String:Any] ?? [:])}}}
struct PhoneRequestsScreen:View {@EnvironmentObject private var api:Backend;@State private var rows:[Item]=[]
    @State private var error="";func load()async{do{rows=Item.items(try await api.action("account_action","phone_list"));error=""}catch{self.error=api.errorText(error)}};var body:some View{List{LoadError(text:error);ForEach(rows.filter{$0.text("status")=="pending"}){r in VStack(alignment:.leading,spacing:10){Text(r.text("display_name")).font(.headline);Text(r.text("current_phone")+" ← "+r.text("new_phone")).font(.subheadline);HStack{TaskButton(title:"اعتماد",symbol:"checkmark"){_ = try await api.action("account_action","phone_approve",["id":r.id]);await load()};TaskButton(title:"رفض",symbol:"xmark"){_ = try await api.action("account_action","phone_reject",["id":r.id]);await load()}}.buttonStyle(.bordered)}}}.navigationTitle("طلبات تغيير الجوال").task{await load()}}}
struct KinshipAdminScreen:View {@EnvironmentObject private var api:Backend;@State private var rows:[Item]=[]
    @State private var label=""
    @State private var generation=0
    @State private var reference=true
    @State private var error="";func load()async{do{rows=try await api.table("kinship_options",[q("select","*"),q("order","generation,label")])}catch{self.error=api.errorText(error)}};var body:some View{Form{LoadError(text:error);Section("إضافة صلة قرابة"){TextField("المسمى",text:$label);Stepper("الجيل: \(generation)",value:$generation,in:-4...4);Toggle("متاح لاختيار معرّف الأنثى",isOn:$reference);TaskButton(title:"إضافة",symbol:"plus"){guard !label.trimmingCharacters(in:.whitespaces).isEmpty,label.count<=60 else{return};_ = try await api.table("kinship_options",method:"POST",body:["code":"relation_"+UUID().uuidString.replacingOccurrences(of:"-",with:""),"label":label,"generation":generation,"for_reference":reference,"enabled":true]);label="";await load()}};Section("الخيارات الحالية"){ForEach(rows,id:\.rawCode){r in NavigationLink{KinshipEditor(item:r)}label:{Text(r.text("label")+(r.flag("enabled") ? "":" · معطّل"))}}}}.navigationTitle("خيارات القرابة").task{await load()}}}
struct KinshipEditor:View {@EnvironmentObject private var api:Backend;@Environment(\.dismiss)private var dismiss;let item:Item;@State private var label=""
    @State private var generation=0
    @State private var reference=false
    @State private var allowChat=false
    @State private var enabled=true;var body:some View{Form{TextField("المسمى",text:$label);Stepper("الجيل: \(generation)",value:$generation,in:-4...4);Toggle("متاح للمعرّف",isOn:$reference);Toggle("استثناء الخاص بعد تأكيد القرابة",isOn:$allowChat);Toggle("مفعّل",isOn:$enabled);TaskButton(title:"حفظ",symbol:"checkmark"){guard !label.isEmpty,label.count<=60 else{return};_ = try await api.table("kinship_options",[q("code","eq."+item.text("code"))],method:"PATCH",body:["label":label,"generation":generation,"for_reference":reference,"enabled":enabled,"allow_private_chat":allowChat]);dismiss()}}.navigationTitle("تعديل القرابة").task{label=item.text("label");generation=item.number("generation");reference=item.flag("for_reference");enabled=item.flag("enabled");allowChat=item.flag("allow_private_chat")}}}
struct AdsAdminScreen:View {@EnvironmentObject private var api:Backend;@State private var ads:[Item]=[]
    @State private var error=""
    @State private var edit:Item?
    @State private var deleting:Item?;func load()async{do{ads=try await api.table("announcements",[q("select","*"),q("order","created_at.desc"),q("limit","2000")]);error=""}catch{self.error=api.errorText(error)}};var body:some View{List{LoadError(text:error);ForEach(ads){ad in Button{edit=ad}label:{VStack(alignment:.leading,spacing:6){Text(ad.text("title")).font(.headline);Text(ad.flag("enabled") ? "مفعّل":"متوقف").font(.caption);Text(dateValue(ad.text("starts_at")),style:.date).font(.caption).foregroundStyle(.secondary)}}.swipeActions{Button("حذف",role:.destructive){deleting=ad}}}}.navigationTitle("الإعلانات").toolbar{ToolbarItem(placement:.navigationBarTrailing){Button{edit=Item(["id":"new"])}label:{Image(systemName:"plus")}}}.task{await load()}.sheet(item:$edit){ad in NavigationStack{AdEditor(ad:ad.id=="new" ? nil:ad){await load()}}}.confirmationDialog("حذف الإعلان نهائيًا؟",isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button("حذف",role:.destructive){guard let ad=deleting else{return};deleting=nil;Task{do{_ = try await api.table("announcements",[q("id","eq."+ad.id)],method:"DELETE");await load()}catch{self.error=api.errorText(error)}}}}}}
struct AdEditor:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.dismiss)private var dismiss
    let ad:Item?
    let saved:()async->Void
    @State private var title=""
    @State private var bodyText=""
    @State private var category="general"
    @State private var start=Date()
    @State private var end=Date().addingTimeInterval(86400)
    @State private var enabled=true
    @State private var contactID=""
    @State private var contactName=""
    @State private var term=""
    @State private var people:[Item]=[]
    @State private var searchError=""
    @State private var popup=false
    @State private var seconds=8
    @State private var days=1
    @State private var imagePath=""
    @State private var promoPhoto:PhotosPickerItem?
    @State private var promoData:Data?
    @State private var photoError=""
    @State private var loadingPhoto=false
    var body:some View {
        Form{
            Section("الإعلان"){TextField("عنوان الإعلان",text:$title);TextField("التفاصيل",text:$bodyText,axis:.vertical).lineLimit(3...10);Picker("النوع",selection:$category){Text("عام").tag("general");Text("زواج").tag("wedding");Text("وفاة").tag("death");Text("تجاري").tag("commercial");Text("عاجل").tag("urgent");Text("تبرع").tag("donation")};DatePicker("بداية العرض",selection:$start);DatePicker("نهاية العرض",selection:$end);Toggle("مفعّل",isOn:$enabled)}
            Section("إعلان دعائي بعد الدخول"){
                Toggle("صورة على كامل الشاشة",isOn:$popup)
                if popup{
                    if let data=promoData,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:240)}else if !imagePath.isEmpty{PrivateImage(path:imagePath,bucket:"ad-images",fill:false).frame(height:240)}
                    PhotosPicker(selection:$promoPhoto,matching:.images){Label("اختيار صورة الإعلان",systemImage:"photo")}
                    if loadingPhoto{ProgressView()};LoadError(text:photoError)
                    Stepper("مدة العرض: \(seconds) ثانية",value:$seconds,in:1...300)
                    Stepper("يتكرر كل \(days) يوم",value:$days,in:1...3650)
                    Text("يمكن إغلاقه فورًا بعلامة × أو اختيار عدم إظهاره مجددًا. تُحفظ رغبة العضو في حسابه. الصورة كاملة دون قص.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("تواصل مع المعني بالإعلان · اختياري"){
                if !contactID.isEmpty{Label("@"+(contactName.isEmpty ? "العضو المحدد":contactName),systemImage:"person.crop.circle.fill");Button("إزالة جهة التواصل",role:.destructive){contactID="";contactName=""}}
                Button("أنا المعني بالإعلان"){contactID=api.user.id;contactName=api.profile.text("display_name");people=[];term=""}
                TextField("@ أو بداية اسم العضو",text:$term).task(id:term){do{try await Task.sleep(nanoseconds:200_000_000);try Task.checkCancellation();let rows=Item.items(try await api.rpc("mention_search",["term":term.replacingOccurrences(of:"@",with:"")]));try Task.checkCancellation();people=rows;searchError=""}catch{if !Task.isCancelled{searchError=api.errorText(error)}}}
                LoadError(text:searchError)
                ForEach(people){person in Button{contactID=person.id;contactName=person.text("display_name");people=[]}label:{Label(person.text("display_name"),systemImage:contactID==person.id ? "checkmark.circle.fill":"at")}}
                Text("يفتح زر التواصل المحادثة الخاصة مباشرة، مع تطبيق ضوابط الدردشة الحالية.").font(.caption).foregroundStyle(.secondary)
            }
            TaskButton(title:"حفظ الإعلان",symbol:"checkmark"){
                guard title.count>=3,title.count<=250,!bodyText.isEmpty,bodyText.count<=5000,end>start else{throw FamilyError(text:"تحقق من العنوان والتفاصيل وفترة العرض.")}
                guard !loadingPhoto else{throw FamilyError(text:"انتظر تجهيز الصورة.")}
                if popup && promoData==nil && imagePath.isEmpty{throw FamilyError(text:"اختر صورة الإعلان الدعائي.")}
                var uploaded:String?
                if popup,let data=promoData{let path=try await api.upload(data,bucket:"ad-images",preserveAspect:true);uploaded=path}
                var values:[String:Any]=["is_popup":popup,"image_path":(uploaded ?? imagePath).isEmpty ? NSNull():(uploaded ?? imagePath) as Any,"display_seconds":seconds,"repeat_days":days,"title":title,"body":bodyText,"category":category,"starts_at":ISO8601DateFormatter().string(from:start),"ends_at":ISO8601DateFormatter().string(from:end),"enabled":enabled,"contact_member_id":contactID.isEmpty ? NSNull():contactID as Any]
                do{let rows:[Item];if let ad=ad{rows=try await api.table("announcements",[q("id","eq."+ad.id)],method:"PATCH",body:values)}else{values["author_id"]=api.user.id;rows=try await api.table("announcements",method:"POST",body:values)}
                guard !rows.isEmpty else{throw FamilyError(text:"لم يُحفظ الإعلان. تحقق من صلاحياتك.")};await saved();dismiss()
                }catch{if let path=uploaded{_ = try? await api.request("/storage/v1/object/ad-images",method:"DELETE",body:["prefixes":[path]])};throw error}
            }
        }.onChange(of:promoPhoto){_,item in Task{loadingPhoto=true;defer{loadingPhoto=false};do{guard let data=try await item?.loadTransferable(type:Data.self),data.count<=20*1024*1024,UIImage(data:data) != nil else{throw FamilyError(text:"اختر صورة صالحة أقل من 20 ميجابايت.")};promoData=data;photoError=""}catch{photoError=api.errorText(error)}}}.navigationTitle("إعلان العائلة").toolbar{ToolbarItem(placement:.cancellationAction){Button("إلغاء"){dismiss()}}}.task{
            if let ad=ad{title=ad.text("title");bodyText=ad.text("body");category=ad.text("category");start=dateValue(ad.text("starts_at"));end=dateValue(ad.text("ends_at"));enabled=ad.flag("enabled");popup=ad.flag("is_popup");seconds=ad.number("display_seconds");days=ad.number("repeat_days");imagePath=ad.text("image_path");contactID=ad.text("contact_member_id");if !contactID.isEmpty{contactName=((try? await api.table("profiles",[q("select","display_name"),q("id","eq."+contactID)]))?.first?.text("display_name")) ?? ""}}
        }
    }
}
struct ImageCandidate:Identifiable {let info:Item;let data:Data;var id:String{info.text("bucket")+"/"+info.text("path")}}
struct StorageScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var usage=Item()
    @State private var preview=Item()
    @State private var images:[ImageCandidate]=[]
    @State private var error=""
    @State private var notice=""
    @State private var plan="free"
    @State private var dbLimit="500"
    @State private var fileLimit="1024"
    @State private var confirmChat=false
    @State private var confirmImages=false
    @State private var busy=false
    func bytes(_ n:Int)->String{ByteCountFormatter.string(fromByteCount:Int64(n),countStyle:.binary)}
    func load()async{do{usage=Item(try await api.action("storage_maintenance","usage") as? [String:Any] ?? [:]);let limits=usage.child("limits");plan=limits.text("plan");dbLimit=String(limits.number("database_limit")/1048576);fileLimit=String(limits.number("file_limit")/1048576);error=""}catch{self.error=api.errorText(error)}}
    var body:some View{List{LoadError(text:error);if !notice.isEmpty{Text(notice).font(.footnote).foregroundStyle(brandBlue)};Section("قياس المشروع"){meter("قاعدة البيانات",used:usage.number("database_bytes"),limit:usage.child("limits").number("database_limit"));meter("الصور والملفات",used:usage.number("storage_bytes"),limit:usage.child("limits").number("file_limit"));Text("الحدود مرجعية وليست قراءة للفوترة، وقد تُشارك حصة الملفات مع مشاريع المنظمة. لا يتم تفعيل خدمة مدفوعة.").font(.caption).foregroundStyle(.secondary);ForEach(["users","news","comments","messages"],id:\.self){key in Text((key=="users" ? "الأعضاء":key=="news" ? "الأخبار":key=="comments" ? "التعليقات":"الرسائل")+": \(usage.child("records").number(key))")};TaskButton(title:"تحديث القياس",symbol:"arrow.clockwise"){await load()}}
        Section("الحدود المرجعية للعرض"){Picker("مرجع الخطة",selection:$plan){Text("مجاني").tag("free");Text("مدفوع").tag("pro");Text("مخصص").tag("custom")};TextField("حصة القاعدة بالميجابايت",text:$dbLimit).keyboardType(.numberPad);TextField("حصة الملفات بالميجابايت",text:$fileLimit).keyboardType(.numberPad);TaskButton(title:"حفظ مرجع الحدود"){guard let db=Int(dbLimit),let files=Int(fileLimit),db>0,files>0,db<=100000000,files<=100000000 else{return};_ = try await api.action("storage_maintenance","limits",["plan":plan,"database_limit":db*1048576,"file_limit":files*1048576]);await load()}}
        Section("الدردشات الخاملة"){Text("يحذف الرسائل فقط إذا مرّ أكثر من 10 أشهر على آخر رسالة في المحادثة. رسائل المحادثات النشطة محفوظة.").font(.footnote);TaskButton(title:"معاينة الدردشات القديمة",symbol:"clock"){preview=Item(try await api.action("storage_maintenance","preview") as? [String:Any] ?? [:])};if !preview.raw.isEmpty{Text("\(preview.number("rooms")) محادثة · \(preview.number("messages")) رسالة");Button("تأكيد الحذف النهائي",role:.destructive){confirmChat=true}.disabled(preview.number("messages")==0 || busy)}}
        Section("ضغط الصور"){Text("المشروع المستضيف وحدوده الفعلية مشتركة بين الكيانات. سجلات الأخبار والأعضاء المعروضة تخص عائلتك.").font(.footnote);Text("يفحص حتى 50 صورة ويستبدل بعد موافقتك فقط الصور التي توفر 15٪ على الأقل. قد تنخفض جودتها ولا يمكن التراجع عن الاستبدال.").font(.footnote);TaskButton(title:"فحص الصور",symbol:"photo"){guard !busy else{return};busy=true;defer{busy=false};images=[];let candidates=Item.items(try await api.action("storage_maintenance","images")).filter{$0.number("bytes")>30000}.prefix(50);for info in candidates{try Task.checkCancellation();let data=try await api.signedData(bucket:info.text("bucket"),path:info.text("path"));if let image=UIImage(data:data){let longest:CGFloat=info.text("bucket")=="profile-images" ? 512:1280;let scale=min(1,longest/max(image.size.width,image.size.height));let size=CGSize(width:image.size.width*scale,height:image.size.height*scale);let f=UIGraphicsImageRendererFormat();f.scale=1;f.opaque=true;let resized=UIGraphicsImageRenderer(size:size,format:f).image{ctx in UIColor.white.setFill();ctx.fill(CGRect(origin:.zero,size:size));image.draw(in:CGRect(origin:.zero,size:size))};if let jpg=resized.jpegData(compressionQuality:0.72),jpg.count<Int(Double(info.number("bytes"))*0.85){images.append(ImageCandidate(info:info,data:jpg))}}};notice="انتهى الفحص دون تغيير الصور."};if let sample=images.first,let img=UIImage(data:sample.data){Image(uiImage:img).resizable().scaledToFit().frame(maxHeight:180);Text("\(images.count) صورة قابلة للضغط · وفر متوقع "+bytes(images.reduce(0){$0+$1.info.number("bytes")-$1.data.count})).font(.caption);Button("تأكيد ضغط الصور"){confirmImages=true}.disabled(busy)}}
    }.scrollIndicators(.hidden).navigationTitle("البيانات والمساحة").task{await load()}.onChange(of:plan){_,p in if p=="free"{dbLimit="500";fileLimit="1024"}else if p=="pro"{dbLimit="8192";fileLimit="102400"}}.confirmationDialog("حذف نهائي للرسائل الخاملة؟ يُعاد التحقق من آخر نشاط داخل الخادم.",isPresented:$confirmChat){Button("حذف الرسائل الخاملة",role:.destructive){Task{busy=true;defer{busy=false};do{let r=Item(try await api.action("storage_maintenance","clean_chats",["confirm":"DELETE_OLD_CHATS"]) as? [String:Any] ?? [:]);let paths=r.raw["media_paths"] as? [String] ?? [];for i in stride(from:0,to:paths.count,by:500){_ = try await api.request("/functions/v1/family-storage",method:"POST",body:["action":"remove_old_media","paths":Array(paths[i..<min(i+500,paths.count)])])};notice="حُذفت \(r.number("messages")) رسالة.";preview=Item();await load()}catch{self.error=api.errorText(error)}}}}.confirmationDialog("استبدال الصور بنسخ مضغوطة أقل جودة؟",isPresented:$confirmImages){Button("تأكيد الضغط",role:.destructive){Task{busy=true;defer{busy=false};do{for candidate in images{_ = try await api.request("/functions/v1/family-storage",method:"POST",body:["action":"compress","bucket":candidate.info.text("bucket"),"path":candidate.info.text("path"),"expected_bytes":candidate.info.number("bytes"),"data":candidate.data.base64EncodedString()])};images=[];notice="اكتمل ضغط الصور.";await load()}catch{images=[];self.error=api.errorText(error)}}}}}
    func meter(_ title:String,used:Int,limit:Int)->some View{VStack(alignment:.leading,spacing:8){Text(title).font(.headline);Text(bytes(used)+" مستخدم · "+bytes(max(0,limit-used))+" متبقٍ").font(.caption);ProgressView(value:Double(min(used,max(limit,1))),total:Double(max(limit,1))).tint(brandBlue)}.padding(.vertical,8)}
}

struct KinshipReviewScreen:View {
    @EnvironmentObject private var api:Backend
    @State private var rows:[Item]=[]
    @State private var error=""
    func load()async{do{rows=Item.items(try await api.action("family_action","admin_kinship_list"))}catch{self.error=api.errorText(error)}}
    var body:some View{List{Text("تأكيدك لصحة القرابة قد يفتح استثناء الدردشة الخاصة وفق ضوابط العائلة.").font(.footnote);LoadError(text:error);ForEach(rows){r in VStack(alignment:.leading,spacing:12){Text(r.text("display_name")+" · "+r.text("label")+" · "+r.text("member_name"));TaskButton(title:"أؤكد صحة القرابة",symbol:"checkmark.shield"){_ = try await api.action("family_action","admin_kinship_confirm",["owner":r.text("owner_id"),"member":r.text("member_id")]);await load()}.disabled(api.readOnly);TaskButton(title:"رفض",symbol:"xmark"){_ = try await api.action("family_action","admin_kinship_reject",["owner":r.text("owner_id"),"member":r.text("member_id")]);await load()}.disabled(api.readOnly)}}}.navigationTitle("تأكيد القرابة").task{await load()}}
}

struct FamilyAdminDashboard:View {
    @EnvironmentObject private var api:Backend
    @Environment(\.scenePhase)private var phase
    var maintenance:String?=nil
    @State private var data=Item()
    @State private var error=""
    @State private var name=""
    @State private var photo:PhotosPickerItem?
    @State private var logo=""
    let keys=["chat_enabled","public_chat_enabled","private_chat_enabled","restrict_gender_chat","allow_groups","journalist_approval","auto_activate","endorsements_enabled"]
    let labels=["تشغيل الدردشة","الدردشة العامة","الخاص","منع التواصل بين الجنسين","إنشاء المجموعات","موافقة المدير على أخبار الصحفي","التفعيل حسب العوائل","التعريف بالأعضاء"]
    @State private var settings:[String:Bool]=[:]
    func call(_ action:String,_ payload:[String:Any]=[:])async throws->Any{var p=payload;if let maintenance{p["maintenance"]=maintenance};return try await api.action("family_admin",action,p)}
    func load()async{do{let result=Item(try await call("overview")as? [String:Any] ?? [:]);if data.raw.isEmpty{name=result.child("family").text("name");settings=Dictionary(uniqueKeysWithValues:keys.map{($0,result.child("settings").flag($0))})};data=result;error=""}catch{data=Item();self.error=api.errorText(error)}}
    var summary:some View{Section("الكيان والاشتراك"){Text(data.child("family").text("name")).font(.headline);Text("الكود "+data.child("family").text("code"));Text(lifecycleDescription(data.child("lifecycle"))).font(.footnote);ForEach([("members","الأعضاء"),("pending","قيد الاعتماد"),("news","الأخبار"),("messages","الرسائل")],id:\.0){key,label in LabeledContent(label,value:String(data.number(key)))};NavigationLink("الأعضاء والإضافة اليدوية"){PreparedMembersScreen(maintenance:maintenance)}}}
    var links:some View{Section("إدارة العائلة"){NavigationLink("الأعضاء والصلاحيات"){MembersScreen()};NavigationLink("مراجعة الأخبار"){NewsScreen(scope:.review)};NavigationLink("الأخبار المخفية"){NewsScreen(scope:.hidden)};NavigationLink("الإعلانات"){AdsAdminScreen()};NavigationLink("أسماء العوائل والتعريف"){SettingsScreen()};NavigationLink("خيارات القرابة"){KinshipAdminScreen()};NavigationLink("طلبات تغيير الجوال"){PhoneRequestsScreen()};NavigationLink("المساحة"){StorageScreen()};NavigationLink("طلبات صيانة المنصة"){FamilyMaintenanceScreen()}}}
    var identity:some View{Section("هوية العائلة"){TextField("اسم العائلة",text:$name);PhotosPicker(selection:$photo,matching:.images){Label("تغيير الشعار والألوان",systemImage:"photo")};TaskButton(title:"حفظ الهوية",symbol:"checkmark"){var p:[String:Any]=["name":name];if !logo.isEmpty{p["logo"]=logo};_ = try await call("branding",p);if maintenance==nil{try await api.loadAccount()};await load()}.disabled(data.child("lifecycle").flag("read_only"))}}
    var controls:some View{Section("النشر والدردشة"){ForEach(keys.indices,id:\.self){i in Toggle(labels[i],isOn:Binding(get:{settings[keys[i]] ?? false},set:{settings[keys[i]]=$0})).disabled(data.child("lifecycle").flag("read_only"))};TaskButton(title:"حفظ الضوابط",symbol:"checkmark"){_ = try await call("settings",["settings":settings]);await load()}.disabled(data.child("lifecycle").flag("read_only"))}}
    var invoices:some View{Section("الفواتير"){ForEach(data.rows("invoices")){i in VStack(alignment:.leading){Text(i.text("plan_name"));Text(i.text("amount_sar")+" ر.س · "+i.text("status")).font(.caption)}};Text("للتجديد تواصل مع إدارة المنصة. لا توجد بوابة دفع إلكتروني مفعّلة.").font(.footnote)}}
    var audit:some View{Section("سجل الإدارة والصيانة"){ForEach(data.rows("audit").indices,id:\.self){i in let row=data.rows("audit")[i];Text(row.text("action")+" · "+dateValue(row.text("created_at")).formatted()).font(.caption)}}}
    var body:some View{Form{LoadError(text:error);if !data.raw.isEmpty{summary;if maintenance==nil{links}else{NavigationLink("مراجعة أخبار الكيان"){ScopedNewsAdminScreen(maintenance:maintenance!)}};identity;controls;invoices;audit}}.navigationTitle(maintenance==nil ? "لوحة إدارة العائلة":"صيانة العائلة").refreshable{await load()}.task(id:phase){guard phase == .active else{if maintenance != nil{data=Item()};return};await load();if maintenance != nil{while !Task.isCancelled{do{try await Task.sleep(nanoseconds:15_000_000_000)}catch{break};await load()}}}.onChange(of:photo){_,item in Task{do{guard let bytes=try await item?.loadTransferable(type:Data.self),bytes.count<=20*1024*1024,let image=UIImage(data:bytes)else{throw FamilyError(text:"اختر شعارًا صالحًا")};let scale=min(1,512/max(image.size.width,image.size.height));let size=CGSize(width:image.size.width*scale,height:image.size.height*scale);let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true;let output=UIGraphicsImageRenderer(size:size,format:format).image{ctx in UIColor.white.setFill();ctx.fill(CGRect(origin:.zero,size:size));image.draw(in:CGRect(origin:.zero,size:size))};guard let encoded=output.jpegData(compressionQuality:0.72),encoded.count<200000 else{throw FamilyError(text:"اختر شعارًا أصغر")};logo="data:image/jpeg;base64,"+encoded.base64EncodedString()}catch{self.error=api.errorText(error)}}}.privacySensitive()}
}
func lifecycleDescription(_ s:Item)->String{var text=s.flag("trial") ? "تجربة مجانية حتى "+dateValue(s.text("trial_ends_at")).formatted():s.text("subscription_ends_at").isEmpty ? "الكيان مفعّل":"الاشتراك حتى "+dateValue(s.text("subscription_ends_at")).formatted();if s.flag("read_only"){text+=" · للاطلاع فقط؛ جدد الاشتراك لاستعادة الإضافة والدردشة."};if !s.text("delete_after").isEmpty{text+=" · الحذف النهائي لكل الصور والبيانات: "+dateValue(s.text("delete_after")).formatted()}else if !s.text("renewal_notice_due").isEmpty{text+=" · بعد انتهاء الاشتراك: 6 أشهر للاطلاع ثم رسالة تجديد، والحذف بعد إرسالها بـ15 يومًا دون تجديد."};return text}
struct PreparedMembersScreen:View {
    @EnvironmentObject private var api:Backend
    var maintenance:String?=nil
    @State private var rows=Item()
    @State private var error=""
    @State private var full=""
    @State private var email=""
    @State private var mobile=""
    @State private var gender="male"
    @State private var role="member"
    @State private var term=""
    func call(_ action:String,_ payload:[String:Any]=[:])async throws->Any{var p=payload;if let maintenance{p["maintenance"]=maintenance};return try await api.action("family_admin",action,p)}
    func load()async{do{rows=Item(try await call("members")as? [String:Any] ?? [:]);error=""}catch{rows=Item();self.error=api.errorText(error)}}
    var add:some View{Section("إضافة عضو يدويًا"){Text("يُضاف العضو بصلاحيته، ثم يكمل التسجيل بالبريد نفسه ويؤكده قبل الدخول. لا نستخدم كلمة مرور مشتركة.").font(.footnote);TextField("الاسم الرباعي",text:$full);TextField("البريد",text:$email).keyboardType(.emailAddress).textInputAutocapitalization(.never);TextField("الجوال",text:$mobile).keyboardType(.phonePad);Picker("الجنس",selection:$gender){Text("ذكر").tag("male");Text("أنثى").tag("female")};Picker("الصلاحية",selection:$role){Text("عضو").tag("member");Text("صحفي").tag("journalist");Text("مدير").tag("admin")};TaskButton(title:"إضافة العضو",symbol:"person.badge.plus"){_ = try await call("member_add",["full_name":full,"email":email,"phone":try phone(mobile),"gender":gender,"role":role]);full="";email="";mobile="";await load()}}}
    var body:some View{Form{LoadError(text:error);add;Section("بانتظار إكمال التسجيل"){ForEach(rows.rows("prepared")){p in VStack(alignment:.leading){Text(p.text("full_name"));Text(p.text("email")).font(.caption);TaskButton(title:"إلغاء الإضافة",symbol:"xmark"){_ = try await call("member_cancel",["id":p.id]);await load()}}}};Section("الأعضاء والصلاحيات"){ForEach(rows.rows("members").filter{term.isEmpty || [$0.text("display_name"),$0.text("phone"),$0.text("email")].joined(separator:" ").contains(term)}){p in NavigationLink{ScopedMemberEditor(member:p,maintenance:maintenance)}label:{VStack(alignment:.leading){Text(p.text("display_name"));Text(p.text("phone")+" · "+p.text("email")).font(.caption)}}}}}.navigationTitle("إدارة الأعضاء").searchable(text:$term,prompt:"الاسم أو الجوال أو البريد").task{await load()}.refreshable{await load()}}
}
struct ScopedMemberEditor:View {
    @EnvironmentObject private var api:Backend
    let member:Item
    var maintenance:String?=nil
    @State private var role="member"
    @State private var status="pending"
    @State private var notice=""
    var body:some View{Form{Text(member.text("display_name")).font(.headline);Text(member.text("email"));Picker("الدور",selection:$role){Text("عضو").tag("member");Text("صحفي").tag("journalist");Text("مدير").tag("admin")};Picker("الحالة",selection:$status){Text("معتمد").tag("active");Text("بانتظار الاعتماد").tag("pending");Text("موقوف").tag("suspended")};TaskButton(title:"حفظ",symbol:"checkmark"){var p:[String:Any]=["id":member.id,"role":role,"status":status];if let maintenance{p["maintenance"]=maintenance};_ = try await api.action("family_admin","member_update",p);notice="تم الحفظ"}.disabled(member.flag("is_root") || member.id==api.user.id);Text(notice)}.navigationTitle("صلاحية العضو").onAppear{role=member.text("role");status=member.text("status")}}

struct ScopedNewsAdminScreen:View {
 @EnvironmentObject private var api:Backend
 let maintenance:String
 @State private var rows:[Item]=[]
 @State private var error=""
 func load()async{do{rows=Item.items(try await api.action("family_admin","news",["maintenance":maintenance]));error=""}catch{rows=[];self.error=api.errorText(error)}}
 var body:some View{List{LoadError(text:error);ForEach(rows){p in VStack(alignment:.leading,spacing:10){Text(p.text("title")).font(.headline);Text(p.text("body"));TaskButton(title:p.flag("published") ? "إلغاء النشر":"اعتماد ونشر",symbol:"checkmark"){_ = try await api.action("family_admin","news_update",["maintenance":maintenance,"id":p.id,"published": !p.flag("published")]);await load()}}}}.navigationTitle("أخبار الكيان").task{await load()}.refreshable{await load()}}
}
