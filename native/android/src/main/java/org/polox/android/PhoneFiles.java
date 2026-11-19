package org.polox.android;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Copies a file Polox made (an exported world, a chat log) out of the app's private storage, where no file
 * manager or PC can reach it, into the phone's Downloads: Download/Polox/ through MediaStore on Android 10
 * and later (no permission needed), the app's own external Download folder before that
 * (Android/data/com.polox.app/files/Download, which a USB cable can open).
 */
final class PhoneFiles {
    static final String FOLDER = "Polox";

    private PhoneFiles() {
    }

    /** Returns where the copy went ("Download/Polox/name.polox"), or "" when it couldn't be made. */
    static String saveToDownloads(Context ctx, String sourcePath, String displayName, String mime) {
        try {
            if (ctx == null || sourcePath == null) return "";
            File source = new File(sourcePath);
            if (!source.isFile()) return "";
            String name = new File(displayName == null || displayName.isEmpty() ? source.getName() : displayName).getName();
            String type = mime == null || mime.isEmpty() ? "application/octet-stream" : mime;
            if (Build.VERSION.SDK_INT >= 29) {
                return toMediaStore(ctx, source, name, type);
            }
            return toAppDownloads(ctx, source, name);
        } catch (Throwable e) {
            return "";
        }
    }

    static String toMediaStore(Context ctx, File source, String name, String type) {
        if (Build.VERSION.SDK_INT < 29) return "";
        ContentResolver resolver = ctx.getContentResolver();
        ContentValues values = new ContentValues();
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
        values.put(MediaStore.MediaColumns.MIME_TYPE, type);
        values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + FOLDER);
        values.put(MediaStore.MediaColumns.IS_PENDING, 1);
        Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
        if (uri == null) return "";
        try (InputStream in = new FileInputStream(source); OutputStream out = resolver.openOutputStream(uri)) {
            if (out == null) throw new IOException("no output stream");
            copy(in, out);
        } catch (IOException | RuntimeException e) {
            resolver.delete(uri, null, null);
            return "";
        }
        ContentValues done = new ContentValues();
        done.put(MediaStore.MediaColumns.IS_PENDING, 0);
        resolver.update(uri, done, null, null);
        // MediaStore picks "name (1).polox" when the name is taken: report the name it really used.
        String used = name;
        try (Cursor c = resolver.query(uri, new String[] {MediaStore.MediaColumns.DISPLAY_NAME}, null, null, null)) {
            if (c != null && c.moveToFirst() && c.getString(0) != null) used = c.getString(0);
        } catch (RuntimeException ignored) {
        }
        return Environment.DIRECTORY_DOWNLOADS + "/" + FOLDER + "/" + used;
    }

    static String toAppDownloads(Context ctx, File source, String name) throws IOException {
        File dir = ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
        if (dir == null || !(dir.isDirectory() || dir.mkdirs())) return "";
        File target = new File(dir, name);
        String base = name.contains(".") ? name.substring(0, name.lastIndexOf('.')) : name;
        String ext = name.contains(".") ? name.substring(name.lastIndexOf('.')) : "";
        for (int n = 1; target.exists() && n < 1000; n++) {
            target = new File(dir, base + " (" + n + ")" + ext);
        }
        try (InputStream in = new FileInputStream(source); OutputStream out = new FileOutputStream(target)) {
            copy(in, out);
        } catch (IOException e) {
            if (target.exists() && !target.delete()) target.deleteOnExit();
            throw e;
        }
        return target.getAbsolutePath();
    }

    static void copy(InputStream in, OutputStream out) throws IOException {
        byte[] buffer = new byte[256 * 1024];
        int n;
        while ((n = in.read(buffer)) > 0) {
            out.write(buffer, 0, n);
        }
        out.flush();
    }
}
