from pathlib import Path
from PIL import Image
import json,plistlib,shutil
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[1]
icon=Image.open(root/'www/icon-512.png').convert('RGB')
android=root/'android/app/src/main/res'
if android.exists():
 gradle=root/'android/app/build.gradle'
 text=gradle.read_text().replace('versionCode 1','versionCode 6').replace('versionName "1.0"','versionName "1.4.0"');gradle.write_text(text)
 for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
  folder=android/('mipmap-'+density);folder.mkdir(parents=True,exist_ok=True)
  for name in ['ic_launcher.png','ic_launcher_round.png','ic_launcher_foreground.png']:icon.resize((size,size)).save(folder/name)
 for folder in ['mipmap-anydpi-v26']:
  for file in (android/folder).glob('ic_launcher*.xml'):file.unlink()
 # Native launcher aliases use packaged icons.
 strings=android/'values/strings.xml'
 if strings.exists():
  st=ET.parse(strings)
  for node in st.getroot().findall('string'):
   if node.get('name') in ['app_name','title_activity_main']:node.text='العوائل'
  st.write(strings,encoding='utf-8',xml_declaration=True)
 java=root/'android/app/src/main/java/com/martadha3li/familynews'
 java.mkdir(parents=True,exist_ok=True)
 for name in ['MainActivity.java','FamilyBrandPlugin.java']:shutil.copy(root/'branding'/name,java/name)
 (android/'drawable-nodpi').mkdir(exist_ok=True)
 Image.open(root/'www/family-01-icon-512.png').convert('RGB').save(android/'drawable-nodpi/family_01_icon.png')
 ns='http://schemas.android.com/apk/res/android';ET.register_namespace('android',ns)
 manifest=root/'android/app/src/main/AndroidManifest.xml';tree=ET.parse(manifest);app=tree.getroot().find('application')
 main=next(x for x in app.findall('activity')if x.get('{'+ns+'}name')=='.MainActivity')
 for filt in list(main.findall('intent-filter')):
  if any(x.get('{'+ns+'}name')=='android.intent.category.LAUNCHER' for x in filt.findall('category')):main.remove(filt)
 for item in list(app.findall('activity-alias')):
  if item.get('{'+ns+'}name')in['.PlatformLauncher','.Family01Launcher']:app.remove(item)
 for name,label,asset,enabled in [('PlatformLauncher','العوائل','@mipmap/ic_launcher','true'),('Family01Launcher','أخبار العائلة','@drawable/family_01_icon','false')]:
  alias=ET.SubElement(app,'activity-alias',{('{'+ns+'}'+k):v for k,v in dict(name='.'+name,targetActivity='.MainActivity',label=label,icon=asset,enabled=enabled,exported='true').items()})
  filt=ET.SubElement(alias,'intent-filter');ET.SubElement(filt,'action',{'{'+ns+'}name':'android.intent.action.MAIN'});ET.SubElement(filt,'category',{'{'+ns+'}name':'android.intent.category.LAUNCHER'})
 tree.write(manifest,encoding='utf-8',xml_declaration=True)
ios=root/'ios/App/App'
if ios.exists():
 p=ios/'Info.plist'
 settings=plistlib.loads(p.read_bytes())
 settings['CFBundleShortVersionString']='1.3.0'
 settings['CFBundleVersion']='5'
 settings['NSPhotoLibraryUsageDescription']='اختيار صورة لإرفاقها بخبر في أخبار العائلة.'
 settings.pop('NSMicrophoneUsageDescription',None)
 settings['NSCameraUsageDescription']='التقاط صورة لإرفاقها بخبر في أخبار العائلة.'
 settings['NSPhotoLibraryAddUsageDescription']='حفظ صورة تختارها من أخبار العائلة.'
 # SceneDelegate creates the CAPBridgeViewController window programmatically.
 # Loading Main.storyboard as well creates a second window/bridge in the scene,
 # which can leave the visible web view outside the keyboard's key window.
 if (ios/'SceneDelegate.swift').exists():
  settings.pop('UIMainStoryboardFile',None)
  for configurations in settings.get('UIApplicationSceneManifest',{}).get('UISceneConfigurations',{}).values():
   for configuration in configurations:
    configuration.pop('UISceneStoryboardFile',None)
 p.write_bytes(plistlib.dumps(settings))
 icons=ios/'Assets.xcassets/AppIcon.appiconset';icons.mkdir(parents=True,exist_ok=True)
 icon.resize((1024,1024)).save(icons/'AppIcon-1024.png')
 (icons/'Contents.json').write_text(json.dumps({'images':[{'idiom':'universal','platform':'ios','size':'1024x1024','filename':'AppIcon-1024.png'}],'info':{'author':'xcode','version':1}},indent=2))
print('Native app branding configured.')
