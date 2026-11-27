package org.polox.android;

import android.app.Activity;
import android.content.ComponentCallbacks2;
import android.content.Intent;
import android.content.res.Configuration;
import android.view.View;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * Polox's Godot Android plugin (v2). Godot finds it through the meta-data line in this library's manifest and
 * GDScript reaches it as Engine.get_singleton("PoloxAndroid") (scripts/core/android_native.gd). It hands the
 * game's activity to PoloxAndroid's helpers, and passes on Android's memory warnings, which Godot itself
 * doesn't: "memory_warning" carries the trim level (ComponentCallbacks2), 80 for a low-memory call.
 * "document_picked" carries the answer of the system file picker (CloudDocuments): the word the game gave
 * the question and the document's content:// address, or "" when the player backed out.
 */
public final class PoloxAndroidPlugin extends GodotPlugin {
    static final SignalInfo MEMORY_WARNING = new SignalInfo("memory_warning", Integer.class);
    static final SignalInfo DOCUMENT_PICKED = new SignalInfo("document_picked", String.class, String.class);
    /** TRIM_MEMORY_RUNNING_CRITICAL (Android 13 and earlier), and every level from TRIM_MEMORY_BACKGROUND up. */
    static final int RUNNING_CRITICAL = 15;
    static final int BACKGROUND = 40;
    static final int COMPLETE = 80;

    private Activity watched;
    /** What the game called the picker question that is on screen ("" when none is). */
    private volatile String pickerPurpose = "";
    private final ComponentCallbacks2 memoryWatch = new ComponentCallbacks2() {
        @Override
        public void onTrimMemory(int level) {
            if (level == RUNNING_CRITICAL || level >= BACKGROUND) {
                emitSignal(MEMORY_WARNING, level);
            }
        }

        @Override
        public void onConfigurationChanged(Configuration config) {
        }

        @Override
        @SuppressWarnings("deprecation")   // still called on every Android version this app supports
        public void onLowMemory() {
            emitSignal(MEMORY_WARNING, COMPLETE);
        }
    };

