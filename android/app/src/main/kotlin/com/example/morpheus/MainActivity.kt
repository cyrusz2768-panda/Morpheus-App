package com.example.morpheus

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val albumWriter by lazy { DreamAlbumWriter(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "morpheus/dream_export")
            .setMethodCallHandler { call, result ->
                if (call.method == "saveToAlbum") albumWriter.save(call.argument<String>("path"), result)
                else result.notImplemented()
            }
        // Android 11起官方url_launcher可要求“只打开非浏览器App”。较旧系统
        // 没有这个Intent标记，普通ACTION_VIEW会把未安装音乐软件误判为打开成功。
        // 此桥接仅补旧系统缺口；网页浏览和新系统仍使用官方插件。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "morpheus/link_navigation")
            .setMethodCallHandler { call, result ->
                if (call.method != "openMusicIfLegacy") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    result.success(null)
                } else {
                    val url = call.argument<String>("url")
                    val uri = url?.let { Uri.parse(it) }
                    if (uri == null || uri.host.isNullOrEmpty() ||
                        (uri.scheme != "http" && uri.scheme != "https") || !uri.userInfo.isNullOrEmpty()
                    ) {
                        result.success(false)
                    } else {
                        result.success(openLegacyMusic(uri))
                    }
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == DreamAlbumWriter.REQUEST_WRITE) {
            albumWriter.permissionResult(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        }
    }

    @Suppress("DEPRECATION")
    private fun openLegacyMusic(uri: Uri): Boolean {
        // 通用网页处理方视作浏览器，不硬编码音乐软件包名或猜测私有scheme。
        // 实际分享链接匹配的其余处理方才有资格接收音乐跳转；无处理方返回false，
        // Dart层再打开App内浏览器。API24–29没有Android11的包可见性限制。
        val browsers = listOf("https://example.com", "http://example.com")
            .flatMap { address ->
                packageManager.queryIntentActivities(
                    Intent(Intent.ACTION_VIEW, Uri.parse(address)).addCategory(Intent.CATEGORY_BROWSABLE),
                    PackageManager.MATCH_DEFAULT_ONLY,
                )
            }.map { it.activityInfo.packageName }.toSet()
        val intent = Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
        val candidates = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .filter { it.activityInfo.packageName !in browsers }
        for (candidate in candidates) {
            try {
                startActivity(Intent(intent).setPackage(candidate.activityInfo.packageName))
                return true
            } catch (_: ActivityNotFoundException) {
                // 软件可能在解析后卸载，继续尝试其他已关联处理方。
            } catch (_: SecurityException) {
                // 私有/不可导出的Activity不接收跳转，交给后续处理方或网页兜底。
            }
        }
        return false
    }
}
