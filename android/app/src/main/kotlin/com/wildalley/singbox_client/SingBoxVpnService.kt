package com.wildalley.singbox_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import io.nekohasekai.libbox.CommandClient
import io.nekohasekai.libbox.CommandClientHandler
import io.nekohasekai.libbox.CommandClientOptions
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionEvents
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LogIterator
import io.nekohasekai.libbox.OutboundGroupIterator
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StatusMessage
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import java.io.File
import kotlin.concurrent.thread

/**
 * Runs sing-box inside a [VpnService].
 *
 * libbox owns the proxy engine; this service owns the Android VPN lifecycle.
 * [CommandServer] drives the engine, [CommandClient] subscribes to its status
 * and log streams, and both are forwarded to Flutter through [BoxEvents].
 */
class SingBoxVpnService : VpnService() {

    private var commandServer: CommandServer? = null
    private var commandClient: CommandClient? = null
    private var tunDescriptor: ParcelFileDescriptor? = null
    private val platform by lazy { BoxPlatform(this) }

    /** Guards start/stop/reload against concurrent intents. */
    private val lock = Any()

    override fun onCreate() {
        super.onCreate()
        instance = this
        setupLibbox()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopTunnel()
            return START_NOT_STICKY
        }

        val config = intent?.getStringExtra(EXTRA_CONFIG)
        if (config.isNullOrEmpty()) {
            // Restarted by the system without a config: nothing to resume.
            stopSelf()
            return START_NOT_STICKY
        }

