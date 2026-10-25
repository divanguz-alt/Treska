package hr.zet.zet2

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "hr.zet.zet2/updates"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "version" -> result.success(installedVersion())
                    "install" -> result.success(installApk(call.argument("path")))
                    // Lets the UI send the user straight to the per-app
                    // "install unknown apps" screen when the OS blocks us.
                    "unknownSourcesSettings" -> {
                        openUnknownSourcesSettings()
                        result.success(true)
                    }
                    "openUrl" -> result.success(openUrl(call.argument("url")))
                    "openApp" -> result.success(openApp(call.argument("package")))
                    else -> result.notImplemented()
                }
            }
    }

    private fun installedVersion(): Map<String, Any?> {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "versionName" to (info.versionName ?: ""),
            "versionCode" to code,
        )
    }

    /**
     * Starts Android's package installer for [path]. Returns false when the OS
     * refuses (usually the first time, until the user grants "install unknown
     * apps" for Treska) so the UI can offer to open that settings screen.
     */
    private fun installApk(path: String?): Boolean {
        if (path.isNullOrEmpty()) return false
        val file = File(path)
        if (!file.exists()) return false
        return try {
            val uri: Uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun openUnknownSourcesSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {
            // Some OEM builds lack this screen; the OS prompt still covers it.
        }
    }

    /**
     * Launches the app [pkg] if it is installed, else its Play Store page
     * (store app first, web as the last resort). Returns false only when none
     * of those could be opened. The package must be listed under <queries> in
     * the manifest, or Android 11+ hides it and we always land in the store.
     */
    private fun openApp(pkg: String?): Boolean {
        if (pkg.isNullOrEmpty()) return false
        val launch = packageManager.getLaunchIntentForPackage(pkg)
        if (launch != null) {
            return try {
                launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launch)
                true
            } catch (e: Exception) {
                false
            }
        }
        return openUrl("market://details?id=$pkg") ||
            openUrl("https://play.google.com/store/apps/details?id=$pkg")
    }

    /** Opens a link in whatever browser/activity can handle it. */
    private fun openUrl(url: String?): Boolean {
        if (url.isNullOrEmpty()) return false
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
