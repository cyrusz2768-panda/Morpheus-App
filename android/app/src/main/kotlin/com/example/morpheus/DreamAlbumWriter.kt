package com.example.morpheus

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** 只负责把已生成的PNG交给相册，不读取其他照片，也不参与梦境数据库保存。 */
class DreamAlbumWriter(private val activity: Activity) {
    private var pending: Pair<File, MethodChannel.Result>? = null
    companion object { const val REQUEST_WRITE = 7041 }

    fun save(path: String?, result: MethodChannel.Result) {
        val file = path?.let { File(it) }
        if (file == null || !file.isFile) {
            result.error("saveFailed", "Missing export file", null)
            return
        }
        if (pending != null) {
            result.error("saveFailed", "Save already pending", null)
            return
        }
        pending = file to result
        // Android10+写自己新建的媒体无需READ_MEDIA_IMAGES或存储权限。
        // API24–28只在按下保存时申请旧写权限，拒绝后不妨碍系统分享。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_WRITE)
        } else { writePending() }
    }

    fun permissionResult(granted: Boolean) {
        if (granted) writePending()
        else finish("permissionDenied")
    }

    private fun finish(error: String? = null) {
        activity.runOnUiThread {
            val result = pending?.second
            pending = null
            if (error == null) result?.success(null)
            else result?.error(error, null, null)
        }
    }

    private fun writePending() {
        val source = pending?.first ?: return
        // 图片可能很长，文件复制不阻塞Android主线程。成功返回前完成流关闭；
        // 失败删除尚未发布的MediaStore行，避免相册留下损坏的半张图片。
        Thread {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val resolver = activity.contentResolver
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, source.name)
                        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Morpheus")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("MediaStore insert failed")
                    try {
                        val output = resolver.openOutputStream(uri)
                            ?: throw IllegalStateException("MediaStore stream unavailable")
                        output.use { target -> source.inputStream().use { it.copyTo(target) } }
                        val updated = resolver.update(uri, ContentValues().apply {
                            put(MediaStore.Images.Media.IS_PENDING, 0)
                        }, null, null)
                        check(updated > 0) { "MediaStore publish failed" }
                    } catch (error: Exception) {
                        resolver.delete(uri, null, null)
                        throw error
                    }
                    finish()
                } else {
                    writeLegacy(source)
                }
            } catch (_: Exception) { finish("saveFailed") }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun writeLegacy(source: File) {
        val root = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Morpheus")
        check(root.isDirectory || root.mkdirs())
        val target = File(root, source.name)
        try {
            source.copyTo(target)
            MediaScannerConnection.scanFile(activity, arrayOf(target.path), arrayOf("image/png")) { _, uri ->
                if (uri == null) { target.delete(); finish("saveFailed") }
                else finish()
            }
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }
}
