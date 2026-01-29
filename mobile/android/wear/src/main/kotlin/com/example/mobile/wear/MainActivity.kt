package com.example.mobile.wear

import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject
import java.util.UUID

class MainActivity : AppCompatActivity(), MessageClient.OnMessageReceivedListener {
    private val pathCommand = "/pingtalk/command"
    private val pathPing = "/pingtalk/ping"
    private val pathState = "/pingtalk/state"

    private var selectedSide: String = "HOME"
    private var scoreHome: Int = 0
    private var scoreAway: Int = 0
    private var version: Int = 0

    private lateinit var tvStatus: TextView
    private lateinit var tvScore: TextView
    private lateinit var btnHome: Button
    private lateinit var btnAway: Button
    private lateinit var btnInc: Button
    private lateinit var btnDec: Button
    private lateinit var btnReset: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        tvStatus = findViewById(R.id.tvStatus)
        tvScore = findViewById(R.id.tvScore)
        btnHome = findViewById(R.id.btnHome)
        btnAway = findViewById(R.id.btnAway)
        btnInc = findViewById(R.id.btnInc)
        btnDec = findViewById(R.id.btnDec)
        btnReset = findViewById(R.id.btnReset)

        btnHome.setOnClickListener {
            selectedSide = "HOME"
            render()
        }
        btnAway.setOnClickListener {
            selectedSide = "AWAY"
            render()
        }

        btnInc.setOnClickListener { sendCommand("inc", selectedSide) }
        btnDec.setOnClickListener { sendCommand("dec", selectedSide) }
        btnReset.setOnClickListener { sendCommand("reset", null) }

        render()
    }

    override fun onResume() {
        super.onResume()
        Wearable.getMessageClient(this).addListener(this)
        // 워치 앱 실행 시 폰에 ping 보내기(폰 UI에 "연결됨" 표시)
        sendToAllNodes(pathPing, ByteArray(0)) { ok ->
            runOnUiThread { tvStatus.text = if (ok) "폰: 연결됨" else "폰: 미연결" }
        }
    }

    override fun onPause() {
        Wearable.getMessageClient(this).removeListener(this)
        super.onPause()
    }

    override fun onMessageReceived(event: com.google.android.gms.wearable.MessageEvent) {
        if (event.path != pathState) return
        val payload = event.data?.toString(Charsets.UTF_8) ?: return
        val json = JSONObject(payload)

        // Flutter 쪽 MatchState JSON 형태를 그대로 수용(필요한 필드만 사용)
        scoreHome = json.optInt("scoreA", scoreHome)
        scoreAway = json.optInt("scoreB", scoreAway)
        version = json.optInt("version", version)

        runOnUiThread {
            tvStatus.text = "폰: 동기화됨(v$version)"
            render()
        }
    }

    private fun render() {
        tvScore.text = "$scoreHome : $scoreAway"
        btnHome.isEnabled = selectedSide != "HOME"
        btnAway.isEnabled = selectedSide != "AWAY"
    }

    private fun sendCommand(type: String, side: String?) {
        val cmd = JSONObject()
        cmd.put("id", "cmd_${UUID.randomUUID()}")
        cmd.put("matchId", "local")
        cmd.put("type", type)
        if (side != null) cmd.put("side", side)
        cmd.put("issuedAt", java.time.Instant.now().toString())
        cmd.put("issuedBy", "watch")
        cmd.put("deviceId", "wearos")

        sendToAllNodes(pathCommand, cmd.toString().toByteArray(Charsets.UTF_8)) { ok ->
            runOnUiThread { tvStatus.text = if (ok) "폰: 전송됨" else "폰: 전송 실패" }
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
}

