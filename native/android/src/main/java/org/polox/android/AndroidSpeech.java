package org.polox.android;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.speech.RecognizerIntent;
import android.speech.SpeechRecognizer;

import java.util.ArrayList;

/**
 * Android system speech-to-text launcher via RecognizerIntent (pure android.*, no AndroidX).
 * Lets Live Conversation transcribe the player's voice using Android's built-in recognizer without
 * storing audio files or requiring a paid STT API key.
 */
final class AndroidSpeech {
    static final int REQUEST_SPEECH = 0x5046;

    private AndroidSpeech() {
    }

    static boolean available(Activity activity) {
        if (activity == null) {
            return false;
        }
        if (SpeechRecognizer.isRecognitionAvailable(activity)) {
            return true;
        }
        Intent probe = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        return probe.resolveActivity(activity.getPackageManager()) != null;
    }

    static boolean start(Activity activity, String prompt) {
        if (activity == null) {
            return false;
        }
        Intent intent = new Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH);
        intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM);
        intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1);
        if (prompt != null && !prompt.trim().isEmpty()) {
            intent.putExtra(RecognizerIntent.EXTRA_PROMPT, prompt.trim());
        }
        try {
            activity.startActivityForResult(intent, REQUEST_SPEECH);
            return true;
        } catch (ActivityNotFoundException | SecurityException e) {
            return false;
        }
    }

    /** Returns [error, transcript]; error is "" on success or user cancellation ("cancelled"). */
    static String[] onResult(int resultCode, Intent data) {
        if (resultCode != Activity.RESULT_OK || data == null) {
            return new String[]{"cancelled", ""};
        }
        ArrayList<String> matches = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS);
        if (matches == null || matches.isEmpty() || matches.get(0) == null) {
            return new String[]{"Didn't catch any speech.", ""};
        }
        String text = matches.get(0).trim();
        if (text.isEmpty()) {
            return new String[]{"Didn't catch any speech.", ""};
        }
        return new String[]{"", text};
    }
}
