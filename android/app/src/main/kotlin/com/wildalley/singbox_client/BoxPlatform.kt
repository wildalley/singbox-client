package com.wildalley.singbox_client

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.system.OsConstants
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import java.net.InetSocketAddress
import java.net.NetworkInterface as JavaNetworkInterface

/**
 * Bridges libbox's platform requirements onto Android APIs.
 *
 * The important method is [openTun]: libbox hands us the tun parameters it
 * derived from the config, we translate them into a [android.net.VpnService.Builder],
 * and return the raw file descriptor for sing-box to drive.
 */
class BoxPlatform(private val service: SingBoxVpnService) : PlatformInterface {

    private val connectivity: ConnectivityManager
        get() = service.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    // ------------------------------------------------------------------ tun

    override fun openTun(options: TunOptions): Int {
        val builder = service.newBuilder()
            .setSession(SESSION_NAME)
            .setMtu(options.mtu)

        options.inet4Address.forEach { builder.addAddress(it.address(), it.prefix()) }
        options.inet6Address.forEach { builder.addAddress(it.address(), it.prefix()) }

        if (options.autoRoute) {
            // Route ranges already account for the configured excludes, so add
            // them verbatim rather than defaulting to 0.0.0.0/0.
            val v4Ranges = options.inet4RouteRange.toList()
            if (v4Ranges.isEmpty()) {
                builder.addRoute("0.0.0.0", 0)
            } else {
                v4Ranges.forEach { builder.addRoute(it.address(), it.prefix()) }
            }

            val v6Ranges = options.inet6RouteRange.toList()
            if (v6Ranges.isNotEmpty()) {
                v6Ranges.forEach { builder.addRoute(it.address(), it.prefix()) }
            } else if (options.inet6Address.toList().isNotEmpty()) {
                builder.addRoute("::", 0)
            }

            runCatching { builder.addDnsServer(options.dnsServerAddress.value) }
        }

        // Per-app routing. Our own package must stay outside the tunnel or the
        // subscription fetch would loop back through a proxy that isn't up yet.
        val include = options.includePackage.toList()
        val exclude = options.excludePackage.toList()
        if (include.isNotEmpty()) {
            include.forEach { pkg -> runCatching { builder.addAllowedApplication(pkg) } }
        } else {
            runCatching { builder.addDisallowedApplication(service.packageName) }
            exclude.forEach { pkg -> runCatching { builder.addDisallowedApplication(pkg) } }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            runCatching {
                builder.setHttpProxy(
                    android.net.ProxyInfo.buildDirectProxy(
                        options.httpProxyServer,
                        options.httpProxyServerPort,
                        options.httpProxyBypassDomain.toList(),
                    )
                )
            }
        }

        val descriptor = builder.establish()
            ?: error("VPN permission was revoked or another VPN is active")

        // Keep the ParcelFileDescriptor alive: closing it tears down the tun.
        service.retainTunDescriptor(descriptor)
        return descriptor.fd
    }

