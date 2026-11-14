package com.naveen.flik.network

import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Log
import com.naveen.flik.discovery.DiscoveredMac
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class FlikTransferClient(private val context: Context) {
    private val tag = "FlikTransferClient"

    suspend fun ping(mac: DiscoveredMac): Boolean = withContext(Dispatchers.IO) {
        val target = "http://${mac.host}:${mac.port}/ping"
        try {
            val url = URL(target)
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 3000
            conn.readTimeout = 3000
            conn.requestMethod = "GET"
            val code = conn.responseCode
            conn.disconnect()
            code in 200..299
        } catch (e: Exception) {
            Log.e(tag, "Ping to $target failed: ${e.message}")
            false
        }
    }

    suspend fun sendLink(mac: DiscoveredMac, linkUrl: String): Boolean = withContext(Dispatchers.IO) {
        val target = "http://${mac.host}:${mac.port}/link"
        try {
            val url = URL(target)
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")

            val json = JSONObject().apply {
                put("url", linkUrl)
                put("senderName", "${Build.MANUFACTURER} ${Build.MODEL}")
            }

            OutputStreamWriter(conn.outputStream).use { writer ->
                writer.write(json.toString())
                writer.flush()
            }

            val code = conn.responseCode
            conn.disconnect()
            code in 200..299
        } catch (e: Exception) {
            Log.e(tag, "Failed to send link: ${e.message}")
            false
        }
    }

    suspend fun streamFile(
        mac: DiscoveredMac,
        uri: Uri,
        angle: Float = 0f,
        velocity: Float = 1.5f,
        aimX: Float = 0f,
        onProgress: (Float) -> Unit = {}
    ): Boolean = withContext(Dispatchers.IO) {
        val target = "http://${mac.host}:${mac.port}/transfer"
        val fileName = getFileName(uri)
        val fileSize = getFileSize(uri)
        val mimeType = context.contentResolver.getType(uri) ?: "application/octet-stream"

        Log.d(tag, "🚀 Streaming '$fileName' ($fileSize bytes) to ${mac.name} ($target) [angle: $angle°, vel: $velocity, aimX: $aimX]")

        try {
            val url = URL(target)
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 60000
            conn.requestMethod = "POST"
            conn.doOutput = true
            if (fileSize > 0) {
                conn.setFixedLengthStreamingMode(fileSize)
                conn.setRequestProperty("Content-Length", fileSize.toString())
            } else {
                conn.setChunkedStreamingMode(65536)
            }

            val encodedName = URLEncoder.encode(fileName, "UTF-8")
            val senderDevice = "${Build.MANUFACTURER} ${Build.MODEL}"

            conn.setRequestProperty("Content-Type", mimeType)
            conn.setRequestProperty("X-File-Name", encodedName)
            conn.setRequestProperty("X-File-Size", fileSize.toString())
            conn.setRequestProperty("X-Mime-Type", mimeType)
            conn.setRequestProperty("X-Flick-Angle", angle.toString())
            conn.setRequestProperty("X-Flick-Velocity", velocity.toString())
            conn.setRequestProperty("X-Flick-Position-X", aimX.toString())
            conn.setRequestProperty("X-Sender-Name", senderDevice)

            context.contentResolver.openInputStream(uri)?.use { inputStream ->
                conn.outputStream.use { outputStream ->
                    val buffer = ByteArray(65536)
                    var bytesRead: Int
                    var totalWritten = 0L

                    while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                        totalWritten += bytesRead
                        if (fileSize > 0) {
                            onProgress(totalWritten.toFloat() / fileSize.toFloat())
                        }
                    }
                    outputStream.flush()
                }
            } ?: return@withContext false

            val code = conn.responseCode
            conn.disconnect()
            Log.d(tag, "Transfer completed with HTTP $code")
            code in 200..299
        } catch (e: Exception) {
            Log.e(tag, "Transfer error", e)
            false
        }
    }

    private fun getFileName(uri: Uri): String {
        var name = "received_${System.currentTimeMillis()}"
        if (uri.scheme == "content") {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex != -1 && cursor.moveToFirst()) {
                    val displayName = cursor.getString(nameIndex)
                    if (!displayName.isNullOrBlank()) {
                        name = displayName
                    }
                }
            }
        } else if (uri.scheme == "file") {
            uri.lastPathSegment?.let { name = it }
        }
        return name
    }

    private fun getFileSize(uri: Uri): Long {
        var size = -1L
        if (uri.scheme == "content") {
            context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex != -1 && cursor.moveToFirst()) {
                    size = cursor.getLong(sizeIndex)
                }
            }
        }
        return size
    }
}
