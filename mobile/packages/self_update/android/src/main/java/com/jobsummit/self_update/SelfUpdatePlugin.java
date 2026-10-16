package com.jobsummit.self_update;

import android.app.ActivityManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.InstallSourceInfo;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.net.ConnectivityManager;
import android.os.Build;

import androidx.annotation.NonNull;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Installs JobSummit's own updates through a PackageInstaller session. On Android 12
 * and newer, Android lets an app update itself without asking once that app installed
 * the current version, so after the first tapped update the next ones are silent.
 * A plugin (not MainActivity code) so the background task's engine has it too.
 */
public class SelfUpdatePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Context context;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "jobsummit/self_update");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "status":
                result.success(status());
                break;
            case "install":
                try {
                    install(call.argument("path"), Boolean.TRUE.equals(call.argument("interactive")));
                    result.success(null);
                } catch (Exception e) {
                    result.error("install_failed", e.getMessage(), null);
                }
                break;
            default:
                result.notImplemented();
        }
    }

    @SuppressWarnings("deprecation") // getInstallerPackageName: the only way below Android 11
    private Map<String, Object> status() {
        PackageManager pm = context.getPackageManager();
        String self = context.getPackageName();
        boolean canInstall = pm.canRequestPackageInstalls();
        String installer = null;
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                InstallSourceInfo info = pm.getInstallSourceInfo(self);
                installer = info.getInstallingPackageName();
            } else {
                installer = pm.getInstallerPackageName(self);
            }
        } catch (Exception ignored) {
            // Unknown: treated as "not installed by itself", so Android will ask.
        }
        boolean selfInstalled = self.equals(installer);

        ActivityManager.RunningAppProcessInfo me = new ActivityManager.RunningAppProcessInfo();
        ActivityManager.getMyMemoryState(me);
        ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);

        Map<String, Object> m = new HashMap<>();
        m.put("sdk", Build.VERSION.SDK_INT);
        m.put("canInstall", canInstall);
        m.put("selfInstalled", selfInstalled);
        m.put("silent", Build.VERSION.SDK_INT >= 31 && canInstall && selfInstalled);
        m.put("unmetered", cm != null && cm.getActiveNetwork() != null && !cm.isActiveNetworkMetered());
        m.put("appVisible", me.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE);
        m.put("updatesDir", new File(context.getCacheDir(), "updates").getAbsolutePath());
        return m;
    }

    private void install(String path, boolean interactive) throws Exception {
        File apk = new File(path);
        PackageInstaller installer = context.getPackageManager().getPackageInstaller();
        PackageInstaller.SessionParams params =
                new PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL);
        params.setAppPackageName(context.getPackageName());
        params.setSize(apk.length());
        params.setInstallReason(PackageManager.INSTALL_REASON_USER);
        if (Build.VERSION.SDK_INT >= 31) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED);
        }
        int id = installer.createSession(params);
        boolean committed = false;
        try (PackageInstaller.Session session = installer.openSession(id)) {
            try (InputStream in = new FileInputStream(apk);
                 OutputStream out = session.openWrite("base.apk", 0, apk.length())) {
                byte[] buffer = new byte[64 * 1024];
                int n;
                while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
                session.fsync(out);
            }
            Intent done = new Intent(context, InstallResultReceiver.class)
                    .putExtra(InstallResultReceiver.EXTRA_INTERACTIVE, interactive);
            // Mutable: the installer adds the result (status, confirm intent) to it.
            int flags = PendingIntent.FLAG_UPDATE_CURRENT
                    | (Build.VERSION.SDK_INT >= 31 ? PendingIntent.FLAG_MUTABLE : 0);
            session.commit(PendingIntent.getBroadcast(context, id, done, flags).getIntentSender());
            committed = true;
        } finally {
            if (!committed) installer.abandonSession(id);
        }
    }
}
