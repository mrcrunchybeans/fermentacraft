package com.fermentacraft

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import androidx.core.view.WindowCompat

class MainActivity : FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // Opt into edge-to-edge on all Android versions (matches Android 15 default)
    WindowCompat.setDecorFitsSystemWindows(window, false)
  }
}
