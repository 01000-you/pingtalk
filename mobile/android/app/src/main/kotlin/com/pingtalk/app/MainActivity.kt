package com.pingtalk.app

import android.os.Bundle
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity(), MessageClient.OnMessageReceivedListener {
    private val channelName = "pingtalk/watch"
    private lateinit var channel: MethodChannel

    private val pathCommand = "/pingtalk/command"
    private val pathPing = "/pingtalk/ping"
    private val pathState = "/pingtalk/state"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Flutter -> Native: 현재 state를 워치로 푸시
                "state" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = call.arguments as? Map<String, Any?>
                    if (map == null) {
                        result.error("bad_args", "state expects Map<String, Any?>", null)
                        return@setMethodCallHandler
                    }

                    val json = JSONObject(map).toString()
                    sendToAllNodes(pathState, json.toByteArray(Charsets.UTF_8)) { ok ->
                        if (ok) result.success(true) else result.error("send_failed", "failed to send state", null)
                    }
                }
                
                // Flutter -> Native: 언어 변경을 워치로 전달
                "setLanguage" -> {
                    @Suppress("UNCHECKED_CAST")
                    val map = call.arguments as? Map<String, Any?>
                    val locale = map?.get("locale") as? String
                    if (locale == null) {
                        result.error("bad_args", "setLanguage expects Map with 'locale' key", null)
                        return@setMethodCallHandler
                    }
                    
                    val json = JSONObject().apply {
                        put("locale", locale)
                    }
                    sendToAllNodes("/pingtalk/language", json.toString().toByteArray(Charsets.UTF_8)) { ok ->
                        if (ok) result.success(true) else result.error("send_failed", "failed to send language", null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 즉시 연결 확인을 위해 워치에 ping을 보내는 대신,
        // 워치가 앱 실행 시 ping을 보내도록(워치->폰) 두는 편이 단순합니다.
    }

    override fun onResume() {
        super.onResume()
        Wearable.getMessageClient(this).addListener(this)
    }

    override fun onPause() {
        Wearable.getMessageClient(this).removeListener(this)
        super.onPause()
    }

    override fun onMessageReceived(event: com.google.android.gms.wearable.MessageEvent) {
        when (event.path) {
            pathPing -> {
                runOnUiThread { channel.invokeMethod("ping", null) }
            }

            pathCommand -> {
                val payload = event.data?.toString(Charsets.UTF_8) ?: return
                val json = JSONObject(payload)
                val map = jsonToMap(json)
                runOnUiThread { channel.invokeMethod("command", map) }
            }
        }
    }

    private fun sendToAllNodes(path: String, data: ByteArray, done: (Boolean) -> Unit) {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    done(false)
                    return@addOnSuccessListener
                }

                var remaining = nodes.size
                var anySuccess = false

                for (node in nodes) {
                    Wearable.getMessageClient(this)
                        .sendMessage(node.id, path, data)
                        .addOnSuccessListener {
                            anySuccess = true
                            remaining -= 1
                            if (remaining == 0) done(anySuccess)
                        }
                        .addOnFailureListener {
                            remaining -= 1
                            if (remaining == 0) done(anySuccess)
                        }
                }
            }
            .addOnFailureListener {
                done(false)
            }
    }

    private fun jsonToMap(obj: JSONObject): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        val keys = obj.keys()
        while (keys.hasNext()) {
            val k = keys.next()
            val v = obj.get(k)
            out[k] = jsonValue(v)
        }
        return out
    }

    private fun jsonValue(v: Any?): Any? = when (v) {
        null -> null
        JSONObject.NULL -> null
        is JSONObject -> jsonToMap(v)
        is JSONArray -> (0 until v.length()).map { idx -> jsonValue(v.get(idx)) }
        else -> v
    }
}
