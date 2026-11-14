package com.naveen.flik.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.net.InetAddress

class NsdDiscoveryManager(private val context: Context) {
    private val tag = "NsdDiscoveryManager"
    private val serviceType = "_flick._tcp."
    
    private val nsdManager: NsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val _devices = MutableStateFlow<List<DiscoveredMac>>(emptyList())
    val devices: StateFlow<List<DiscoveredMac>> = _devices.asStateFlow()

    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private var isDiscovering = false

    fun startDiscovery() {
        if (isDiscovering) return

        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
                Log.e(tag, "Discovery start failed: $errorCode")
                isDiscovering = false
            }

            override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {
                Log.e(tag, "Discovery stop failed: $errorCode")
                isDiscovering = false
            }

            override fun onDiscoveryStarted(regType: String?) {
                Log.d(tag, "Service discovery started for: $regType")
                isDiscovering = true
            }

            override fun onDiscoveryStopped(serviceType: String?) {
                Log.d(tag, "Service discovery stopped")
                isDiscovering = false
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                Log.d(tag, "Service found: ${serviceInfo.serviceName}")
                // Resolve service to get IP and Port
                resolveService(serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                Log.d(tag, "Service lost: ${serviceInfo.serviceName}")
                _devices.update { current ->
                    current.filter { it.name != serviceInfo.serviceName }
                }
            }
        }

        try {
            nsdManager.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (e: Exception) {
            Log.e(tag, "Failed to start service discovery", e)
        }
    }

    private fun resolveService(serviceInfo: NsdServiceInfo) {
        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) {
                Log.e(tag, "Resolve failed for ${serviceInfo?.serviceName}: $errorCode")
            }

            override fun onServiceResolved(resolvedInfo: NsdServiceInfo) {
                val host: InetAddress = resolvedInfo.host
                val port: Int = resolvedInfo.port
                val deviceName = resolvedInfo.serviceName

                Log.d(tag, "Resolved: $deviceName at ${host.hostAddress}:$port")
                val device = DiscoveredMac(
                    name = deviceName,
                    host = host.hostAddress ?: "127.0.0.1",
                    port = port
                )

                _devices.update { current ->
                    val filtered = current.filter { it.name != deviceName }
                    filtered + device
                }
            }
        }

        try {
            nsdManager.resolveService(serviceInfo, resolveListener)
        } catch (e: Exception) {
            Log.e(tag, "Resolve invocation failed", e)
        }
    }

    private var registrationListener: NsdManager.RegistrationListener? = null
    private var isRegistered = false

    fun registerPhoneService(port: Int = 52841) {
        if (isRegistered) return
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "${Build.MANUFACTURER} ${Build.MODEL}"
            serviceType = "_flick_phone._tcp."
            setPort(port)
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(NsdServiceInfo: NsdServiceInfo?) {
                Log.d(tag, "Phone service registered: ${NsdServiceInfo?.serviceName}")
                isRegistered = true
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) {
                Log.e(tag, "Registration failed: $errorCode")
                isRegistered = false
            }

            override fun onServiceUnregistered(arg0: NsdServiceInfo?) {
                Log.d(tag, "Phone service unregistered")
                isRegistered = false
            }

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) {
                Log.e(tag, "Unregistration failed: $errorCode")
            }
        }

        try {
            nsdManager.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
        } catch (e: Exception) {
            Log.e(tag, "Failed to register phone service", e)
        }
    }

    fun unregisterPhoneService() {
        if (!isRegistered) return
        try {
            registrationListener?.let { nsdManager.unregisterService(it) }
        } catch (e: Exception) {
            Log.e(tag, "Failed to unregister phone service", e)
        }
        registrationListener = null
        isRegistered = false
    }

    fun stopDiscovery() {
        if (!isDiscovering) return
        try {
            discoveryListener?.let { nsdManager.stopServiceDiscovery(it) }
        } catch (e: Exception) {
            Log.e(tag, "Error stopping discovery", e)
        }
        discoveryListener = null
        isDiscovering = false
    }
}
