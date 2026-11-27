package org.polox.android;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Cloud sync on Android (scripts/sync/cloud_store.gd, DocumentStore and TreeStore): a world's cloud copy
 * is either a document the player picks with Android's own file picker (Google Drive, OneDrive, Dropbox...)
 * or a whole cloud folder picked via ACTION_OPEN_DOCUMENT_TREE (DriveSync, Syncthing, Nextcloud, SD/local).
 * Android gives Polox persistent read and write access to what the player picks without Polox signing in
 * anywhere or asking for broad storage permissions.
 *
 * Copies go between the document/folder and a file in Polox's own storage, where the game checks them
 * (scripts/sync/cloud_package.gd) before using anything. Every method answers with "" for success or a
 * sentence the game can show.
 */
final class CloudDocuments {
    /** Request codes for the pickers (the game's activity allows 16 bits). */
    static final int REQUEST_CREATE = 0x5043;
    static final int REQUEST_OPEN = 0x5044;
    static final int REQUEST_TREE = 0x5045;
    static final String PACKAGE_MIME = "application/octet-stream";
    static final String PACKAGE_EXTENSION = ".poloxsync";
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

    /** "Open folder": lets the player pick a synced cloud folder (ACTION_OPEN_DOCUMENT_TREE). */
    static boolean pickTree(Activity activity) {
        if (activity == null) return false;
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        intent.addFlags(ACCESS | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION | Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
        return start(activity, intent, REQUEST_TREE);
    }

    private static boolean start(Activity activity, Intent intent, int request) {
        try {
            activity.startActivityForResult(intent, request);
            return true;
        } catch (RuntimeException e) {   // no app on this phone can show the picker
            return false;
        }
    }

    /** The picked document or folder's address, with the grant made persistent; "" when the player backed out. */
    static String onPicked(Context ctx, int resultCode, Intent data) {
        if (ctx == null || resultCode != Activity.RESULT_OK || data == null || data.getData() == null) return "";
        Uri uri = data.getData();
        ContentResolver resolver = ctx.getContentResolver();
        int flags = data.getFlags() & ACCESS;
        if (flags == 0) flags = ACCESS;
        try {
            resolver.takePersistableUriPermission(uri, flags);
        } catch (RuntimeException e) {
            if (flags != Intent.FLAG_GRANT_READ_URI_PERMISSION) {
                try {
                    resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
                } catch (RuntimeException ignored) {
                    // Some storage apps don't offer a lasting grant. The document still works until
                    // the phone restarts; after that info() says it is gone and the game asks again.
                }
            }
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
            out.flush();
            if (out instanceof FileOutputStream) {
                FileOutputStream fos = (FileOutputStream) out;
                try {
                    fos.getChannel().truncate(source.length());
                } catch (IOException | RuntimeException ignored) {
                    // Non-seekable streams (such as Google Drive pipes) cannot be truncated after writing.
                }
                try {
                    fos.getFD().sync();
                } catch (IOException | RuntimeException ignored) {
                }
            }
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

    /** {"exists", "name"} for a picked cloud folder (ACTION_OPEN_DOCUMENT_TREE). */
    static String treeInfo(Context ctx, String treeAddress) {
        JSONObject out = new JSONObject();
        try {
            out.put("exists", false);
            if (ctx == null || treeAddress == null || treeAddress.isEmpty()) return out.toString();
            Uri treeUri = Uri.parse(treeAddress);
            Uri rootDoc = treeRootDocumentUri(treeUri);
            String[] cols = {
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            };
            try (Cursor row = ctx.getContentResolver().query(rootDoc, cols, null, null, null)) {
                if (row == null || !row.moveToFirst()) return out.toString();
                String mime = row.isNull(1) ? null : row.getString(1);
                if (mime != null && !DocumentsContract.Document.MIME_TYPE_DIR.equals(mime)) {
                    return out.toString();
                }
                out.put("exists", true);
                out.put("name", !row.isNull(0) && row.getString(0) != null ? row.getString(0) : "Cloud folder");
            }
        } catch (Exception e) {
            return "{\"exists\":false}";
        }
        return out.toString();
    }

    /** Sorted JSON array of ".poloxsync" file names directly inside the picked cloud folder. */
    static String treeList(Context ctx, String treeAddress) {
        if (ctx == null || treeAddress == null || treeAddress.isEmpty()) return "[]";
        try {
            Uri treeUri = Uri.parse(treeAddress);
            Uri childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, DocumentsContract.getTreeDocumentId(treeUri));
            String[] cols = {
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            };
            List<String> names = new ArrayList<>();
            try (Cursor rows = ctx.getContentResolver().query(childrenUri, cols, null, null, null)) {
                if (rows == null) return "[]";
                while (rows.moveToNext()) {
                    String mime = rows.isNull(1) ? null : rows.getString(1);
                    if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mime)) continue;
                    String name = rows.isNull(0) ? "" : rows.getString(0);
                    if (isSafeFileName(name) && name.toLowerCase().endsWith(PACKAGE_EXTENSION)) {
                        names.add(name);
                    }
                }
            }
            Collections.sort(names);
            JSONArray out = new JSONArray();
            for (String n : names) out.put(n);
            return out.toString();
        } catch (Exception e) {
            return "[]";
        }
    }

