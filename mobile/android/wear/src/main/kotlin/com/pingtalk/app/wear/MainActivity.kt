package com.pingtalk.app.wear

import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject
import java.util.UUID

class MainActivity : AppCompatActivity(), MessageClient.OnMessageReceivedListener {
    private val pathCommand = "/pingtalk/command"
    private val pathPing = "/pingtalk/ping"
    private val pathState = "/pingtalk/state"
    private val pathLanguage = "/pingtalk/language"

    private var selectedSide: String = "HOME"
    private var scoreHome: Int = 0
    private var scoreAway: Int = 0
    private var version: Int = 0
    private var currentLocale: String = "ko"
    private var currentStatus: String = "disconnected" // 현재 상태 저장

    private lateinit var tvStatus: TextView
    private lateinit var tvScore: TextView
    private lateinit var layoutHomeAway: LinearLayout
    private lateinit var btnHome: Button
    private lateinit var btnAway: Button
    private lateinit var btnReset: Button
    private lateinit var btnUndo: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 시스템 UI를 완전히 숨기고 상단 여백 제거
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.hide(WindowInsetsCompat.Type.statusBars() or WindowInsetsCompat.Type.navigationBars())
        windowInsetsController.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        
        setContentView(R.layout.activity_main)

        tvStatus = findViewById(R.id.tvStatus)
        tvScore = findViewById(R.id.tvScore)
        layoutHomeAway = findViewById(R.id.layoutHomeAway)
        btnHome = findViewById(R.id.btnHome)
        btnAway = findViewById(R.id.btnAway)
        btnReset = findViewById(R.id.btnReset)
        btnUndo = findViewById(R.id.btnUndo)

        btnHome.setOnClickListener {
            selectedSide = "HOME"
            sendCommand("inc", "HOME")
            render()
        }
        btnAway.setOnClickListener {
            selectedSide = "AWAY"
            sendCommand("inc", "AWAY")
            render()
        }

        btnReset.setOnClickListener { showResetConfirmDialog() }
        btnUndo.setOnClickListener { sendCommand("undo", null) }

