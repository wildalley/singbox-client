package com.wildalley.singbox_client

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

    fun setListener(value: Listener?) {
        listener = value
    }

    fun setStage(next: Stage, detail: String? = null) {
        stage = next
        message = detail
        since = if (next == Stage.CONNECTED) (since ?: System.currentTimeMillis()) else null
        emit(statusMap())
    }

    fun statusMap(): Map<String, Any?> = mapOf(
        "type" to "status",
        "stage" to stage.wire,
        "message" to message,
        "since" to since,
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

    fun emitLog(message: String) {
        emit(mapOf("type" to "log", "message" to message))
    }

    private fun emit(event: Map<String, Any?>) {
        listener?.onEvent(event)
    }
}
