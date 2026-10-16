package com.jobsummit.self_update;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.os.Build;

/**
 * The installer's answer. Success needs nothing (Android restarts the app on the new
 * version). If Android wants a tap ("Update this app?"): open it right away when the
 * install was started from the app, otherwise post a notification to tap later.
 */
public class InstallResultReceiver extends BroadcastReceiver {
    static final String EXTRA_INTERACTIVE = "com.jobsummit.self_update.INTERACTIVE";
    private static final String CHANNEL = "app_updates";
    private static final int NOTIFICATION_ID = 7001;

    @Override
    @SuppressWarnings("deprecation") // untyped getParcelableExtra below Android 13
    public void onReceive(Context context, Intent intent) {
        int status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE);
        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            Intent confirm = Build.VERSION.SDK_INT >= 33
                    ? intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent.class)
                    : intent.getParcelableExtra(Intent.EXTRA_INTENT);
            if (confirm == null) return;
            confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            if (intent.getBooleanExtra(EXTRA_INTERACTIVE, false)) {
                try {
                    context.startActivity(confirm);
                    return;
                } catch (Exception ignored) {
                    // Not allowed right now (app left the screen): fall back to a notification.
                }
            }
            notifyTapToFinish(context, confirm);
        }
    }

    private static void notifyTapToFinish(Context context, Intent confirm) {
        NotificationManager nm = context.getSystemService(NotificationManager.class);
        if (nm == null) return;
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                    new NotificationChannel(CHANNEL, "App updates", NotificationManager.IMPORTANCE_DEFAULT));
        }
        PendingIntent tap = PendingIntent.getActivity(context, NOTIFICATION_ID, confirm,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        // The app's status-bar icon (kept from resource shrinking by res/raw/keep.xml).
        int icon = context.getResources().getIdentifier("ic_stat_jobsummit", "drawable", context.getPackageName());
        if (icon == 0) icon = context.getApplicationInfo().icon;
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(context, CHANNEL)
                : new Notification.Builder(context);
        builder.setSmallIcon(icon)
                .setContentTitle("JobSummit update ready")
                .setContentText("Tap to finish installing the new version.")
                .setContentIntent(tap)
                .setAutoCancel(true);
        try {
            nm.notify(NOTIFICATION_ID, builder.build());
        } catch (SecurityException ignored) {
            // Notifications switched off: the in-app prompt offers it next time.
        }
    }
}