    // -------------------------------------------------------- interface info

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
        // Protect sing-box's own sockets from being routed back into the tun.
        service.protect(fd)
    }

    override fun useProcFS(): Boolean = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): io.nekohasekai.libbox.ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            error("connection owner lookup requires Android 10+")
        }
        val uid = connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        if (uid == android.os.Process.INVALID_UID) error("connection owner not found")

        val owner = io.nekohasekai.libbox.ConnectionOwner()
        owner.userId = uid
        val packages = service.packageManager.getPackagesForUid(uid)
        if (packages != null && packages.isNotEmpty()) {
            owner.userName = packages[0]
            owner.setAndroidPackageNames(StringArrayIterator(packages.toList()))
        }
        return owner
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val result = mutableListOf<io.nekohasekai.libbox.NetworkInterface>()
        val activeNetwork = connectivity.activeNetwork
        val capabilities = activeNetwork?.let { connectivity.getNetworkCapabilities(it) }

        val enumeration = JavaNetworkInterface.getNetworkInterfaces()
            ?: return InterfaceArrayIterator(result)

        for (java in enumeration) {
            val name = java.name ?: continue
            val item = io.nekohasekai.libbox.NetworkInterface()
            item.name = name
            item.index = java.index
            item.mtu = runCatching { java.mtu }.getOrDefault(1500)
            item.addresses = StringArrayIterator(cidrAddresses(java))
            item.dnsServer = StringArrayIterator(emptyList())
            item.flags = buildFlags(java)
            item.type = interfaceType(name, capabilities)
            item.metered = capabilities?.hasCapability(
                NetworkCapabilities.NET_CAPABILITY_NOT_METERED
            )?.not() ?: false
            result.add(item)
        }
        return InterfaceArrayIterator(result)
    }

    /**
     * Interface addresses as CIDR strings, filtered to what libbox can parse.
     *
     * libbox hands each string to Go's `netip.MustParsePrefix`, which **panics**
     * rather than returning an error — and a Go panic crossing the gomobile JNI
     * boundary aborts the whole process, so a single bad string here is a hard
     * crash, not a logged warning. Three shapes have to be filtered out:
     *
     *  - **Scoped IPv6.** `Inet6Address.getHostAddress()` appends the zone for
     *    link-local addresses (`fe80::1%wlan0`), and netip rejects zones inside
     *    a prefix. Every Wi-Fi interface carries one, so this is not an edge
     *    case: unfiltered, it crashes on essentially every device.
     *  - **Null host addresses**, which would stringify to `"null/24"`.
     *  - **Out-of-range prefix lengths**, which netip also rejects.
     */
    private fun cidrAddresses(java: JavaNetworkInterface): List<String> =
        runCatching {
            java.interfaceAddresses.mapNotNull { entry ->
                val address = entry.address ?: return@mapNotNull null
                // Drop the "%wlan0" / "%15" zone suffix.
                val host = address.hostAddress?.substringBefore('%')
                if (host.isNullOrEmpty()) return@mapNotNull null
                val bits = entry.networkPrefixLength.toInt()
                val max = if (address is java.net.Inet4Address) 32 else 128
                if (bits !in 0..max) return@mapNotNull null
                "$host/$bits"
            }
        }.getOrDefault(emptyList())

    private fun buildFlags(java: JavaNetworkInterface): Int {
        var flags = 0
        runCatching { if (java.isUp) flags = flags or OsConstants.IFF_UP }
        runCatching { if (java.isLoopback) flags = flags or OsConstants.IFF_LOOPBACK }
        runCatching { if (java.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT }
        runCatching { if (java.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST }
        return flags
    }

    private fun interfaceType(name: String, capabilities: NetworkCapabilities?): Int = when {
        name.startsWith("wlan") -> io.nekohasekai.libbox.Libbox.InterfaceTypeWIFI
        name.startsWith("rmnet") || name.startsWith("ccmni") ->
            io.nekohasekai.libbox.Libbox.InterfaceTypeCellular
        name.startsWith("eth") -> io.nekohasekai.libbox.Libbox.InterfaceTypeEthernet
        capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true ->
            io.nekohasekai.libbox.Libbox.InterfaceTypeWIFI
        capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true ->
            io.nekohasekai.libbox.Libbox.InterfaceTypeCellular
        else -> io.nekohasekai.libbox.Libbox.InterfaceTypeOther
    }

    // ---------------------------------------------------- default interface

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = notify(network)
            override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) =
                notify(network)

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities,
            ) = notify(network)

            override fun onLost(network: Network) {
                listener.updateDefaultInterface("", -1, false, false)
            }

            private fun notify(network: Network) {
                val properties = connectivity.getLinkProperties(network) ?: return
                val name = properties.interfaceName ?: return
                val java = runCatching { JavaNetworkInterface.getByName(name) }.getOrNull()
                val capabilities = connectivity.getNetworkCapabilities(network)
                val expensive = capabilities?.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_NOT_METERED
                )?.not() ?: false
                val constrained = if (Build.VERSION.SDK_INT >= 30) {
                    capabilities?.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_TEMPORARILY_NOT_METERED
                    )?.not() ?: false
                } else {
                    false
                }
                listener.updateDefaultInterface(name, java?.index ?: -1, expensive, constrained)
            }
        }
        networkCallback = callback
        connectivity.registerNetworkCallback(
            NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build(),
            callback,
        )
        // Report the current default immediately so sing-box does not wait for
        // the first network change.
        connectivity.activeNetwork?.let { network ->
            val name = connectivity.getLinkProperties(network)?.interfaceName
            if (name != null) {
                val index = runCatching { JavaNetworkInterface.getByName(name).index }
                    .getOrDefault(-1)
                listener.updateDefaultInterface(name, index, false, false)
            }
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkCallback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
        networkCallback = null
    }

    // --------------------------------------------------------------- unused

    /** Returning null makes libbox use its own resolver instead of Android's. */
    override fun localDNSTransport(): LocalDNSTransport? = null

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun readWIFIState(): WIFIState? = null

    override fun clearDNSCache() = Unit

    override fun systemCertificates(): StringIterator = StringArrayIterator(emptyList())

    override fun sendNotification(notification: Notification) = Unit

    private companion object {
        const val SESSION_NAME = "SingBox Client"
    }
}

// ------------------------------------------------------------------ iterators

/** libbox consumes lists through its own iterator interfaces. */
class StringArrayIterator(private val items: List<String>) : StringIterator {
    private var index = 0
    override fun len(): Int = items.size
    override fun hasNext(): Boolean = index < items.size
    override fun next(): String = items[index++]
}

private class InterfaceArrayIterator(
    private val items: List<io.nekohasekai.libbox.NetworkInterface>,
) : NetworkInterfaceIterator {
    private var index = 0
    override fun hasNext(): Boolean = index < items.size
    override fun next(): io.nekohasekai.libbox.NetworkInterface = items[index++]
}

// Kotlin `for`/`map` over libbox iterators.
private inline fun io.nekohasekai.libbox.RoutePrefixIterator.forEach(
    action: (io.nekohasekai.libbox.RoutePrefix) -> Unit,
) {
    while (hasNext()) action(next())
}

private fun io.nekohasekai.libbox.RoutePrefixIterator.toList():
    List<io.nekohasekai.libbox.RoutePrefix> {
    val result = mutableListOf<io.nekohasekai.libbox.RoutePrefix>()
    while (hasNext()) result.add(next())
    return result
}

private fun StringIterator.toList(): List<String> {
    val result = mutableListOf<String>()
    while (hasNext()) result.add(next())
    return result
}