        startForegroundNotification(getString(R.string.notification_connecting))
        // Engine startup does blocking IO (rule-set downloads, DNS), so keep it
        // off the main thread or the service will ANR.
        thread(name = "singbox-start") { startTunnel(config) }
        return START_STICKY
    }

    override fun onRevoke() {
        // The user revoked VPN permission, or another VPN took over.
        BoxEvents.setStage(BoxEvents.Stage.ERROR, "VPN permission was revoked")
        stopTunnel()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopTunnel()
        if (instance === this) instance = null
        super.onDestroy()
    }

    // ------------------------------------------------------------------ engine

    private fun setupLibbox() {
        if (libboxReady) return
        val working = File(filesDir, "work").apply { mkdirs() }
        val temp = File(cacheDir, "temp").apply { mkdirs() }
        runCatching {
            Libbox.setup(
                SetupOptions().apply {
                    basePath = filesDir.absolutePath
                    workingPath = working.absolutePath
                    tempPath = temp.absolutePath
                    // Works around a Go runtime stack issue on Android.
                    fixAndroidStack = true
                    logMaxLines = 300
                }
            )
            Libbox.setMemoryLimit(true)
            libboxReady = true
        }.onFailure { Log.e(TAG, "libbox setup failed", it) }
    }

    private fun startTunnel(config: String) {
        synchronized(lock) {
            if (commandServer != null) {
                // Already running: treat this as a config change.
                runCatching { commandServer?.startOrReloadService(config, OverrideOptions()) }
                    .onFailure { fail(it) }
                return
            }

            BoxEvents.setStage(BoxEvents.Stage.STARTING)
            try {
                val server = Libbox.newCommandServer(ServerHandler(), platform)
                server.start()
                commandServer = server
                // This is what actually parses the config and opens the tun.
                server.startOrReloadService(config, OverrideOptions())

                connectCommandClient()

                BoxEvents.setStage(BoxEvents.Stage.CONNECTED)
                updateNotification(getString(R.string.notification_connected))
            } catch (error: Throwable) {
                fail(error)
                stopTunnel()
            }
        }
    }

    private fun stopTunnel() {
        synchronized(lock) {
            if (commandServer == null && tunDescriptor == null) {
                stopForegroundCompat()
                stopSelf()
                return
            }
            // Preserve an error stage so the UI can explain what went wrong.
            val failed = BoxEvents.stage == BoxEvents.Stage.ERROR
            if (!failed) BoxEvents.setStage(BoxEvents.Stage.STOPPING)

            runCatching { commandClient?.disconnect() }
            commandClient = null

            runCatching { commandServer?.closeService() }
            runCatching { commandServer?.close() }
            commandServer = null

            runCatching { tunDescriptor?.close() }
            tunDescriptor = null

            if (!failed) BoxEvents.setStage(BoxEvents.Stage.DISCONNECTED)
            stopForegroundCompat()
            stopSelf()
        }
    }

    /** Applies a new config to the running engine without dropping the tun. */
    fun reload(config: String) {
        synchronized(lock) {
            val server = commandServer ?: return
            runCatching { server.startOrReloadService(config, OverrideOptions()) }
                .onFailure { fail(it) }
        }
    }

    fun selectOutbound(group: String, tag: String) {
        runCatching { commandClient?.selectOutbound(group, tag) }
            .onFailure { Log.w(TAG, "selectOutbound failed", it) }
    }

    private fun connectCommandClient() {
        val options = CommandClientOptions().apply {
            statusInterval = STATUS_INTERVAL_NANOS
            // Subscribe before the client is built, so the first connect already
            // carries the subscriptions.
            addCommand(Libbox.CommandStatus)
            addCommand(Libbox.CommandLog)
        }
        val client = Libbox.newCommandClient(ClientHandler(), options)
        client.connect()
        commandClient = client
    }

    private fun fail(error: Throwable) {
        val detail = error.message ?: error.toString()
        Log.e(TAG, "sing-box failure: $detail", error)
        BoxEvents.setStage(BoxEvents.Stage.ERROR, detail)
        updateNotification(getString(R.string.notification_error))
    }

    // --------------------------------------------------------------- tun state

    /**
     * [Builder] is a non-static inner class, so only this service can create
     * one. [BoxPlatform] goes through here.
     */
    fun newBuilder(): Builder = Builder()

    /** Called by [BoxPlatform] after `establish()` so the fd stays open. */
    fun retainTunDescriptor(descriptor: ParcelFileDescriptor) {
        runCatching { tunDescriptor?.close() }
        tunDescriptor = descriptor
    }

    // ------------------------------------------------------------- notification

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.notification_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setShowBadge(false)
                description = getString(R.string.notification_channel_description)
            }
        )
    }

    private fun buildNotification(text: String): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, SingBoxVpnService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_tunnel)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(
                Notification.Action.Builder(
                    null,
                    getString(R.string.notification_action_stop),
                    stopIntent,
                ).build()
            )
            .build()
    }

    private fun startForegroundNotification(text: String) {
        val notification = buildNotification(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        runCatching { manager.notify(NOTIFICATION_ID, buildNotification(text)) }
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    // ------------------------------------------------------------- libbox hooks

    /** Commands libbox sends back to the platform. */
    private inner class ServerHandler : CommandServerHandler {
        override fun serviceStop() {
            stopTunnel()
        }

        override fun serviceReload() {
            // Reload is driven from Flutter, so there is nothing to do here.
        }

        override fun getSystemProxyStatus(): SystemProxyStatus =
            SystemProxyStatus().apply {
                // Android routes everything through the tun; there is no
                // separate system-proxy toggle to report.
                available = false
                enabled = false
            }

        override fun setSystemProxyEnabled(enabled: Boolean) = Unit

        override fun writeDebugMessage(message: String) {
            Log.d(TAG, message)
        }
    }

    /** Status and log streams from the running engine. */
    private inner class ClientHandler : CommandClientHandler {
        override fun connected() = Unit

        override fun disconnected(message: String) {
            if (message.isNotEmpty()) BoxEvents.emitLog("disconnected: $message")
        }

        override fun writeStatus(message: StatusMessage) {
            BoxEvents.emitTraffic(
                uplink = message.uplink,
                downlink = message.downlink,
                uplinkTotal = message.uplinkTotal,
                downlinkTotal = message.downlinkTotal,
                connectionsIn = message.connectionsIn,
                connectionsOut = message.connectionsOut,
                memory = message.memory,
            )
        }

        override fun writeLogs(messageList: LogIterator) {
            while (messageList.hasNext()) {
                BoxEvents.emitLog(messageList.next().message)
            }
        }

        override fun clearLogs() = Unit

        override fun setDefaultLogLevel(level: Int) = Unit

        override fun initializeClashMode(modeList: StringIterator, currentMode: String) = Unit

        override fun updateClashMode(newMode: String) = Unit

        override fun writeGroups(message: OutboundGroupIterator) = Unit

        override fun writeConnectionEvents(events: ConnectionEvents) = Unit
    }

    companion object {
        const val ACTION_STOP = "com.wildalley.singbox_client.STOP"
        const val EXTRA_CONFIG = "config"

        private const val TAG = "SingBoxVpn"
        private const val CHANNEL_ID = "singbox-tunnel"
        private const val NOTIFICATION_ID = 1

        /** libbox reports status on this interval, in nanoseconds. */
        private const val STATUS_INTERVAL_NANOS = 1_000_000_000L

        /** `Libbox.setup` is process-global and must run only once. */
        @Volatile
        private var libboxReady = false

        /** Lets the Flutter plugin talk to a service that is already running. */
        @Volatile
        var instance: SingBoxVpnService? = null
            private set
    }
}
