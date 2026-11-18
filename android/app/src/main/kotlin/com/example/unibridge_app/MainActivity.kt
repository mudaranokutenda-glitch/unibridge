package com.example.unibridge_app

import android.content.Context
import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Used by the startup sound: it must not play when the phone is on silent or vibrate.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "unibridge/audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "isRingerNormal") {
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    result.success(audio.ringerMode == AudioManager.RINGER_MODE_NORMAL)
                } else {
                    result.notImplemented()
                }
            }
    }
}
