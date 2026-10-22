package com.martadha3li.familynews;
import android.os.Bundle;
import android.content.Intent;
import com.getcapacitor.BridgeActivity;
public class MainActivity extends BridgeActivity {
    @Override public void onCreate(Bundle savedInstanceState){registerPlugin(FamilyBrandPlugin.class);super.onCreate(savedInstanceState);}
    @Override public void onNewIntent(Intent intent){super.onNewIntent(intent);setIntent(intent);android.net.Uri uri=intent.getData();if(uri!=null&&"familynews".equals(uri.getScheme())&&"family".equals(uri.getHost())&&getBridge()!=null){getBridge().getWebView().post(()->getBridge().getWebView().evaluateJavascript("window.dispatchEvent(new Event('family:shortcut'))",null));}}
}

