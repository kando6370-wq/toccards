package dev.kando.cardvault.app

import android.graphics.Color
import android.os.Build
import android.view.ContextThemeWrapper
import android.view.WindowManager.LayoutParams
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleCallback
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MainActivityEdgeToEdgeTest {
    @Suppress("DEPRECATION") // Before Android 15 the host, not the OS, sets the startup bar color.
    @Test
    fun startupAndFlutterContentCanDrawBehindTheSystemBars() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val monitor = ActivityLifecycleMonitorRegistry.getInstance()
        var startupBarColor: Int? = null
        val capture = ActivityLifecycleCallback { activity, stage ->
            if (activity is MainActivity && stage == Stage.CREATED) {
                startupBarColor = activity.window.statusBarColor
            }
        }
        instrumentation.runOnMainSync { monitor.addLifecycleCallback(capture) }
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    assertEquals("The first frame must draw behind a transparent status bar", Color.TRANSPARENT, startupBarColor)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        val expected = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                        } else {
                            LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                        }
                        val splash = ContextThemeWrapper(activity.applicationContext, R.style.LaunchTheme)
                        val attributes = splash.obtainStyledAttributes(intArrayOf(android.R.attr.windowLayoutInDisplayCutoutMode))
                        try {
                            assertEquals("Splash must fill the same cutout as Flutter", expected, attributes.getInt(0, -1))
                        } finally {
                            attributes.recycle()
                        }
                        assertEquals("The running window must fill the cutout", expected, activity.window.attributes.layoutInDisplayCutoutMode)
                    }
                }
            }
        } finally {
            instrumentation.runOnMainSync { monitor.removeLifecycleCallback(capture) }
        }
    }
}
