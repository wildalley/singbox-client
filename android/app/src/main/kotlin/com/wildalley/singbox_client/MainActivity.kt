package com.wildalley.singbox_client

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and bridges it to [SingBoxVpnService].
 *
 * Two channels: `singbox/control` for commands, `singbox/events` for the
 * status/traffic/log stream. State itself lives in [BoxEvents] so the tunnel can
 * outlive this activity.
 */
class MainActivity : FlutterActivity() {

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    /** Pending `requestPermission` call, answered in [onActivityResult]. */
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONTROL_CHANNEL,
        ).apply { setMethodCallHandler(::onMethodCall) }

        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENTS_CHANNEL,
        ).apply {
            setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                        eventSink = sink
                        BoxEvents.setListener(
                            object : BoxEvents.Listener {
                                override fun onEvent(event: Map<String, Any?>) {
                                    // libbox emits from its own threads; the
                                    // channel requires the main thread.
                                    runOnUiThread { eventSink?.success(event) }
                                }
                            }
                        )
                        // Replay current state so a fresh engine is not blank
                        // while the tunnel is already up.
                        sink.success(BoxEvents.statusMap())
                    }

                    override fun onCancel(arguments: Any?) {
                        BoxEvents.setListener(null)
                        eventSink = null
                    }
                }
            )
        }
    }

    override fun onDestroy() {
        BoxEvents.setListener(null)
        eventSink = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        super.onDestroy()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestVpnPermission(result)

            "start" -> {
                val config = call.argument<String>("config")
                if (config.isNullOrEmpty()) {
                    result.error("bad_args", "config is required", null)
                    return
                }
                startService(config)
                result.success(null)
            }

            "stop" -> {
                val intent = Intent(this, SingBoxVpnService::class.java)
                    .setAction(SingBoxVpnService.ACTION_STOP)
                // The service is already running, so a plain start delivers the
                // stop action without needing foreground privileges.
                runCatching { startService(intent) }
                result.success(null)
            }

            "reload" -> {
                val config = call.argument<String>("config")
                if (config.isNullOrEmpty()) {
                    result.error("bad_args", "config is required", null)
                    return
                }
                val service = SingBoxVpnService.instance
                if (service == null) {
                    result.error("not_running", "The tunnel is not running", null)
                } else {
                    service.reload(config)
                    result.success(null)
                }
            }

            "selectOutbound" -> {
                val tag = call.argument<String>("tag")
                if (tag.isNullOrEmpty()) {
                    result.error("bad_args", "tag is required", null)
                    return
                }
                val service = SingBoxVpnService.instance
                if (service == null) {
                    result.error("not_running", "The tunnel is not running", null)
                } else {
                    service.selectOutbound(PROXY_GROUP, tag)
                    result.success(null)
                }
            }

            // Asks the engine to measure every member of the proxy selector
            // through the tunnel. Results do not come back here — they arrive on
            // the event channel as a `groups` event, because libbox reports them
            // to the group subscription rather than to the caller.
            "urlTest" -> {
                val service = SingBoxVpnService.instance
                if (service == null) {
                    result.error("not_running", "The tunnel is not running", null)
                } else {
                    try {
                        service.urlTest(PROXY_GROUP)
                        result.success(null)
                    } catch (error: Throwable) {
                        result.error("url_test_failed", error.message ?: "urlTest failed", null)
                    }
                }
            }

            "status" -> result.success(BoxEvents.statusMap())

            // Where Dart unpacks the bundled rule-sets. Deliberately the same
            // directory libbox is set up with (SetupOptions.basePath), so the
            // files the config points at live beside the engine's own state.
            "dataDir" -> result.success(filesDir.absolutePath)

            "version" -> result.success(
                runCatching { io.nekohasekai.libbox.Libbox.version() }
                    .getOrDefault("unknown")
            )

            else -> result.notImplemented()
        }
    }

    private fun requestVpnPermission(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            // Already granted.
            result.success(true)
            return
        }
        if (permissionResult != null) {
            result.error("busy", "A permission request is already in flight", null)
            return
        }
        permissionResult = result
        startActivityForResult(intent, REQUEST_VPN_PERMISSION)
    }

    private fun startService(config: String) {
        val intent = Intent(this, SingBoxVpnService::class.java)
            .putExtra(SingBoxVpnService.EXTRA_CONFIG, config)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    @Deprecated("Matches FlutterActivity's own onActivityResult contract")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_VPN_PERMISSION) {
            val pending = permissionResult
            permissionResult = null
            pending?.success(resultCode == Activity.RESULT_OK)
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    private companion object {
        const val CONTROL_CHANNEL = "singbox/control"
        const val EVENTS_CHANNEL = "singbox/events"
        const val REQUEST_VPN_PERMISSION = 0x5B01

        /** Selector tag rendered by ConfigBuilder; runtime switching targets it. */
        const val PROXY_GROUP = "proxy"
    }
}
