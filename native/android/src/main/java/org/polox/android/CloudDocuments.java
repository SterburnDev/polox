package org.polox.android;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * Cloud sync on Android (scripts/sync/cloud_store.gd, DocumentStore): a world's cloud copy is a document the
 * player picks with Android's own file picker (the Storage Access Framework), so it can live in Google Drive,
 * OneDrive or any other storage app without Polox signing in anywhere or asking for a storage permission.
 * Android gives Polox read and write access to that one document; the grant is made persistent so it survives
 * a restart, and it ends when the document is moved or deleted (documentInfo then says it doesn't exist).
 *
 * Copies go between the document and a file in Polox's own storage, where the game checks them
 * (scripts/sync/cloud_package.gd) before using anything. Every method answers with "" for success or a
 * sentence the game can show.
 */
final class CloudDocuments {
    /** Request codes for the two pickers (the game's activity allows 16 bits). */
    static final int REQUEST_CREATE = 0x5043;
    static final int REQUEST_OPEN = 0x5044;
    static final String PACKAGE_MIME = "application/octet-stream";
    static final int ACCESS = Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION;

    private CloudDocuments() {
    }

    /** "Save as": the picker asks where the new document goes. The answer arrives in the activity's result. */
    static boolean pickToCreate(Activity activity, String suggestedName) {
        if (activity == null) return false;
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(PACKAGE_MIME);
        intent.putExtra(Intent.EXTRA_TITLE, suggestedName == null || suggestedName.isEmpty() ? "world.poloxsync" : suggestedName);
        intent.addFlags(ACCESS | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        return start(activity, intent, REQUEST_CREATE);
    }

    /** "Open": the picker shows existing documents (any type: storage apps name unknown extensions differently). */
    static boolean pickToOpen(Activity activity) {
        if (activity == null) return false;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.addFlags(ACCESS | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
        return start(activity, intent, REQUEST_OPEN);
    }

    private static boolean start(Activity activity, Intent intent, int request) {
        try {
            activity.startActivityForResult(intent, request);
            return true;
        } catch (RuntimeException e) {   // no app on this phone can show the picker
            return false;
        }
    }

    /** The picked document's address, with the grant made persistent; "" when the player backed out. */
    static String onPicked(Context ctx, int resultCode, Intent data) {
        if (ctx == null || resultCode != Activity.RESULT_OK || data == null || data.getData() == null) return "";
        Uri uri = data.getData();
        try {
            ctx.getContentResolver().takePersistableUriPermission(uri, data.getFlags() & ACCESS);
        } catch (RuntimeException e) {
            // Some storage apps don't offer a lasting grant. The document still works until the phone
            // restarts; after that documentInfo says it is gone and the game asks to pick it again.
        }
        return uri.toString();
    }

    /** {"exists", "name", "bytes", "modified_ms"} as JSON. bytes is -1 when the storage app doesn't say. */
    static String info(Context ctx, String address) {
        JSONObject out = new JSONObject();
        try {
            out.put("exists", false);
            if (ctx == null || address == null || address.isEmpty()) return out.toString();
            Uri uri = Uri.parse(address);
            try (Cursor row = ctx.getContentResolver().query(uri, null, null, null, null)) {
                if (row == null || !row.moveToFirst()) return out.toString();
                out.put("exists", true);
                int name = row.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                int size = row.getColumnIndex(OpenableColumns.SIZE);
                int modified = row.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED);
                out.put("name", name >= 0 && !row.isNull(name) ? row.getString(name) : "");
                out.put("bytes", size >= 0 && !row.isNull(size) ? row.getLong(size) : -1L);
                out.put("modified_ms", modified >= 0 && !row.isNull(modified) ? row.getLong(modified) : 0L);
            }
        } catch (Exception e) {   // the grant was taken away, or the document was moved or deleted
            return "{\"exists\":false}";
        }
        return out.toString();
    }

    /** Copies the document into one of Polox's own files. */
    static String copyToFile(Context ctx, String address, String destPath) {
        if (ctx == null || address == null || destPath == null) return "This phone can't open cloud documents.";
        File dest = new File(destPath);
        File folder = dest.getParentFile();
        if (folder != null && !folder.isDirectory() && !folder.mkdirs()) return "Couldn't save the cloud copy on this phone (is storage full?).";
        ContentResolver resolver = ctx.getContentResolver();
        try (InputStream in = resolver.openInputStream(Uri.parse(address)); OutputStream out = new FileOutputStream(dest)) {
            if (in == null) return "The cloud document can't be opened. Pick it again.";
            PhoneFiles.copy(in, out);
            return "";
        } catch (SecurityException e) {
            removeQuietly(dest);
            return "Polox is no longer allowed to open that cloud document. Pick it again.";
        } catch (IOException | RuntimeException e) {
            removeQuietly(dest);
            return "Couldn't download the cloud copy. Is the phone online? (" + shortReason(e) + ")";
        }
    }

    /** Replaces the document's contents with one of Polox's own files ("wt": write and cut to length). */
    static String copyFromFile(Context ctx, String sourcePath, String address) {
        if (ctx == null || address == null || sourcePath == null) return "This phone can't open cloud documents.";
        File source = new File(sourcePath);
        if (!source.isFile()) return "The world's package wasn't made. Try again.";
        ContentResolver resolver = ctx.getContentResolver();
        Uri uri = Uri.parse(address);
        try (InputStream in = new FileInputStream(source); OutputStream out = openForReplacing(resolver, uri)) {
            if (out == null) return "The cloud document can't be written. Pick it again.";
            PhoneFiles.copy(in, out);
            return "";
        } catch (SecurityException e) {
            return "Polox is no longer allowed to change that cloud document. Pick it again.";
        } catch (IOException | RuntimeException e) {
            return "Couldn't upload to the cloud document. Is the phone online? (" + shortReason(e) + ")";
        }
    }

    /** Most storage apps cut the document to the new length with "wt"; a few only know "w". */
    private static OutputStream openForReplacing(ContentResolver resolver, Uri uri) throws IOException {
        try {
            return resolver.openOutputStream(uri, "wt");
        } catch (IOException | IllegalArgumentException | UnsupportedOperationException e) {
            return resolver.openOutputStream(uri, "w");
        }
    }

    /** Gives back the lasting grant for a document Polox no longer syncs with. */
    static void release(Context ctx, String address) {
        if (ctx == null || address == null || address.isEmpty()) return;
        try {
            ctx.getContentResolver().releasePersistableUriPermission(Uri.parse(address), ACCESS);
        } catch (RuntimeException e) {
            // (there was no lasting grant)
        }
    }

    private static void removeQuietly(File file) {
        if (file.exists() && !file.delete()) file.deleteOnExit();
    }

    private static String shortReason(Exception e) {
        String message = e.getMessage();
        String text = message == null || message.isEmpty() ? e.getClass().getSimpleName() : message;
        return text.length() > 80 ? text.substring(0, 80) : text;
    }
}
