package org.polox.android;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Shows a notification Polox scheduled earlier (PoloxAndroid.schedule): it runs even when the game
 * is closed, because Android starts it from the alarm. Declared in this library's manifest
 * (src/main/AndroidManifest.xml), not exported: only this app's own alarms reach it.
 */
public final class MissYouReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context ctx, Intent intent) {
        try {
            if (intent == null || !PoloxAndroid.ACTION.equals(intent.getAction())) {
                return;
            }
            PoloxAndroid.notifyNow(ctx, intent.getIntExtra("id", 1), intent.getStringExtra("title"),
                    intent.getStringExtra("text"));
        } catch (Throwable t) {
            // A notification that can't be shown is simply not shown.
        }
    }
}
