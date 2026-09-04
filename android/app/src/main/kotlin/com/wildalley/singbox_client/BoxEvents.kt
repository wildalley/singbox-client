package com.wildalley.singbox_client

import android.os.SystemClock

/**
 * Single place the service and the Flutter plugin agree on for runtime state.
 *
 * The service can outlive the Flutter engine (the user swipes the app away but
 * keeps the tunnel up), so state lives here as process-global truth and the
 * plugin attaches/detaches a listener around it.
 */
object BoxEvents {

    enum class Stage(val wire: String) {
        DISCONNECTED("disconnected"),
        STARTING("starting"),
        CONNECTED("connected"),
        STOPPING("stopping"),
        ERROR("error"),
    }

    interface Listener {
        fun onEvent(event: Map<String, Any?>)
    }

    @Volatile
    private var listener: Listener? = null

    @Volatile
    var stage: Stage = Stage.DISCONNECTED
        private set

    @Volatile
    var message: String? = null
        private set

    /** Epoch millis of the moment the tunnel reached [Stage.CONNECTED]. */
    @Volatile
    var since: Long? = null
        private set

    /** Increases for every new start/reload generation of the service. */
    @Volatile
    var session: Long = 0L
        private set

    // A broken endpoint can make sing-box emit the same error many times per
    // second.  EventChannel posts each event to Flutter's main thread, so an
    // unbounded stream can starve the UI before Dart gets a chance to render.
    private const val LOG_WINDOW_MILLIS = 1_000L
    private const val MAX_LOG_EVENTS_PER_WINDOW = 60
    private var logWindowStartedAt = 0L
    private var logEventsInWindow = 0
    private var suppressedLogEvents = 0

    fun setListener(value: Listener?) {
        listener = value
    }

    fun setStage(next: Stage, detail: String? = null) {
        stage = next
        message = detail
        since = if (next == Stage.CONNECTED) (since ?: System.currentTimeMillis()) else null
        emit(statusMap())
    }

    /** Marks callbacks from a previous engine generation as stale. */
    @Synchronized
    fun beginSession() {
        session += 1L
        since = null
    }

    fun statusMap(): Map<String, Any?> = mapOf(
        "type" to "status",
        "stage" to stage.wire,
        "message" to message,
        "since" to since,
        "session" to session,
    )

    fun emitTraffic(
        uplink: Long,
        downlink: Long,
        uplinkTotal: Long,
        downlinkTotal: Long,
        connectionsIn: Int,
        connectionsOut: Int,
        memory: Long,
    ) {
        emit(
            mapOf(
                "type" to "traffic",
                "uplink" to uplink,
                "downlink" to downlink,
                "uplinkTotal" to uplinkTotal,
                "downlinkTotal" to downlinkTotal,
                "connectionsIn" to connectionsIn,
                "connectionsOut" to connectionsOut,
                "memory" to memory,
            )
        )
    }

    @Synchronized
    fun emitLog(message: String) {
        val now = SystemClock.elapsedRealtime()
        if (logWindowStartedAt == 0L || now - logWindowStartedAt >= LOG_WINDOW_MILLIS) {
            if (suppressedLogEvents > 0) {
                emit(
                    mapOf(
                        "type" to "log",
                        "message" to "WARN log stream: $suppressedLogEvents lines suppressed",
                    )
                )
            }
            logWindowStartedAt = now
            logEventsInWindow = 0
            suppressedLogEvents = 0
        }

        if (logEventsInWindow >= MAX_LOG_EVENTS_PER_WINDOW) {
            suppressedLogEvents++
            return
        }
        logEventsInWindow++
        emit(mapOf("type" to "log", "message" to message))
    }

    /** Resets bridge-side counters after the engine log buffer is cleared. */
    @Synchronized
    fun resetLogThrottle() {
        logWindowStartedAt = 0L
        logEventsInWindow = 0
        suppressedLogEvents = 0
    }

    /**
     * Outbound groups as the engine reports them: each member's URL-test delay,
     * and which member the group is sending through.
     *
     * [groups] is already flattened into channel-safe maps, because the libbox
     * iterators it came from are only valid inside the callback that handed them
     * over.
     */
    fun emitGroups(groups: List<Map<String, Any?>>) {
        emit(mapOf("type" to "groups", "groups" to groups))
    }

    private fun emit(event: Map<String, Any?>) {
        listener?.onEvent(event)
    }
}