        // 초기 상태 메시지 설정
        currentStatus = "disconnected"
        tvStatus.text = getStatusText(currentStatus)
        render()
    }

    override fun onResume() {
        super.onResume()
        Wearable.getMessageClient(this).addListener(this)
        // 워치 앱 실행 시 폰에 ping 보내기(폰 UI에 "연결됨" 표시)
        sendToAllNodes(pathPing, ByteArray(0)) { ok ->
            runOnUiThread { 
                currentStatus = if (ok) "connected" else "disconnected"
                tvStatus.text = getStatusText(currentStatus)
                render() // 언어 설정 반영
            }
        }
    }

    override fun onPause() {
        Wearable.getMessageClient(this).removeListener(this)
        super.onPause()
    }

    override fun onMessageReceived(event: com.google.android.gms.wearable.MessageEvent) {
        when (event.path) {
            pathState -> {
                val payload = event.data?.toString(Charsets.UTF_8) ?: return
                val json = JSONObject(payload)

                // Flutter 쪽 MatchState JSON 형태를 그대로 수용(필요한 필드만 사용)
                scoreHome = json.optInt("scoreA", scoreHome)
                scoreAway = json.optInt("scoreB", scoreAway)
                version = json.optInt("version", version)

                runOnUiThread {
                    currentStatus = "synced"
                    tvStatus.text = getStatusText(currentStatus)
                    render()
                }
            }
            pathLanguage -> {
                val payload = event.data?.toString(Charsets.UTF_8) ?: return
                Log.d("PingTalk", "Received language message: $payload")
                val json = JSONObject(payload)
                val newLocale = json.optString("locale", "ko")
                Log.d("PingTalk", "New locale: $newLocale, current locale: $currentLocale")
                if (newLocale != currentLocale) {
                    currentLocale = newLocale
                    Log.d("PingTalk", "Updating locale to: $currentLocale")
                    runOnUiThread {
                        // 모든 UI 텍스트 업데이트 (현재 상태 유지)
                        tvStatus.text = getStatusText(currentStatus)
                        render()
                        Log.d("PingTalk", "UI updated with locale: $currentLocale")
                    }
                } else {
                    Log.d("PingTalk", "Locale unchanged, skipping update")
                }
            }
        }
    }
    
    private fun getStatusText(status: String): String {
        return when (status) {
            "connected" -> "Phone: Connected"
            "disconnected" -> "Phone: Disconnected"
            "synced" -> "Phone: Synced"
            "sent" -> "Phone: Sent"
            "sendFailed" -> "Phone: Send Failed"
            else -> "Phone: Disconnected"
        }
    }
    
    private fun getResetDialogTexts(): Triple<String, String, String> {
        return Triple("Reset", "All scores, set scores,\nand undo history will be deleted.\nAre you sure you want to reset?", "Reset")
    }

    private fun render() {
        tvScore.text = "$scoreHome : $scoreAway"
        
        // 버튼 텍스트 다국어 설정
        val (homeText, awayText, resetText, undoText) = getButtonTexts()
        btnHome.text = homeText
        btnAway.text = awayText
        btnReset.text = resetText
        btnUndo.text = undoText
        
        // 버튼은 항상 활성화 상태로 유지 (토글 가능하게)
        val isHomeSelected = selectedSide == "HOME"
        btnHome.isEnabled = true
        btnAway.isEnabled = true
        
        // 모바일 앱과 동일한 색상 사용
        // homeAccent = 0xFF3DDCFF (청록-하늘색), awayAccent = 0xFFFFC14D (노란색)
        val homeAccentColor = Color.rgb(61, 220, 255) // 0xFF3DDCFF
        val awayAccentColor = Color.rgb(255, 193, 77) // 0xFFFFC14D
        val unselectedBgColor = Color.argb(80, 150, 150, 150) // 약간 밝은 회색 배경
        val unselectedTextColor = Color.argb(180, 255, 255, 255) // 약간 투명한 흰색 텍스트
        
        // 선택된 쪽과 비선택된 쪽을 배경색과 텍스트 색상으로 구분
        if (isHomeSelected) {
            // HOME 선택됨: HOME은 accent 색상 배경, AWAY는 어두운 배경
            btnHome.setBackgroundColor(homeAccentColor)
            btnHome.setTextColor(Color.BLACK)
            btnHome.alpha = 1.0f
            
            btnAway.setBackgroundColor(unselectedBgColor)
            btnAway.setTextColor(unselectedTextColor)
            btnAway.alpha = 1.0f
        } else {
            // AWAY 선택됨: AWAY는 accent 색상 배경, HOME은 어두운 배경
            btnHome.setBackgroundColor(unselectedBgColor)
            btnHome.setTextColor(unselectedTextColor)
            btnHome.alpha = 1.0f
            
            btnAway.setBackgroundColor(awayAccentColor)
            btnAway.setTextColor(Color.BLACK)
            btnAway.alpha = 1.0f
        }
        
        // RESET 버튼: 빨간색 계열 (위험한 작업)
        btnReset.setBackgroundColor(Color.rgb(220, 80, 80)) // 빨간색
        btnReset.setTextColor(Color.WHITE)
        btnReset.alpha = 1.0f
        
        // UNDO 버튼: 파란색 계열 (되돌리기 작업)
        btnUndo.setBackgroundColor(Color.rgb(100, 150, 255)) // 파란색
        btnUndo.setTextColor(Color.WHITE)
        btnUndo.alpha = 1.0f
    }
    
    private fun getButtonTexts(): Quadruple<String, String, String, String> {
        return Quadruple("HOME", "AWAY", "RESET", "UNDO")
    }
    
    private data class Quadruple<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)

    private fun showResetConfirmDialog() {
        val (title, message, confirmText) = getResetDialogTexts()
        val cancelText = "Cancel"
        
        val dialog = AlertDialog.Builder(this)
            .setTitle(title)
            .setMessage(message)
            .setPositiveButton(confirmText) { _, _ ->
                sendCommand("reset", null)
            }
            .setNegativeButton(cancelText, null)
            .create()
        
        dialog.setOnShowListener {
            // 다이얼로그 배경을 어두운 색으로
            val bgColor = Color.rgb(11, 18, 32) // 0xFF0B1220
            dialog.window?.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(bgColor))
            
            // 제목 TextView 찾기 - 재귀적으로 모든 TextView 검색
            fun findTitleView(view: android.view.View?): TextView? {
                if (view == null) return null
                if (view is TextView && view.text == "Reset") {
                    return view
                }
                if (view is android.view.ViewGroup) {
                    for (i in 0 until view.childCount) {
                        val found = findTitleView(view.getChildAt(i))
                        if (found != null) return found
                    }
                }
                return null
            }
            
            val titleView = dialog.findViewById<TextView>(android.R.id.title) 
                ?: findTitleView(dialog.window?.decorView)
            
            titleView?.let {
                it.setTextColor(Color.WHITE)
                it.gravity = android.view.Gravity.CENTER
                it.setTypeface(null, android.graphics.Typeface.BOLD)
                it.textAlignment = android.view.View.TEXT_ALIGNMENT_CENTER
                // 부모 레이아웃의 중앙정렬도 설정 (LinearLayout인 경우)
                val parent = it.parent as? LinearLayout
                parent?.gravity = android.view.Gravity.CENTER
            }
            
            // 메시지 텍스트 색상 및 중앙정렬
            val messageView = dialog.findViewById<TextView>(android.R.id.message)
            if (messageView != null) {
                messageView.setTextColor(Color.argb(230, 255, 255, 255))
                messageView.gravity = android.view.Gravity.CENTER
                messageView.textAlignment = android.view.View.TEXT_ALIGNMENT_CENTER
            }
            
            // 버튼 색상 설정
            val positiveButton = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
            positiveButton?.setBackgroundColor(Color.rgb(220, 80, 80)) // 빨간색
            positiveButton?.setTextColor(Color.WHITE)
            
            val negativeButton = dialog.getButton(AlertDialog.BUTTON_NEGATIVE)
            negativeButton?.setBackgroundColor(Color.argb(80, 150, 150, 150)) // 회색
            negativeButton?.setTextColor(Color.argb(180, 255, 255, 255))
        }
        
        dialog.show()
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
            runOnUiThread { 
                currentStatus = if (ok) "sent" else "sendFailed"
                tvStatus.text = getStatusText(currentStatus)
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
}

