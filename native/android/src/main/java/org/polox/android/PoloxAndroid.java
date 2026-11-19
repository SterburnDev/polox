package org.polox.android;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.ApplicationExitInfo;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.view.Display;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import org.json.JSONArray;
import org.json.JSONObject;
import java.io.InputStream;
import java.io.ByteArrayOutputStream;
import android.util.Base64;

/**
 * Small Android helpers behind Polox's Godot plugin (PoloxAndroidPlugin hands them the game's activity),
 * built with Gradle into addons/polox_android/bin/PoloxAndroid.aar by tools/export_android.ps1.
 *
 * Every method catches everything: a phone that can't do something simply doesn't, and the game
 * carries on.
 */
public final class PoloxAndroid {
    static final String CHANNEL = "polox_friends";
    static final String ACTION = "org.polox.android.MISS_YOU";

    private PoloxAndroid() {
    }

    /** Android's own exit records survive a native crash that cannot run GDScript. */
    public static String recentCrashExits(Activity activity) {
        JSONArray out = new JSONArray();
        try {
            if (Build.VERSION.SDK_INT < 30 || activity == null) return out.toString();
            ActivityManager manager = (ActivityManager) activity.getSystemService(Context.ACTIVITY_SERVICE);
            long cutoff = System.currentTimeMillis() - 3L * 24 * 60 * 60 * 1000;
            // Android keeps these records across updates: an exit from before this install was an older build.
            long installed = 0;
            try {
                installed = packageInfo(activity).lastUpdateTime;
            } catch (Throwable ignored) { }
            for (ApplicationExitInfo exit : manager.getHistoricalProcessExitReasons(activity.getPackageName(), 0, 20)) {
                int reason = exit.getReason();
                // Exclude normal exits, user force-stops, updates and permission changes.
                if (exit.getTimestamp() < cutoff || !(reason == 2 || reason == 3 || reason == 4
                        || reason == 5 || reason == 6 || reason == 9 || reason == 13)) continue;
                JSONObject item = new JSONObject();
                item.put("timestamp_ms", exit.getTimestamp());
                item.put("reason", reason);
                item.put("status", exit.getStatus());
                item.put("pss_kb", exit.getPss());
                item.put("rss_kb", exit.getRss());
                item.put("importance", exit.getImportance());
                item.put("installed_ms", installed);
                byte[] tag = exit.getProcessStateSummary();   // the version the process tagged itself with
                if (tag != null && tag.length > 0) {
                    item.put("version", clip(new String(tag, java.nio.charset.StandardCharsets.UTF_8), 40));
                }
                String description = exit.getDescription();
                item.put("description", description == null ? "" : description.substring(0, Math.min(300, description.length())));
                // Android 12+ keeps a native tombstone (protobuf). It is read here, on the phone, down to
                // the crashing thread's stack and the last log lines, so the report stays small. The raw
                // start of the file goes along only when that summary has no stack in it.
                if (reason == 5 && Build.VERSION.SDK_INT >= 31) {
                    try (InputStream trace = exit.getTraceInputStream()) {
                        if (trace != null) {
                            byte[] data = readAtMost(trace, 8 * 1024 * 1024);
                            String text = tombstoneText(data);
                            item.put("trace_text", text);
                            if (!text.contains("#00 ")) {
                                int n = Math.min(data.length, 98304);
                                item.put("trace_base64", Base64.encodeToString(data, 0, n, Base64.NO_WRAP));
                                item.put("trace_format", "android_tombstone_proto");
                                item.put("trace_truncated", n < data.length);
                            }
                        }
                    } catch (Throwable ignored) { }
                }
                out.put(item);
                if (out.length() >= 5) break;
            }
        } catch (Throwable ignored) {
            // Older or restricted devices still start normally.
        }
        return out.toString();
    }

