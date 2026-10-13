package com.foliage.dania

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.foliage.dania.toolbox.ToolboxPlugin

class MainActivity : FlutterActivity() {
    private var toolbox: ToolboxPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        toolbox = ToolboxPlugin(this, flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        toolbox?.close()
        toolbox = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStop() {
        toolbox?.stopMirrors()
        super.onStop()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (toolbox?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
