package cn.gduthelper.gdut_network_helper

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.Executors

/** Every portal request uses a currently connected Wi-Fi, never the cellular default. */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val maxBytes = 512 * 1024

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gdut_helper/wifi_http")
            .setMethodCallHandler { call, result ->
                if (call.method != "request") {
                    result.notImplemented()
                } else {
                    executor.execute {
                        try {
                            val response = request(call)
                            mainHandler.post { result.success(response) }
                        } catch (_: Exception) {
                            // Never expose exception messages: they may contain a credential-bearing URL.
                            mainHandler.post {
                                result.error("WIFI_HTTP_FAILED", "校园 Wi-Fi 请求失败，请确认已连接校园网。", null)
                            }
                        }
                    }
                }
            }
    }

    private fun request(call: MethodCall): Map<String, Any?> {
        val rawUrl = requireNotNull(call.argument<String>("url"))
        require(rawUrl.length <= 16384)
        val uri = URI(rawUrl)
        require(uri.scheme == "http" && uri.host == "10.0.3.2")
        require(uri.port == -1 || uri.port == 80 || uri.port == 801)
        require(uri.rawUserInfo == null && uri.fragment == null)
        val method = call.argument<String>("method") ?: "GET"
        require(method == "GET" || method == "POST")
        val body = (call.argument<String>("body") ?: "").toByteArray(Charsets.UTF_8)
        require(body.size <= maxBytes && (method == "POST" || body.isEmpty()))
        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
        require(headers.size <= 20)
        headers.forEach { (name, value) ->
            require(name.matches(Regex("[A-Za-z0-9-]+")) && value.length <= 8192)
            require(!value.contains('\r') && !value.contains('\n'))
            require(name.lowercase() !in setOf("host", "connection", "content-length", "transfer-encoding"))
        }
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val wifi = manager.allNetworks.firstOrNull { network ->
            manager.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        } ?: error("No Wi-Fi")
        val connection = wifi.openConnection(uri.toURL()) as HttpURLConnection
        try {
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 8000
            connection.readTimeout = 8000
            connection.useCaches = false
            connection.requestMethod = method
            headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            if (method == "POST") {
                connection.doOutput = true
                connection.setFixedLengthStreamingMode(body.size)
                connection.outputStream.use { it.write(body) }
            }
            val status = connection.responseCode
            val responseBody = ByteArrayOutputStream()
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            stream?.use { input ->
                val chunk = ByteArray(8192)
                while (true) {
                    val count = input.read(chunk)
                    if (count < 0) break
                    require(responseBody.size() + count <= maxBytes)
                    responseBody.write(chunk, 0, count)
                }
            }
            return mapOf(
                "statusCode" to status,
                "body" to responseBody.toString("UTF-8"),
                "location" to connection.getHeaderField("Location")
            )
        } finally {
            connection.disconnect()
        }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }
}
