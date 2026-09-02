package com.jmcomic3.yee

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import android.view.Display
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.io.File
import opensource.jenny.Jni
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
import android.hardware.biometrics.BiometricPrompt
import java.util.concurrent.TimeUnit
import android.os.CancellationSignal

class MainActivity : FlutterActivity() {

    private val uiThreadHandler = Handler(Looper.getMainLooper())
    private val pool =
        Executors.newCachedThreadPool { runnable -> Thread(runnable).also { it.isDaemon = true } }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // 初始化
        Jni.init(context.filesDir.absolutePath)
        // channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "methods").setMethodCallHandler(
            this::methods
        )
        //
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "volume_button")
            .setStreamHandler(volumeStreamHandler)
        // super
        super.configureFlutterEngine(flutterEngine)
    }

    private fun methods(call: MethodCall, result: MethodChannel.Result) {
        result.withCoroutine {
            when (call.method) {
                "invoke" -> Jni.invoke(call.arguments<String>())
                "saveImageFileToGallery" -> saveImageFileToGallery(call.arguments<String>()!!)
                "androidGetModes" -> {
                    modes()
                }
                "androidSetMode" -> {
                    setMode(call.argument("mode")!!)
                }
                "androidGetVersion" -> Build.VERSION.SDK_INT
                "androidStorageRoot" -> storageRoot()
                "androidDefaultExportsDir" -> androidDefaultExportsDir().absolutePath
                "androidMkdirs" -> androidMkdirs(
                    call.arguments<String>() ?: throw Exception("need arg"),
                )
                "picturesDir" -> picturesDir().absolutePath
                "verifyAuthentication" -> auth()
                else -> notImplementedToken
            }
        }
    }

    private val notImplementedToken = Any()
    private fun MethodChannel.Result.withCoroutine(exec: () -> Any?) {
        pool.submit {
            try {
                val data = exec()
                uiThreadHandler.post {
                    when (data) {
                        notImplementedToken -> {
                            notImplemented()
                        }
                        is Unit, null -> {
                            success(null)
                        }
                        else -> {
                            success(data)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e("Method", "Exception", e)
                uiThreadHandler.post {
                    error("", e.message, "")
                }
            }

        }
    }

    private fun saveImageFileToGallery(path: String) {
        BitmapFactory.decodeFile(path)?.let { bitmap ->
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, System.currentTimeMillis().toString())
                put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { //this one
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }
            contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                ?.let { uri ->
                    contentResolver.openOutputStream(uri)?.use { fos ->
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 100, fos)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) { //this one
                        contentValues.clear()
                        contentValues.put(MediaStore.Video.Media.IS_PENDING, 0)
                        contentResolver.update(uri, contentValues, null, null)
                    }
                }
        }
    }

    // fps mods
    private fun mixDisplay(): Display? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.let {
                return it
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            windowManager.defaultDisplay?.let {
                return it
            }
        }
        return null
    }

    private fun modes(): List<String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            mixDisplay()?.let { display ->
                return display.supportedModes.map { mode ->
                    mode.toString()
                }
            }
        }
        return ArrayList()
    }

    private fun setMode(string: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            mixDisplay()?.let { display ->
                if (string == "") {
                    uiThreadHandler.post {
                        window.attributes = window.attributes.also { attr ->
                            attr.preferredDisplayModeId = 0
                        }
                    }
                    return
                }
                return display.supportedModes.forEach { mode ->
                    if (mode.toString() == string) {
                        uiThreadHandler.post {
                            window.attributes = window.attributes.also { attr ->
                                attr.preferredDisplayModeId = mode.modeId
                            }
                        }
                        return
                    }
                }
            }
        }
    }

// volume_buttons

    private var volumeEvents: EventChannel.EventSink? = null

    private val volumeStreamHandler = object : EventChannel.StreamHandler {

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            volumeEvents = events
        }

        override fun onCancel(arguments: Any?) {
            volumeEvents = null
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        volumeEvents?.let {
            if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
                uiThreadHandler.post {
                    it.success("DOWN")
                }
                return true
            }
            if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
                uiThreadHandler.post {
                    it.success("UP")
                }
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    fun storageRoot(): String {
        return Environment.getExternalStorageDirectory().absolutePath
    }

    private fun picturesDir(): File {
        return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
            ?: throw java.lang.IllegalStateException()
    }

    private fun downloadsDir(): File {
        return Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            ?: throw java.lang.IllegalStateException()
    }

    private fun defaultJennyDir(): File {
        return File(downloadsDir(), "jmtt2mic")
    }

    private fun androidDefaultExportsDir(): File {
        return File(defaultJennyDir(), "exports")
    }

    private fun androidMkdirs(path: String) {
        val dir = File(path)
        if (!dir.exists()) {
            dir.mkdirs()
        }
    }
    private fun auth(): Boolean {
        val queue = LinkedBlockingQueue<Boolean>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val completed = AtomicBoolean(false)
            val finish: (Boolean) -> Unit = { value ->
                if (completed.compareAndSet(false, true)) {
                    queue.offer(value)
                }
            }
            var mBiometricPrompt = BiometricPrompt.Builder(this)
                .setTitle("验证身份")
                .setDescription("需要验证您的身份")
                .setNegativeButton(
                    "取消", mainExecutor
                ) { _, _ -> finish(false) }
                .build()


            var mCancellationSignal = CancellationSignal()
            mCancellationSignal.setOnCancelListener {
                finish(false)
            }

            var mAuthenticationCallback = object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) {
                    super.onAuthenticationError(errorCode, errString)
                    finish(false)
                }

                override fun onAuthenticationFailed() {
                    super.onAuthenticationFailed()
                    // A failed attempt is non-terminal; the user may retry.
                }

                override fun onAuthenticationSucceeded(result1: BiometricPrompt.AuthenticationResult?) {
                    super.onAuthenticationSucceeded(result1)
                    finish(true)
                }
            }

            mBiometricPrompt.authenticate(
                mCancellationSignal,
                mainExecutor,
                mAuthenticationCallback
            )

        } else {
            queue.add(false)
        }

        return queue.poll(5, TimeUnit.MINUTES) ?: false
    }

}
