package com.martadha3li.familynews;
import android.content.ComponentName;
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
    private boolean enabled(PackageManager pm,ComponentName component,String name){
        int state=pm.getComponentEnabledSetting(component);
        return state==PackageManager.COMPONENT_ENABLED_STATE_ENABLED||(state==PackageManager.COMPONENT_ENABLED_STATE_DEFAULT&&"PlatformLauncher".equals(name));
    }
}
