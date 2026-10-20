package com.martadha3li.familynews;
import android.content.ComponentName;
import android.content.Intent;
import android.content.ClipData;
import android.net.Uri;
import android.util.Base64;
import androidx.core.content.FileProvider;
import java.io.File;
import java.io.FileOutputStream;
import java.util.UUID;
import android.content.pm.PackageManager;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
@CapacitorPlugin(name = "FamilyBrand")
public class FamilyBrandPlugin extends Plugin {
    @PluginMethod public void setFamilyIcon(PluginCall call) {
        final String selected = "01".equals(call.getString("code", "")) ? "Family01Launcher" : "PlatformLauncher";
        getActivity().runOnUiThread(() -> {
            try {
                PackageManager pm=getContext().getPackageManager();String pkg=getContext().getPackageName();
                ComponentName chosen=new ComponentName(pkg,pkg+"."+selected);
                if(!enabled(pm,chosen,selected))pm.setComponentEnabledSetting(chosen,PackageManager.COMPONENT_ENABLED_STATE_ENABLED,PackageManager.DONT_KILL_APP);
                for(String name:new String[]{"PlatformLauncher","Family01Launcher"}){
                    ComponentName other=new ComponentName(pkg,pkg+"."+name);
                    if(!name.equals(selected)&&enabled(pm,other,name))pm.setComponentEnabledSetting(other,PackageManager.COMPONENT_ENABLED_STATE_DISABLED,PackageManager.DONT_KILL_APP);
                }
                JSObject result=new JSObject();result.put("icon",selected);call.resolve(result);
            }catch(Exception error){call.reject("Could not update launcher icon",error);}
        });
    }
    @PluginMethod public void shareExport(PluginCall call) {
        try {
            String type=call.getString("type", ""),encoded=call.getString("data", "");
            if ((!"image/jpeg".equals(type)&&!"application/pdf".equals(type))||encoded.length()>44000000) {call.reject("Unsupported export");return;}
            byte[] bytes=Base64.decode(encoded,Base64.DEFAULT);
            boolean jpeg=bytes.length>3&&(bytes[0]&255)==255&&(bytes[1]&255)==216;
            boolean pdf=bytes.length>5&&bytes[0]==37&&bytes[1]==80&&bytes[2]==68&&bytes[3]==70;
            if(bytes.length>30000000||("image/jpeg".equals(type)?!jpeg:!pdf)){call.reject("Invalid export");return;}
            File folder=new File(getContext().getCacheDir(),"family-exports");if(!folder.exists()&&!folder.mkdirs()){call.reject("Export unavailable");return;}
            File[] previous=folder.listFiles();if(previous!=null)for(File item:previous)if(item.lastModified()<System.currentTimeMillis()-86400000L)item.delete();
            File file=new File(folder,"family-"+UUID.randomUUID()+(jpeg?".jpg":".pdf"));
            try(FileOutputStream output=new FileOutputStream(file)){output.write(bytes);}
            Uri uri=FileProvider.getUriForFile(getContext(),getContext().getPackageName()+".familyexports",file);
            getActivity().runOnUiThread(()->{try{Intent send=new Intent(Intent.ACTION_SEND);send.setType(type);send.putExtra(Intent.EXTRA_STREAM,uri);send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);send.setClipData(ClipData.newRawUri("family export",uri));getActivity().startActivity(Intent.createChooser(send,"مشاركة أو حفظ الملف"));call.resolve();}catch(Exception error){file.delete();call.reject("Sharing unavailable",error);}});
        }catch(Exception error){call.reject("Export unavailable",error);}
    }
    private boolean enabled(PackageManager pm,ComponentName component,String name){
        int state=pm.getComponentEnabledSetting(component);
        return state==PackageManager.COMPONENT_ENABLED_STATE_ENABLED||(state==PackageManager.COMPONENT_ENABLED_STATE_DEFAULT&&"PlatformLauncher".equals(name));
    }
}