    /** {"exists", "name", "bytes", "modified_ms"} for a single file inside the picked cloud folder. */
    static String treeDocumentInfo(Context ctx, String treeAddress, String fileName) {
        if (ctx == null || treeAddress == null || treeAddress.isEmpty() || !isSafeFileName(fileName)) {
            return "{\"exists\":false}";
        }
        try {
            Uri child = findChildDocumentUri(ctx.getContentResolver(), Uri.parse(treeAddress), fileName);
            return child == null ? "{\"exists\":false}" : info(ctx, child.toString());
        } catch (Exception e) {
            return "{\"exists\":false}";
        }
    }

    /** Copies a named file from the picked cloud folder into `destPath`. */
    static String treeCopyToFile(Context ctx, String treeAddress, String fileName, String destPath) {
        if (ctx == null || treeAddress == null || treeAddress.isEmpty()) return "No cloud folder is chosen yet.";
        if (!isSafeFileName(fileName)) return "Invalid cloud file name.";
        try {
            Uri child = findChildDocumentUri(ctx.getContentResolver(), Uri.parse(treeAddress), fileName);
            if (child == null) return "That world isn't in the cloud folder.";
            return copyToFile(ctx, child.toString(), destPath);
        } catch (SecurityException e) {
            return "Polox is no longer allowed to open that cloud folder. Choose it again.";
        } catch (RuntimeException e) {
            return "Couldn't read from the cloud folder (" + shortReason(e) + ")";
        }
    }

    /** Writes or replaces a named file inside the picked cloud folder from `sourcePath`. */
    static String treeCopyFromFile(Context ctx, String sourcePath, String treeAddress, String fileName) {
        if (ctx == null || treeAddress == null || treeAddress.isEmpty()) return "No cloud folder is chosen yet.";
        if (!isSafeFileName(fileName)) return "Invalid cloud file name.";
        if (sourcePath == null || !new File(sourcePath).isFile()) return "The world's package wasn't made. Try again.";
        ContentResolver resolver = ctx.getContentResolver();
        Uri treeUri = Uri.parse(treeAddress);
        Uri target = null;
        boolean created = false;
        try {
            target = findChildDocumentUri(resolver, treeUri, fileName);
            if (target == null) {
                target = DocumentsContract.createDocument(resolver, treeRootDocumentUri(treeUri), PACKAGE_MIME, fileName);
                created = target != null;
            }
        } catch (SecurityException e) {
            return "Polox is no longer allowed to write to that cloud folder. Choose it again.";
        } catch (Exception e) {
            return "Couldn't create that file in the cloud folder (" + shortReason(e) + ")";
        }
        if (target == null) {
            return "Couldn't create that file in the cloud folder.";
        }
        String err = copyFromFile(ctx, sourcePath, target.toString());
        if (!err.isEmpty() && created) {
            try {
                DocumentsContract.deleteDocument(resolver, target);
            } catch (Exception ignored) {
            }
        }
        return err;
    }

    private static boolean isSafeFileName(String name) {
        return name != null && !name.isEmpty()
                && !name.contains("/") && !name.contains("\\")
                && !".".equals(name) && !"..".equals(name);
    }

    private static Uri treeRootDocumentUri(Uri treeUri) {
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, DocumentsContract.getTreeDocumentId(treeUri));
    }

    private static Uri findChildDocumentUri(ContentResolver resolver, Uri treeUri, String fileName) {
        Uri childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, DocumentsContract.getTreeDocumentId(treeUri));
        String[] cols = {
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        };
        String fallbackId = null;
        try (Cursor rows = resolver.query(childrenUri, cols, null, null, null)) {
            if (rows == null) return null;
            while (rows.moveToNext()) {
                String mime = rows.isNull(2) ? null : rows.getString(2);
                if (DocumentsContract.Document.MIME_TYPE_DIR.equals(mime)) continue;
                String docId = rows.isNull(0) ? null : rows.getString(0);
                String name = rows.isNull(1) ? null : rows.getString(1);
                if (docId == null || name == null) continue;
                if (fileName.equals(name)) {
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, docId);
                }
                if (fallbackId == null && fileName.equalsIgnoreCase(name)) {
                    fallbackId = docId;
                }
            }
        }
        return fallbackId != null ? DocumentsContract.buildDocumentUriUsingTree(treeUri, fallbackId) : null;
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
