package com.naveen.flik.discovery

data class DiscoveredMac(
    val name: String,
    val host: String,
    val port: Int,
    val isOnline: Boolean = true
)
