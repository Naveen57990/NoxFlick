package com.naveen.flik.network

import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.*
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder

class FlikPhoneServer(
    private val context: Context,
    private val onFileReceived: (File, String) -> Unit
) {
    private val tag = "FlikPhoneServer"
    private var serverSocket: ServerSocket? = null
    private var isRunning = false
    private var serverJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    val port = 52841

    fun isAlive(): Boolean = isRunning && serverSocket != null && !serverSocket!!.isClosed

    fun start() {
        if (isAlive()) return
        stop()
        isRunning = true
        serverJob = scope.launch {
            try {
                serverSocket = ServerSocket().apply {
                    reuseAddress = true
                    bind(InetSocketAddress(port))
                }
                Log.d(tag, "📱 Phone receiver server started on port $port")
                supervisorScope {
                    while (isRunning && serverSocket != null && !serverSocket!!.isClosed) {
                        try {
                            val client = serverSocket!!.accept()
                            launch(Dispatchers.IO) {
                                handleConnection(client)
                            }
                        } catch (e: Exception) {
                            if (!isRunning) break
                            Log.w(tag, "Accept exception: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                if (isRunning) {
                    Log.e(tag, "Server error: ${e.message}")
                }
            }
        }
    }

    fun stop() {
        isRunning = false
        try {
            serverSocket?.close()
        } catch (e: Exception) {
            // Ignored
        }
        serverSocket = null
        serverJob?.cancel()
        serverJob = null
    }

    private suspend fun handleConnection(socket: Socket) = withContext(Dispatchers.IO) {
        try {
            val input = BufferedInputStream(socket.getInputStream())
            val output = BufferedOutputStream(socket.getOutputStream())

            // Read HTTP headers
            val headerBytes = ByteArrayOutputStream()
            var prev1 = -1
            var prev2 = -1
            var prev3 = -1
            var b: Int

            while (input.read().also { b = it } != -1) {
                headerBytes.write(b)
                if (prev3 == '\r'.code && prev2 == '\n'.code && prev1 == '\r'.code && b == '\n'.code) {
                    break
                }
                prev3 = prev2
                prev2 = prev1
                prev1 = b
            }

            val headerStr = headerBytes.toString("UTF-8")
            val lines = headerStr.split("\r\n")
            if (lines.isEmpty()) {
                socket.close()
                return@withContext
            }

            val requestLine = lines[0].split(" ")
            if (requestLine.size < 2) {
                socket.close()
                return@withContext
            }

            val method = requestLine[0]
            val path = requestLine[1]

            val headers = mutableMapOf<String, String>()
            for (i in 1 until lines.size) {
                val line = lines[i]
                val idx = line.indexOf(":")
                if (idx != -1) {
                    val k = line.substring(0, idx).trim().lowercase()
                    val v = line.substring(idx + 1).trim()
                    headers[k] = v
                }
            }

            if (path == "/ping" || path == "/status") {
                val json = JSONObject().apply {
                    put("status", "ready")
                    put("deviceName", "${Build.MANUFACTURER} ${Build.MODEL}")
                    put("port", port)
                }.toString()

                val res = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${json.toByteArray().size}\r\nConnection: close\r\n\r\n$json"
                output.write(res.toByteArray())
                output.flush()
                socket.close()
                return@withContext
            }

            if (path.startsWith("/transfer")) {
                val rawName = headers["x-file-name"] ?: "received_${System.currentTimeMillis()}.dat"
                val decodedName = try { URLDecoder.decode(rawName, "UTF-8") } catch (e: Exception) { rawName }
                val safeName = File(decodedName).name.replace("/", "_")
                val contentLength = headers["content-length"]?.toLongOrNull() ?: 0L
                val mimeType = headers["content-type"] ?: "application/octet-stream"

                Log.d(tag, "📥 Receiving file from Mac: $safeName ($contentLength bytes)")

                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!downloadsDir.exists()) downloadsDir.mkdirs()

                var targetFile = File(downloadsDir, safeName)
                if (targetFile.exists()) {
                    val base = targetFile.nameWithoutExtension
                    val ext = targetFile.extension
                    targetFile = File(downloadsDir, "${base}_${System.currentTimeMillis()}.${ext}")
                }

                FileOutputStream(targetFile).use { fos ->
                    val buffer = ByteArray(65536)
                    var bytesRemaining = contentLength
                    var read = 0

                    if (contentLength > 0) {
                        while (bytesRemaining > 0 && input.read(buffer, 0, Math.min(buffer.size.toLong(), bytesRemaining).toInt()).also { read = it } != -1) {
                            fos.write(buffer, 0, read)
                            bytesRemaining -= read
                        }
                    } else {
                        while (input.read(buffer).also { read = it } != -1) {
                            fos.write(buffer, 0, read)
                        }
                    }
                    fos.flush()
                }

                // Index with MediaScanner so photos/videos appear immediately in Gallery
                MediaScannerConnection.scanFile(context, arrayOf(targetFile.absolutePath), arrayOf(mimeType), null)

                val resJson = JSONObject().apply {
                    put("success", true)
                    put("fileName", targetFile.name)
                }.toString()

                val res = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${resJson.toByteArray().size}\r\nConnection: close\r\n\r\n$resJson"
                output.write(res.toByteArray())
                output.flush()
                socket.close()

                withContext(Dispatchers.Main) {
                    onFileReceived(targetFile, mimeType)
                }
            } else {
                val notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                output.write(notFound.toByteArray())
                output.flush()
                socket.close()
            }
        } catch (e: Exception) {
            Log.e(tag, "Connection error: ${e.message}")
            try { socket.close() } catch (ignored: Exception) {}
        }
    }
}
