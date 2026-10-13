package com.deimos.reminder_app

import android.media.MediaPlayer
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var previewPlayer: MediaPlayer? = null
    private var previewResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    "preview" -> {
                        stopPreview()
                        val path = call.arguments as? String
                        if (path == null) {
                            result.error("bad_args", "Expected a sound path", null)
                        } else {
                            previewResult = result
                            try {
                                val player = MediaPlayer()
                                previewPlayer = player
                                player.setDataSource(path)
                                player.setOnPreparedListener {
                                    if (previewPlayer === it) {
                                        try { it.start() }
                                        catch (error: Exception) { stopPreview("This sound could not be played") }
                                    }
                                }
                                player.setOnCompletionListener { stopPreview() }
                                player.setOnErrorListener { _, _, _ ->
                                    stopPreview("This sound could not be played")
                                    true
                                }
                                player.prepareAsync()
                            } catch (error: Exception) {
                                stopPreview(error.localizedMessage ?: "This sound could not be played")
                            }
                        }
                    }
                    "stopPreview" -> {
                        stopPreview()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun stopPreview(error: String? = null) {
        previewPlayer?.setOnPreparedListener(null)
        previewPlayer?.setOnCompletionListener(null)
        previewPlayer?.setOnErrorListener(null)
        previewPlayer?.release()
        previewPlayer = null
        val pending = previewResult
        previewResult = null
        if (error == null) pending?.success(null)
        else pending?.error("playback_failed", error, null)
    }

    override fun onStop() {
        stopPreview()
        super.onStop()
    }

    /** Null when the sound is missing or outside configured FileProvider roots. */
    private fun soundUriFor(path: String): String? =
        try {
            val file = File(path)
            if (file.exists()) {
                FileProvider.getUriForFile(this, "$packageName.reminder_sounds", file).toString()
            } else null
        } catch (e: IllegalArgumentException) {
            null
        }

    private companion object {
        const val SOUND_CHANNEL = "com.deimos.reminder_app/sounds"
    }
}
