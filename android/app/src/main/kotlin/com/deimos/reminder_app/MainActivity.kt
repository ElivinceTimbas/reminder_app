package com.deimos.reminder_app

import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Exposes the sounds library to the OS audio stack.
        //
        // A notification sound has to be a URI the system (uid 1000, not this
        // app) can actually open, and app-private files are not readable by
        // anyone else. FileProvider turns a path under `reminder_file_paths.xml`
        // into a `content://` URI that the system may be granted access to.
        // Computing the URI here rather than in Dart keeps FileProvider's own
        // path canonicalization and segment encoding in the layer that owns them.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOUND_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSoundUri" -> {
                        val path = call.arguments as? String
                        if (path == null) {
                            result.error("bad_args", "Expected a file path", null)
                        } else {
                            result.success(soundUriFor(path))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Null when [path] is missing or outside the configured FileProvider roots. */
    private fun soundUriFor(path: String): String? =
        try {
            val file = File(path)
            if (file.exists()) {
                FileProvider.getUriForFile(this, "$packageName.reminder_sounds", file).toString()
            } else {
                null
            }
        } catch (e: IllegalArgumentException) {
            null
        }

    private companion object {
        const val SOUND_CHANNEL = "com.deimos.reminder_app/sounds"
    }
}