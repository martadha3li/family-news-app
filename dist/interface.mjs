// Shared vector icons: local assets, no icon fonts or third-party requests.
const paths={
 home:'<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z"/>',
 chat:'<path d="M21 11.5a8.5 8.5 0 0 1-12.3 7.6L3 21l1.9-5.7A8.5 8.5 0 1 1 21 11.5Z"/><path d="M8 11.5h8M8 8h5"/>',
 plus:'<rect x="3" y="3" width="18" height="18" rx="5"/><path d="M12 7v10M7 12h10"/>',
 user:'<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
 menu:'<path d="M4 6h16M4 12h16M4 18h16"/>',
 close:'<path d="m6 6 12 12M18 6 6 18"/>',
 logout:'<path d="M9 4H4v16h5M10 12h11m-4-4 4 4-4 4"/>',
 heart:'<path d="M20.8 4.6a5.6 5.6 0 0 0-7.9 0l-.9.9-.9-.9a5.6 5.6 0 0 0-7.9 7.9L12 21l8.8-8.5a5.6 5.6 0 0 0 0-7.9Z"/>',
 comment:'<path d="M21 11.5a9 9 0 0 1-9 9 9.5 9.5 0 0 1-4-.9L3 21l1.4-5a9 9 0 1 1 16.6-4.5Z"/>',
 search:'<circle cx="10.5" cy="10.5" r="7.5"/><path d="m16 16 5 5"/>',
 back:'<path d="m9 5 7 7-7 7"/>',
 send:'<path d="m21 3-7 18-4-7-7-4Z"/><path d="m10 14 11-11"/>',
 refresh:'<path d="M20 7v5h-5M4 17v-5h5"/><path d="M6 6a8 8 0 0 1 13 1l1 5M4 12l1 5a8 8 0 0 0 13 1"/>',
 people:'<circle cx="9" cy="8" r="3"/><path d="M3 21v-3a6 6 0 0 1 12 0v3M16 5a3 3 0 0 1 0 6M18 15a5 5 0 0 1 3 5"/>',
 settings:'<path d="M4 7h16M4 17h16"/><circle cx="8" cy="7" r="3"/><circle cx="16" cy="17" r="3"/>',
 bell:'<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
 check:'<path d="m5 12 4 4L19 6"/>',
 archive:'<path d="M4 8v13h16V8M3 3h18v5H3Z M9 12h6"/>',
 storage:'<ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 4 18 4 18 0V5M3 12c0 4 18 4 18 0"/>',
 edit:'<path d="m16 3 5 5-12 12-6 1 1-6Z M13 6l5 5"/>',
 hide:'<path d="m3 3 18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9 5a11 11 0 0 1 12 7 13 13 0 0 1-3 4M6 6a13 13 0 0 0-3 6 11 11 0 0 0 13 7"/>',
 trash:'<path d="M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7M14 10v7"/>',
 more:'<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
 info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7v.1"/>'
};
export function icon(name){const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox','0 0 24 24');svg.setAttribute('fill','none');svg.setAttribute('stroke','currentColor');svg.setAttribute('stroke-width','1.8');svg.setAttribute('stroke-linecap','round');svg.setAttribute('stroke-linejoin','round');svg.setAttribute('aria-hidden','true');svg.setAttribute('focusable','false');svg.classList.add('ui-icon');svg.innerHTML=paths[name]||paths.more;return svg;}
export function presentButton(node,name,label,{compact=false}={}){if(!node)return;const text=document.createElement('span');text.className=compact?'sr-only':'button-label';text.textContent=label;node.replaceChildren(icon(name),text);node.classList.add('icon-button');node.classList.toggle('icon-only',compact);node.setAttribute('aria-label',label);node.title=label;}
export function initInterface({$,state,showSection}){
 const controls=[['menu-open','menu','القائمة',true],['logout','logout','تسجيل الخروج',true],['profile-open','user','حسابي',true],['menu-close','close','إغلاق القائمة',true],['close-editor','close','إغلاق محرر الخبر',true],['profile-close','close','إغلاق ملفي',true],['refresh-feed','refresh','تحديث الأخبار',true],['news-tab','home','الأخبار'],['chat-tab','chat','الدردشات'],['new-post','plus','نشر خبر'],['members-tab','people','إدارة الأعضاء'],['announcements-tab','bell','الإعلانات'],['trash-tab','archive','الأخبار المخفية'],['review-tab','check','مراجعة الأخبار'],['settings-tab','settings','إعدادات العائلة'],['storage-tab','storage','البيانات والمساحة'],['chat-back','back','العودة للمحادثات',true],['group-info','info','معلومات المجموعة',true],['member-info','user','ملف العضو',true],['message-search-open','search','بحث في المحادثة',true],['chat-public','people','العامة'],['chat-private','user','خاصة'],['create-event','bell','إنشاء حدث']];
 for(const [id,name,label,compact]of controls)presentButton($(id),name,label,{compact});
 presentButton(document.querySelector('.chat-exit'),'back','الأخبار');
 presentButton($('chat-form').querySelector('button'),'send','إرسال الرسالة',{compact:true});
 const newGroup=[...document.querySelectorAll('.chat-layout aside button')].find(b=>b.textContent.includes('＋ مجموعة'));presentButton(newGroup,'plus','مجموعة جديدة');
 const drawer=$('nav-drawer');const drawerBrand=document.createElement('div');drawerBrand.className='drawer-brand';const brand=document.createElement('img');brand.src='/family-logo.png';brand.alt='أخبار العائلة';drawerBrand.append(brand);drawer.querySelector('.feed-heading').after(drawerBrand);
 const nav=document.createElement('nav');nav.id='mobile-navigation';nav.className='mobile-navigation';nav.setAttribute('aria-label','التنقل الرئيسي');nav.hidden=true;const shortcuts=[];
 for(const [id,name,label,action]of [['news','home','الأخبار',()=>$('news-tab').click()],['chat','chat','الدردشات',()=>$('chat-tab').click()],['create','plus','طلب خبر',()=>$('request-news-plus').click()],['profile','user','حسابي',()=>$('profile-open').click()],['menu','menu','المزيد',()=>$('menu-open').click()]]){const b=document.createElement('button');b.type='button';b.dataset.destination=id;presentButton(b,name,label);b.onclick=action;nav.append(b);shortcuts.push(b);}
 document.body.append(nav);
 // Touch focus stays native: no global touch handlers or keyboard overrides.
 for(const input of document.querySelectorAll('input[type="search"],#chat-search'))input.setAttribute('enterkeyhint','search');
 $('email').setAttribute('inputmode','email');$('email').setAttribute('autocapitalize','none');$('password').setAttribute('enterkeyhint','go');$('chat-body').setAttribute('enterkeyhint','send');
 $('profile-dialog').querySelector('h2').textContent='ملفي الشخصي';
 const profile=$('profile-dialog');profile.setAttribute('aria-label','ملفي الشخصي');$('editor').setAttribute('aria-label','تحرير خبر');drawer.setAttribute('aria-label','قائمة أخبار العائلة');
 function sync(section=state.uiSection||'news'){
  state.uiSection=section;const signed=!!state.user,active=signed&&state.profile?.status==='active';nav.hidden=!active;
  document.body.classList.toggle('signed-in',signed);document.body.classList.toggle('member-active',active);
  for(const b of shortcuts){const target=b.dataset.destination;b.hidden=false;b.classList.toggle('active',target===section);if(target===section)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');}
 }
 sync();return {sync};
}
