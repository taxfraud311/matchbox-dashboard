package com.plinth.display;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Brings the display back after the tablet reboots (or the app is updated). */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Intent i = new Intent(context, MainActivity.class);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
        try {
            context.startActivity(i);
        } catch (Exception ignored) {
            // Background activity starts need SYSTEM_ALERT_WINDOW (granted by the Mac over adb);
            // otherwise the Mac relaunches the display as soon as USB comes up.
        }
    }
}