    public PoloxAndroidPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "PoloxAndroid";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        return new HashSet<>(Arrays.asList(MEMORY_WARNING, DOCUMENT_PICKED));
    }

    @Override
    public View onMainCreate(Activity activity) {
        if (activity != null) {
            activity.registerComponentCallbacks(memoryWatch);
            watched = activity;
        }
        return null;
    }

    /** The file or folder picker closed: tell the game which address was picked (or that none was). */
    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != CloudDocuments.REQUEST_CREATE
                && requestCode != CloudDocuments.REQUEST_OPEN
                && requestCode != CloudDocuments.REQUEST_TREE) {
            return;
        }
        String purpose = pickerPurpose;
        pickerPurpose = "";
        emitSignal(DOCUMENT_PICKED, purpose, CloudDocuments.onPicked(getActivity(), resultCode, data));
    }

    @Override
    public void onMainDestroy() {
        if (watched != null) {
            watched.unregisterComponentCallbacks(memoryWatch);
            watched = null;
        }
    }

    @UsedByGodot
    public String recentCrashExits() {
        return PoloxAndroid.recentCrashExits(getActivity());
    }

    @UsedByGodot
    public boolean installCrashRecorder() {
        return PoloxAndroid.installCrashRecorder(getActivity());
    }

    @UsedByGodot
    public double requestRefreshRate(double cap) {
        return PoloxAndroid.requestRefreshRate(getActivity(), cap);
    }

    @UsedByGodot
    public double currentRefreshRate() {
        return PoloxAndroid.currentRefreshRate(getActivity());
    }

    @UsedByGodot
    public double maxRefreshRate() {
        return PoloxAndroid.maxRefreshRate(getActivity());
    }

    @UsedByGodot
    public long residentKb() {
        return PoloxAndroid.residentKb();
    }

    @UsedByGodot
    public boolean notificationsAllowed() {
        return PoloxAndroid.notificationsAllowed(getActivity());
    }

    @UsedByGodot
    public boolean schedule(int id, long atMillis, String title, String text) {
        return PoloxAndroid.schedule(getActivity(), id, atMillis, title, text);
    }

    @UsedByGodot
    public boolean cancel(int id) {
        return PoloxAndroid.cancel(getActivity(), id);
    }

    @UsedByGodot
    public boolean notifyNow(int id, String title, String text) {
        return PoloxAndroid.notifyNow(getActivity(), id, title, text);
    }

    /** A copy of one of Polox's own files in the phone's Downloads (PhoneFiles): where it went, or "". */
    @UsedByGodot
    public String saveToDownloads(String sourcePath, String displayName, String mime) {
        return PhoneFiles.saveToDownloads(getActivity(), sourcePath, displayName, mime);
    }

    /** Cloud sync: the system picker to make a new document; the answer comes as "document_picked". */
    @UsedByGodot
    public void pickDocumentToCreate(String purpose, String suggestedName) {
        showPicker(purpose, 0, suggestedName);
    }

    /** Cloud sync: the system picker to choose an existing document; the answer comes as "document_picked". */
    @UsedByGodot
    public void pickDocumentToOpen(String purpose) {
        showPicker(purpose, 1, "");
    }

    /** Cloud sync: the system folder picker (ACTION_OPEN_DOCUMENT_TREE); answer comes as "document_picked". */
    @UsedByGodot
    public void pickTree(String purpose) {
        showPicker(purpose, 2, "");
    }

    /** Pickers are windows: they start on Android's own thread, not the game's. mode: 0=create, 1=open, 2=tree. */
    private void showPicker(String purpose, int mode, String suggestedName) {
        Activity activity = getActivity();
        if (activity == null) {
            emitSignal(DOCUMENT_PICKED, purpose, "");
            return;
        }
        pickerPurpose = purpose == null ? "" : purpose;
        activity.runOnUiThread(() -> {
            boolean shown;
            if (mode == 0) {
                shown = CloudDocuments.pickToCreate(activity, suggestedName);
            } else if (mode == 2) {
                shown = CloudDocuments.pickTree(activity);
            } else {
                shown = CloudDocuments.pickToOpen(activity);
            }
            if (!shown) {
                pickerPurpose = "";
                emitSignal(DOCUMENT_PICKED, purpose, "");
            }
        });
    }

    @UsedByGodot
    public String documentInfo(String address) {
        return CloudDocuments.info(getActivity(), address);
    }

    @UsedByGodot
    public String copyDocumentToFile(String address, String destPath) {
        return CloudDocuments.copyToFile(getActivity(), address, destPath);
    }

    @UsedByGodot
    public String copyFileToDocument(String sourcePath, String address) {
        return CloudDocuments.copyFromFile(getActivity(), sourcePath, address);
    }

    @UsedByGodot
    public void releaseDocument(String address) {
        CloudDocuments.release(getActivity(), address);
    }

    @UsedByGodot
    public String treeInfo(String treeAddress) {
        return CloudDocuments.treeInfo(getActivity(), treeAddress);
    }

    @UsedByGodot
    public String treeList(String treeAddress) {
        return CloudDocuments.treeList(getActivity(), treeAddress);
    }

    @UsedByGodot
    public String treeDocumentInfo(String treeAddress, String fileName) {
        return CloudDocuments.treeDocumentInfo(getActivity(), treeAddress, fileName);
    }

    @UsedByGodot
    public String treeCopyToFile(String treeAddress, String fileName, String destPath) {
        return CloudDocuments.treeCopyToFile(getActivity(), treeAddress, fileName, destPath);
    }

    @UsedByGodot
    public String treeCopyFromFile(String sourcePath, String treeAddress, String fileName) {
        return CloudDocuments.treeCopyFromFile(getActivity(), sourcePath, treeAddress, fileName);
    }
}