    static byte[] readAtMost(InputStream in, int limit) throws java.io.IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        byte[] buffer = new byte[16384];
        int count;
        while (bytes.size() < limit && (count = in.read(buffer, 0, Math.min(buffer.length, limit - bytes.size()))) > 0) {
            bytes.write(buffer, 0, count);
        }
        return bytes.toByteArray();
    }

    // --- Tombstone (system/core/debuggerd/proto/tombstone.proto) --------------------------------

    /** Just enough of the protobuf wire format to walk a tombstone; never reads past `end`. */
    static final class Pb {
        final byte[] b;
        final int end;
        int p;

        Pb(byte[] b, int start, int end) {
            this.b = b;
            this.p = start;
            this.end = end;
        }

        boolean more() {
            return p < end;
        }

        long varint() {
            long v = 0;
            for (int shift = 0; p < end && shift < 64; shift += 7) {
                int x = b[p++] & 0xff;
                v |= (long) (x & 0x7f) << shift;
                if ((x & 0x80) == 0) {
                    break;
                }
            }
            return v;
        }

        /** A length-delimited field: its sub-reader (bounded by this one). */
        Pb sub() {
            long n = varint();
            int s = p;
            int e = (int) Math.min((long) end, s + Math.max(0L, n));
            p = e;
            return new Pb(b, s, e);
        }

        String str() {
            Pb s = sub();
            return new String(b, s.p, s.end - s.p, java.nio.charset.StandardCharsets.UTF_8);
        }

        void skip(int wire) {
            if (wire == 0) {
                varint();
            } else if (wire == 1) {
                p = Math.min(end, p + 8);
            } else if (wire == 2) {
                sub();
            } else if (wire == 5) {
                p = Math.min(end, p + 4);
            } else {
                p = end;
            }
        }
    }

    static String clip(String s, int n) {
        s = s.replace('\n', ' ').replace('\r', ' ').replace('\t', ' ');
        return s.length() > n ? s.substring(0, n) : s;
    }

    /** "signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x10", the crashing thread's frames and
     *  the last log lines, at most 12000 characters ("" if it can't be read). */
    static String tombstoneText(byte[] data) {
        try {
            Pb t = new Pb(data, 0, data.length);
            long tid = -1;
            String signal = "";
            String abort = "";
            java.util.ArrayList<String> causes = new java.util.ArrayList<>();
            java.util.HashMap<Long, Pb> threads = new java.util.HashMap<>();
            java.util.ArrayList<Pb> logs = new java.util.ArrayList<>();
            while (t.more()) {
                long tag = t.varint();
                int field = (int) (tag >>> 3);
                int wire = (int) (tag & 7);
                if (field == 6 && wire == 0) {
                    tid = t.varint();
                } else if (field == 10 && wire == 2) {
                    signal = signalText(t.sub());
                } else if (field == 14 && wire == 2) {
                    abort = clip(t.str(), 300);
                } else if (field == 15 && wire == 2) {
                    Pb c = t.sub();
                    while (c.more()) {
                        long ct = c.varint();
                        if ((ct >>> 3) == 1 && (ct & 7) == 2) {
                            causes.add(clip(c.str(), 200));
                        } else {
                            c.skip((int) (ct & 7));
                        }
                    }
                } else if (field == 16 && wire == 2) {
                    Pb e = t.sub();
                    long key = -1;
                    Pb value = null;
                    while (e.more()) {
                        long et = e.varint();
                        if ((et >>> 3) == 1 && (et & 7) == 0) {
                            key = e.varint();
                        } else if ((et >>> 3) == 2 && (et & 7) == 2) {
                            value = e.sub();
                        } else {
                            e.skip((int) (et & 7));
                        }
                    }
                    if (value != null) {
                        threads.put(key, value);
                    }
                } else if (field == 18 && wire == 2) {
                    logs.add(t.sub());
                } else {
                    t.skip(wire);
                }
            }
            StringBuilder out = new StringBuilder(signal);
            if (!abort.isEmpty()) {
                out.append("\nabort: ").append(abort);
            }
            for (String c : causes) {
                out.append("\ncause: ").append(c);
            }
            Pb crashing = threads.get(tid);
            if (crashing != null) {
                out.append('\n').append(threadText(crashing, 48));
            }
            java.util.ArrayList<String> lines = new java.util.ArrayList<>();
            for (Pb buffer : logs) {
                while (buffer.more()) {
                    long bt = buffer.varint();
                    if ((bt >>> 3) == 2 && (bt & 7) == 2) {
                        lines.add(logLine(buffer.sub()));
                    } else {
                        buffer.skip((int) (bt & 7));
                    }
                }
            }
            if (!lines.isEmpty()) {
                out.append("\nlog:");
                for (String line : lines.subList(Math.max(0, lines.size() - 40), lines.size())) {
                    out.append("\n  ").append(line);
                }
            }
            return out.length() > 12000 ? out.substring(0, 12000) : out.toString();
        } catch (Throwable t) {
            return "";
        }
    }

    static String signalText(Pb s) {
        long number = 0;
        long code = 0;
        long fault = 0;
        boolean hasFault = false;
        String name = "";
        String codeName = "";
        while (s.more()) {
            long tag = s.varint();
            int field = (int) (tag >>> 3);
            int wire = (int) (tag & 7);
            if (field == 1 && wire == 0) {
                number = s.varint();
            } else if (field == 2 && wire == 2) {
                name = clip(s.str(), 40);
            } else if (field == 3 && wire == 0) {
                code = s.varint();
            } else if (field == 4 && wire == 2) {
                codeName = clip(s.str(), 40);
            } else if (field == 8 && wire == 0) {
                hasFault = s.varint() != 0;
            } else if (field == 9 && wire == 0) {
                fault = s.varint();
            } else {
                s.skip(wire);
            }
        }
        return "signal " + number + " (" + name + "), code " + (int) code + " (" + codeName + ")"
                + (hasFault ? ", fault addr 0x" + Long.toHexString(fault) : "");
    }

    static String threadText(Pb th, int maxFrames) {
        String name = "";
        long id = 0;
        StringBuilder frames = new StringBuilder();
        int n = 0;
        while (th.more()) {
            long tag = th.varint();
            int field = (int) (tag >>> 3);
            int wire = (int) (tag & 7);
            if (field == 1 && wire == 0) {
                id = th.varint();
            } else if (field == 2 && wire == 2) {
                name = clip(th.str(), 60);
            } else if (field == 4 && wire == 2) {
                Pb f = th.sub();
                if (n < maxFrames) {
                    frames.append("\n  ").append(frameText(f, n));
                }
                n++;
            } else {
                th.skip(wire);
            }
        }
        return "thread " + id + " \"" + name + "\" (" + n + " frames):" + frames;
    }

    static String frameText(Pb f, int index) {
        long relPc = 0;
        long offset = 0;
        String function = "";
        String file = "";
        while (f.more()) {
            long tag = f.varint();
            int field = (int) (tag >>> 3);
            int wire = (int) (tag & 7);
            if (field == 1 && wire == 0) {
                relPc = f.varint();
            } else if (field == 4 && wire == 2) {
                function = clip(f.str(), 120);
            } else if (field == 5 && wire == 0) {
                offset = f.varint();
            } else if (field == 6 && wire == 2) {
                file = clip(f.str(), 120);
            } else {
                f.skip(wire);
            }
        }
        return String.format(java.util.Locale.ROOT, "#%02d pc %016x  %s%s", index, relPc, file,
                function.isEmpty() ? "" : " (" + function + "+" + offset + ")");
    }

    static String logLine(Pb m) {
        String tag = "";
        String message = "";
        long priority = 0;
        while (m.more()) {
            long t = m.varint();
            int field = (int) (t >>> 3);
            int wire = (int) (t & 7);
            if (field == 4 && wire == 0) {
                priority = m.varint();
            } else if (field == 5 && wire == 2) {
                tag = clip(m.str(), 40);
            } else if (field == 6 && wire == 2) {
                message = clip(m.str(), 200);
            } else {
                m.skip(wire);
            }
        }
        String level = priority >= 2 && priority <= 7 ? String.valueOf("VDIWEF".charAt((int) priority - 2)) : "?";
        return level + " " + tag + ": " + message;
    }

    // --- Java exceptions ----------------------------------------------------------------------

    static boolean crashRecorderOn = false;

    /** An uncaught Java exception writes its stack to <files>/logs/java_crash_<ms>.txt (crash_log.gd
     *  sends it to the PC next time), then Android's own handling carries on as before. */
    public static boolean installCrashRecorder(Activity activity) {
        try {
            if (crashRecorderOn || activity == null) {
                return crashRecorderOn;
            }
            final java.io.File dir = new java.io.File(activity.getFilesDir(), "logs");
            final Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
            Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
                @Override
                public void uncaughtException(Thread thread, Throwable error) {
                    try {
                        dir.mkdirs();
                        java.io.StringWriter text = new java.io.StringWriter();
                        java.io.PrintWriter writer = new java.io.PrintWriter(text);
                        writer.println("thread \"" + thread.getName() + "\"");
                        error.printStackTrace(writer);
                        writer.flush();
                        String s = text.toString();
                        java.io.FileOutputStream file = new java.io.FileOutputStream(
                                new java.io.File(dir, "java_crash_" + System.currentTimeMillis() + ".txt"));
                        file.write(s.substring(0, Math.min(s.length(), 12000)).getBytes(java.nio.charset.StandardCharsets.UTF_8));
                        file.close();
                    } catch (Throwable ignored) {
                    }
                    if (previous != null) {
                        previous.uncaughtException(thread, error);
                    }
                }
            });
            crashRecorderOn = true;
        } catch (Throwable ignored) {
        }
        tagExitRecord(activity);
        return crashRecorderOn;
    }

    /** Android 11+ keeps this tag in the record of however this process ends (recentCrashExits reads
     *  it back), so a crash report names the build that crashed, not the one that sends the report. */
    static void tagExitRecord(Activity activity) {
        try {
            if (Build.VERSION.SDK_INT < 30 || activity == null) return;
            ActivityManager manager = (ActivityManager) activity.getSystemService(Context.ACTIVITY_SERVICE);
            String version = packageInfo(activity).versionName;
            if (version != null) {
                manager.setProcessStateSummary(version.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            }
        } catch (Throwable ignored) {
        }
    }

    @SuppressWarnings("deprecation")   // getPackageInfo(String, PackageInfoFlags) only exists from API 33
    static android.content.pm.PackageInfo packageInfo(Activity activity) throws PackageManager.NameNotFoundException {
        return activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0);
    }

    // --- Display refresh rate ---------------------------------------------------------------

    /**
     * Asks the display for a mode at the current resolution: the fastest one when cap is 0, else
     * the slowest one at or above cap (a 60 fps cap shows each frame for exactly one 60 Hz refresh).
     * Android 15+ holds games to 60 Hz unless they ask, so this also tells the game's surface its
     * frame rate. Returns the refresh rate asked for, or 0 when nothing could be asked.
     */
    public static double requestRefreshRate(final Activity activity, double cap) {
        try {
            Display display = display(activity);
            if (display == null) {
                return 0;
            }
            Display.Mode current = display.getMode();
            Display.Mode best = null;
            for (Display.Mode m : display.getSupportedModes()) {
                if (m.getPhysicalWidth() != current.getPhysicalWidth() || m.getPhysicalHeight() != current.getPhysicalHeight()) {
                    continue;
                }
                if (best == null) {
                    best = m;
                } else if (cap <= 0) {
                    if (m.getRefreshRate() > best.getRefreshRate()) {
                        best = m;
                    }
                } else {
                    boolean mOk = m.getRefreshRate() >= cap - 0.5;
                    boolean bestOk = best.getRefreshRate() >= cap - 0.5;
                    if ((mOk && !bestOk) || (mOk && m.getRefreshRate() < best.getRefreshRate())
                            || (!mOk && !bestOk && m.getRefreshRate() > best.getRefreshRate())) {
                        best = m;
                    }
                }
            }
            if (best == null) {
                return 0;
            }
            final int modeId = best.getModeId();
            final float rate = best.getRefreshRate();
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    applyRefreshRate(activity, modeId, rate);
                }
            });
            return rate;
        } catch (Throwable t) {
            return 0;
        }
    }

    /** The display's refresh rate right now (Hz), 0 if unknown. */
    public static double currentRefreshRate(Activity activity) {
        try {
            Display display = display(activity);
            return display == null ? 0 : display.getRefreshRate();
        } catch (Throwable t) {
            return 0;
        }
    }

    /** The fastest refresh rate the display offers at its current resolution (Hz), 0 if unknown. */
    public static double maxRefreshRate(Activity activity) {
        try {
            Display display = display(activity);
            if (display == null) {
                return 0;
            }
            Display.Mode current = display.getMode();
            float max = 0;
            for (Display.Mode m : display.getSupportedModes()) {
                if (m.getPhysicalWidth() == current.getPhysicalWidth() && m.getPhysicalHeight() == current.getPhysicalHeight()) {
                    max = Math.max(max, m.getRefreshRate());
                }
            }
            return max;
        } catch (Throwable t) {
            return 0;
        }
    }

    /**
     * This process's resident memory in kB (VmRSS in /proc/self/status), 0 when it can't be read. Godot's own
     * file access refuses /proc paths on Android (its scoped-storage layer only opens the app's folders and
     * shared storage), so the game's memory watchdog (scripts/core/memory_guard.gd) asks here.
     */
    public static long residentKb() {
        try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader("/proc/self/status"), 4096)) {
            String line;
            int lines = 0;
            while ((line = reader.readLine()) != null && lines++ < 100) {
                if (line.startsWith("VmRSS:")) {
                    String text = line.substring(6).trim();
                    int end = 0;
                    while (end < text.length() && Character.isDigit(text.charAt(end))) {
                        end++;
                    }
                    return end == 0 ? 0L : Long.parseLong(text.substring(0, end));
                }
            }
        } catch (Throwable t) {
            // Unreadable on this device: 0 means "no reading" and the watchdog stays quiet.
        }
        return 0L;
    }

    @SuppressWarnings("deprecation")
    static Display display(Activity activity) {
        if (Build.VERSION.SDK_INT >= 30) {
            return activity.getDisplay();
        }
        return activity.getWindowManager().getDefaultDisplay();
    }

    static void applyRefreshRate(Activity activity, int modeId, float rate) {
        try {
            Window w = activity.getWindow();
            WindowManager.LayoutParams lp = w.getAttributes();
            if (lp.preferredDisplayModeId != modeId) {
                lp.preferredDisplayModeId = modeId;
                w.setAttributes(lp);
            }
            if (Build.VERSION.SDK_INT >= 30) {
                SurfaceView view = findSurfaceView(w.getDecorView());
                if (view != null) {
                    SurfaceHolder holder = view.getHolder();
                    Surface surface = holder == null ? null : holder.getSurface();
                    if (surface != null && surface.isValid()) {
                        if (Build.VERSION.SDK_INT >= 31) {
                            surface.setFrameRate(rate, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE,
                                    Surface.CHANGE_FRAME_RATE_ONLY_IF_SEAMLESS);
                        } else {
                            surface.setFrameRate(rate, Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE);
                        }
                    }
                }
            }
        } catch (Throwable t) {
            // The system keeps its own choice.
        }
    }

    static SurfaceView findSurfaceView(View v) {
        if (v instanceof SurfaceView) {
            return (SurfaceView) v;
        }
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) {
                SurfaceView found = findSurfaceView(g.getChildAt(i));
                if (found != null) {
                    return found;
                }
            }
        }
        return null;
    }

    // --- Notifications ----------------------------------------------------------------------

    /** Whether Polox may show notifications now (switched on for the app, and on Android 13+ allowed). */
    public static boolean notificationsAllowed(Context ctx) {
        try {
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null || !nm.areNotificationsEnabled()) {
                return false;
            }
            if (Build.VERSION.SDK_INT >= 33
                    && ctx.checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    /**
     * One notification at a wall-clock time (milliseconds since 1970), replacing any earlier one with
     * the same id. Inexact (no exact-alarm permission needed); it survives the game closing but not a
     * restart of the phone (the game schedules again whenever it runs).
     */
    public static boolean schedule(Context ctx, int id, long atMillis, String title, String text) {
        try {
            AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
            if (am == null) {
                return false;
            }
            PendingIntent pi = pending(ctx, id, title, text, true);
            if (pi == null) {
                return false;
            }
            am.setAndAllowWhileIdle(AlarmManager.RTC, atMillis, pi);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    /** Takes back a scheduled notification (and removes it if it is already showing). */
    public static boolean cancel(Context ctx, int id) {
        boolean found = false;
        try {
            AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
            PendingIntent pi = pending(ctx, id, "", "", false);
            if (pi != null) {
                found = true;
                if (am != null) {
                    am.cancel(pi);
                }
                pi.cancel();
            }
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm != null) {
                nm.cancel("polox", id);
            }
        } catch (Throwable t) {
            // Nothing scheduled, or the system said no: either way nothing will show.
        }
        return found;
    }

    /** Shows a notification now (the receiver calls this; Settings uses it for "Send a test"). */
    public static boolean notifyNow(Context ctx, int id, String title, String text) {
        try {
            if (!notificationsAllowed(ctx)) {
                return false;
            }
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            Notification.Builder b;
            if (Build.VERSION.SDK_INT >= 26) {
                if (nm.getNotificationChannel(CHANNEL) == null) {
                    NotificationChannel ch = new NotificationChannel(CHANNEL, "Friends", NotificationManager.IMPORTANCE_DEFAULT);
                    ch.setDescription("Your friends in Polox saying they miss you");
                    nm.createNotificationChannel(ch);
                }
                b = new Notification.Builder(ctx, CHANNEL);
            } else {
                b = legacyBuilder(ctx);
            }
            String t = title == null || title.isEmpty() ? "Polox" : title;
            String body = text == null ? "" : text;
            b.setSmallIcon(smallIcon(ctx))
                    .setContentTitle(t)
                    .setContentText(body)
                    .setStyle(new Notification.BigTextStyle().bigText(body))
                    .setAutoCancel(true)
                    .setShowWhen(true);
            Intent launch = ctx.getPackageManager().getLaunchIntentForPackage(ctx.getPackageName());
            if (launch != null) {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                b.setContentIntent(PendingIntent.getActivity(ctx, id, launch,
                        PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT));
            }
            nm.notify("polox", id, b.build());
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    @SuppressWarnings("deprecation")
    static Notification.Builder legacyBuilder(Context ctx) {
        return new Notification.Builder(ctx);
    }

    /** The launcher's one-colour icon (white on the status bar), else the app icon. */
    static int smallIcon(Context ctx) {
        int mono = ctx.getResources().getIdentifier("icon_monochrome", "mipmap", ctx.getPackageName());
        return mono != 0 ? mono : ctx.getApplicationInfo().icon;
    }

    static PendingIntent pending(Context ctx, int id, String title, String text, boolean create) {
        Intent i = new Intent(ctx, MissYouReceiver.class);
        i.setAction(ACTION);
        i.putExtra("id", id);
        i.putExtra("title", title);
        i.putExtra("text", text);
        int flags = PendingIntent.FLAG_IMMUTABLE | (create ? PendingIntent.FLAG_UPDATE_CURRENT : PendingIntent.FLAG_NO_CREATE);
        return PendingIntent.getBroadcast(ctx, id, i, flags);
    }
}
