package com.libanapps.chat;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * LibanApps Chat — غلاف بسيط حوالين https://libanapps.com/chat
 * + إشعارات أصلية للرسائل الجديدة (عبر الجسر LibanAppsChat.notify)
 */
public class MainActivity extends Activity {
    static final String HOME = "https://libanapps.com/chat";
    static final String CH = "wachat_msgs";
    WebView web;
    boolean visible = false;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        web = new WebView(this);
        setContentView(web);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setUserAgentString(s.getUserAgentString() + " LibanAppsChat/1");
        web.addJavascriptInterface(new Bridge(), "LibanAppsChat");
        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                Uri u = r.getUrl();
                if ("libanapps.com".equals(u.getHost()) && u.getPath() != null && u.getPath().startsWith("/chat")) return false;
                // أي رابط تاني (واتساب، صور، ملفات) بيفتح برّا التطبيق
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception e) { }
                return true;
            }
        });
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel c = new NotificationChannel(CH, "الرسائل", NotificationManager.IMPORTANCE_HIGH);
            c.enableVibration(true);
            ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE)).createNotificationChannel(c);
        }
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, 1);
        if (b != null) web.restoreState(b); else web.loadUrl(HOME);
        handle(getIntent());
    }

    @Override protected void onSaveInstanceState(Bundle o) { super.onSaveInstanceState(o); web.saveState(o); }
    @Override protected void onNewIntent(Intent i) { super.onNewIntent(i); handle(i); }
    @Override protected void onResume() { super.onResume(); visible = true; web.onResume(); web.resumeTimers(); }
    @Override protected void onPause() { super.onPause(); visible = false; }   // منخلّي الـJS شغّال بالخلفية ليوصل الإشعار

    void handle(Intent i) {
        final String ph = i == null ? null : i.getStringExtra("phone");
        if (ph == null) return;
        web.postDelayed(() -> web.evaluateJavascript("window.wachatOpen&&window.wachatOpen('" + ph.replaceAll("\\D", "") + "')", null), 800);
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack(); else super.onBackPressed();
    }

    class Bridge {
        @JavascriptInterface
        public void notify(String title, String body, String phone) {
            if (visible) return;   // التطبيق قدّامك: ما في داعي لإشعار
            Intent it = new Intent(MainActivity.this, MainActivity.class);
            it.putExtra("phone", phone);
            it.setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(MainActivity.this, phone == null ? 0 : phone.hashCode(), it,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            Notification.Builder nb = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(MainActivity.this, CH) : new Notification.Builder(MainActivity.this);
            nb.setSmallIcon(android.R.drawable.stat_notify_chat).setContentTitle(title).setContentText(body)
              .setStyle(new Notification.BigTextStyle().bigText(body)).setAutoCancel(true).setContentIntent(pi);
            if (Build.VERSION.SDK_INT < 26) nb.setDefaults(Notification.DEFAULT_ALL).setPriority(Notification.PRIORITY_HIGH);
            ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE)).notify(phone == null ? 1 : phone.hashCode(), nb.build());
        }
        @JavascriptInterface
        public void setBadge(int n) { }
    }
}
