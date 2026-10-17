from pathlib import Path
from PIL import Image
import json,plistlib
root=Path(__file__).resolve().parents[1]
icon=Image.open(root/'www/icon-512.png').convert('RGB')
android=root/'android/app/src/main/res'
if android.exists():
 gradle=root/'android/app/build.gradle'
 text=gradle.read_text().replace('versionCode 1','versionCode 3').replace('versionName "1.0"','versionName "1.2.0"');gradle.write_text(text)
 for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
  folder=android/('mipmap-'+density);folder.mkdir(parents=True,exist_ok=True)
  for name in ['ic_launcher.png','ic_launcher_round.png','ic_launcher_foreground.png']:icon.resize((size,size)).save(folder/name)
 for folder in ['mipmap-anydpi-v26']:
  for file in (android/folder).glob('ic_launcher*.xml'):file.unlink()
ios=root/'ios/App/App'
if ios.exists():
 p=ios/'Info.plist'
 settings=plistlib.loads(p.read_bytes())
 settings['CFBundleShortVersionString']='1.2.0'
 settings['CFBundleVersion']='4'
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
