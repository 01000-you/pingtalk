package com.pingtalk.app.wear

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

class MainActivity : AppCompatActivity(), MessageClient.OnMessageReceivedListener {
    companion object {
        private const val REQUEST_CODE_SPEECH = 1000
    }
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
    private lateinit var btnVoice: Button

    private var speechRecognizer: SpeechRecognizer? = null
    private var isListening: Boolean = false
    private var wasListeningBeforePause: Boolean = false // 백그라운드 가기 전 리스닝 상태 저장
    private val RECORD_AUDIO_PERMISSION_CODE = 100
    private var lastRecognitionTime: Long = 0 // 마지막 인식 시간 추적
    private var restartCheckHandler: android.os.Handler? = null
    private val RESTART_CHECK_INTERVAL = 10000L // 10초마다 체크

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
        btnVoice = findViewById(R.id.btnVoice)

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
        btnVoice.setOnClickListener {
            if (isListening) {
                // 이미 리스닝 중이면 종료
                stopVoiceRecognition()
            } else {
                // 리스닝 중이 아니면 시작
                startVoiceRecognition()
            }
        }

        // 음성인식 초기화
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) 
            == PackageManager.PERMISSION_GRANTED) {
            initializeSpeechRecognizer()
        }

        // 초기 상태 메시지 설정
        currentStatus = "disconnected"
        tvStatus.text = getStatusText(currentStatus)
        render()
    }
    
    private fun initializeSpeechRecognizer() {
        try {
            Log.d("PingTalk", "Attempting to create SpeechRecognizer (default, no ComponentName)...")
            
            // 기본 SpeechRecognizer 사용 (ComponentName 없이)
            // 시스템이 자동으로 사용 가능한 음성인식 서비스를 선택
            if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                Log.e("PingTalk", "Speech recognition not available on this device")
                Toast.makeText(this, "Speech recognition not available on this device", Toast.LENGTH_LONG).show()
                return
            }
            
            Log.d("PingTalk", "Speech recognition is available, creating default SpeechRecognizer...")
            speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
            
            if (speechRecognizer == null) {
                Log.e("PingTalk", "SpeechRecognizer.createSpeechRecognizer returned null")
                Toast.makeText(this, "Failed to initialize speech recognizer", Toast.LENGTH_SHORT).show()
                return
            }
            
            Log.d("PingTalk", "SpeechRecognizer created successfully (default)")
            
            Log.d("PingTalk", "SpeechRecognizer created successfully")
            speechRecognizer?.setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    Log.d("PingTalk", "Ready for speech")
                    runOnUiThread {
                        isListening = true
                        updateVoiceButton()
                    }
                }

                override fun onBeginningOfSpeech() {
                    Log.d("PingTalk", "Beginning of speech")
                    runOnUiThread {
                        btnVoice.text = "LISTENING..."
                        btnVoice.setBackgroundColor(Color.rgb(255, 200, 0)) // 주황색
                    }
                }

                override fun onRmsChanged(rmsdB: Float) {}

                override fun onBufferReceived(buffer: ByteArray?) {}

                override fun onEndOfSpeech() {
                    Log.d("PingTalk", "End of speech")
                    runOnUiThread {
                        btnVoice.text = "PROCESSING..."
                        btnVoice.setBackgroundColor(Color.rgb(200, 150, 255)) // 연한 보라색
                    }
                    // onEndOfSpeech 후에도 onResults가 호출되므로 자동으로 계속 리스닝됨
                }

                override fun onError(error: Int) {
                    val errorMessage = when (error) {
                        SpeechRecognizer.ERROR_AUDIO -> "Audio error"
                        SpeechRecognizer.ERROR_CLIENT -> "Client error"
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Insufficient permissions"
                        SpeechRecognizer.ERROR_NETWORK -> "Network error"
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
                        SpeechRecognizer.ERROR_NO_MATCH -> "No match found"
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
                        SpeechRecognizer.ERROR_SERVER -> "Server error"
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Speech timeout"
                        10 -> "Speech service unavailable. Please check Google app or try again."
                        else -> "Unknown error: $error"
                    }
                    Log.e("PingTalk", "Speech recognition error: $errorMessage ($error)")
                    Log.e("PingTalk", "Error details - code: $error, isListening: $isListening, recognizer: ${speechRecognizer != null}")
                    
                    runOnUiThread {
                        // NO_MATCH나 SPEECH_TIMEOUT 같은 경우는 계속 리스닝
                        val shouldContinueListening = error == SpeechRecognizer.ERROR_NO_MATCH || 
                                                      error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                        
                        // ERROR_RECOGNIZER_BUSY는 잠시 후 재시도
                        val isBusyError = error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY
                        
                        if (!shouldContinueListening && !isBusyError) {
                            // 심각한 에러인 경우에만 종료
                            isListening = false
                            updateVoiceButton()
                            Toast.makeText(this@MainActivity, errorMessage, Toast.LENGTH_SHORT).show()
                            
                            // 권한 에러인 경우 권한 요청
                            if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                                requestAudioPermission()
                            }
                            
                            // ERROR 10인 경우 SpeechRecognizer 재초기화 시도
                            if (error == 10) {
                                Log.d("PingTalk", "Attempting to reinitialize SpeechRecognizer after error 10")
                                speechRecognizer?.destroy()
                                speechRecognizer = null
                                // 재초기화 시도
                                try {
                                    initializeSpeechRecognizer()
                                    if (speechRecognizer != null && isListening) {
                                        // 재초기화 성공 시 다시 시작
                                        startVoiceRecognition()
                                    }
                                } catch (e: Exception) {
                                    Log.e("PingTalk", "Failed to reinitialize SpeechRecognizer: ${e.message}", e)
                                    isListening = false
                                    updateVoiceButton()
                                }
                            }
                        } else if (isBusyError) {
                            // BUSY 에러는 잠시 후 재시도 (너무 빠르게 재시도하지 않음)
                            Log.w("PingTalk", "Recognizer busy, will retry after delay")
                            btnVoice.postDelayed({
                                if (isListening && speechRecognizer != null) {
                                    try {
                                        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                                        }
                                        speechRecognizer?.startListening(intent)
                                        Log.d("PingTalk", "Retried listening after busy error")
                                    } catch (e: Exception) {
                                        Log.e("PingTalk", "Error retrying after busy: ${e.message}", e)
                                        isListening = false
                                        updateVoiceButton()
                                    }
                                }
                            }, 500) // 0.5초 후 재시도
                        } else {
                            // 계속 리스닝하도록 다시 시작 (NO_MATCH, SPEECH_TIMEOUT)
                            if (isListening && speechRecognizer != null) {
                                try {
                                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                                    }
                                    speechRecognizer?.startListening(intent)
                                    Log.d("PingTalk", "Restarted listening after error: $errorMessage")
                                } catch (e: Exception) {
                                    Log.e("PingTalk", "Error restarting listening: ${e.message}", e)
                                    isListening = false
                                    updateVoiceButton()
                                }
                            }
                        }
                    }
                }

                override fun onResults(results: Bundle?) {
                    // 결과 처리 후에도 계속 리스닝하도록 자동 종료하지 않음
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val confidence = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
                    
                    Log.d("PingTalk", "=== Voice Recognition Results ===")
                    if (matches != null && matches.isNotEmpty()) {
                        Log.d("PingTalk", "Total matches: ${matches.size}")
                        matches.forEachIndexed { index, text ->
                            val conf = if (confidence != null && index < confidence.size) {
                                confidence[index]
                            } else {
                                null
                            }
                            Log.d("PingTalk", "Match[$index]: \"$text\" (confidence: $conf)")
                        }
                        
                        val recognizedText = matches[0].lowercase(Locale.getDefault())
                        Log.d("PingTalk", "Selected text: \"$recognizedText\"")
                        
                        when {
                            recognizedText.contains("블루") || recognizedText.contains("blue") -> {
                                Log.d("PingTalk", "Action: HOME score increment")
                                // 진동 발생
                                vibrate()
                                // HOME 점수 증가
                                selectedSide = "HOME"
                                sendCommand("inc", "HOME")
                                render()
                                Toast.makeText(this@MainActivity, "Blue +1", Toast.LENGTH_SHORT).show()
                            }
                            recognizedText.contains("레드") || recognizedText.contains("red") -> {
                                Log.d("PingTalk", "Action: AWAY score increment")
                                // 진동 발생
                                vibrate()
                                // AWAY 점수 증가
                                selectedSide = "AWAY"
                                sendCommand("inc", "AWAY")
                                render()
                                Toast.makeText(this@MainActivity, "Red +1", Toast.LENGTH_SHORT).show()
                            }
                            else -> {
                                Log.d("PingTalk", "No matching command found for: \"$recognizedText\"")
                            }
                        }
                    } else {
                        Log.d("PingTalk", "No recognition results")
                    }
                    Log.d("PingTalk", "=== End Recognition Results ===")
                    
                    // 마지막 인식 시간 업데이트
                    lastRecognitionTime = System.currentTimeMillis()
                    
                    // 계속 리스닝하도록 다시 시작 (isListening이 true인 경우에만)
                    runOnUiThread {
                        if (isListening && speechRecognizer != null) {
                            try {
                                // 잠시 대기 후 재시작 (너무 빠르게 재시작하면 BUSY 에러 발생 가능)
                                btnVoice.postDelayed({
                                    if (isListening && speechRecognizer != null) {
                                        try {
                                            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                                            }
                                            speechRecognizer?.startListening(intent)
                                            Log.d("PingTalk", "Restarted listening after results")
                                            lastRecognitionTime = System.currentTimeMillis() // 재시작 시간도 업데이트
                                        } catch (e: Exception) {
                                            Log.e("PingTalk", "Error restarting listening after delay: ${e.message}", e)
                                            isListening = false
                                            updateVoiceButton()
                                        }
                                    } else {
                                        Log.w("PingTalk", "Cannot restart: isListening=$isListening, recognizer=${speechRecognizer != null}")
                                    }
                                }, 300) // 0.3초 후 재시작
                            } catch (e: Exception) {
                                Log.e("PingTalk", "Error scheduling restart: ${e.message}", e)
                                isListening = false
                                updateVoiceButton()
                            }
                        } else {
                            Log.w("PingTalk", "Not restarting after results: isListening=$isListening, recognizer=${speechRecognizer != null}")
                        }
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    if (matches != null && matches.isNotEmpty()) {
                        Log.d("PingTalk", "Partial result: ${matches[0]}")
                    }
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
            Log.d("PingTalk", "Speech recognizer initialized")
        } catch (e: Exception) {
            Log.e("PingTalk", "Failed to create speech recognizer: ${e.message}", e)
            speechRecognizer = null
        }
    }
    
    private fun startVoiceRecognition() {
        if (isListening) {
            // 이미 듣고 있으면 중지
            stopVoiceRecognition()
            return
        }
        
        // 권한 확인
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) 
            != PackageManager.PERMISSION_GRANTED) {
            Log.e("PingTalk", "Audio permission not granted")
            requestAudioPermission()
            Toast.makeText(this, "Audio permission required", Toast.LENGTH_SHORT).show()
            return
        }
        
        // SpeechRecognizer 초기화 확인
        if (speechRecognizer == null) {
            Log.d("PingTalk", "Initializing speech recognizer")
            initializeSpeechRecognizer()
            if (speechRecognizer == null) {
                Log.e("PingTalk", "Failed to initialize speech recognizer")
                Toast.makeText(this, "Speech recognition not available on this device", Toast.LENGTH_LONG).show()
                isListening = false
                updateVoiceButton()
                return
            }
        }
        
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
        }
        
        try {
            Log.d("PingTalk", "Starting voice recognition with intent: $intent")
            Log.d("PingTalk", "SpeechRecognizer state: ${if (speechRecognizer == null) "null" else "initialized"}")
            
            if (speechRecognizer == null) {
                Log.e("PingTalk", "SpeechRecognizer is null, attempting reinitialization")
                initializeSpeechRecognizer()
                if (speechRecognizer == null) {
                    Log.e("PingTalk", "SpeechRecognizer is still null after reinitialization")
                    Toast.makeText(this, "Speech recognizer not available", Toast.LENGTH_SHORT).show()
                    isListening = false
                    updateVoiceButton()
                    return
                }
            }
            
            speechRecognizer?.startListening(intent)
            isListening = true
            lastRecognitionTime = System.currentTimeMillis()
            updateVoiceButton()
            Toast.makeText(this, "Listening... Say 'Blue' or 'Red' (Press again to stop)", Toast.LENGTH_SHORT).show()
            Log.d("PingTalk", "Voice recognition started successfully, will continue until button is pressed again")
            
            // 주기적으로 체크하여 응답이 없으면 재시작
            startRestartCheck()
        } catch (e: Exception) {
            Log.e("PingTalk", "Error starting voice recognition: ${e.message}", e)
            e.printStackTrace()
            Toast.makeText(this, "Error: ${e.message}", Toast.LENGTH_LONG).show()
            isListening = false
            updateVoiceButton()
        }
    }
    
    private fun updateVoiceButton() {
        if (isListening) {
            btnVoice.text = "LISTENING..."
            btnVoice.setBackgroundColor(Color.rgb(255, 200, 0)) // 주황색
        } else {
            btnVoice.text = "VOICE"
            btnVoice.setBackgroundColor(Color.rgb(150, 100, 255)) // 보라색
        }
    }
    
    private fun stopVoiceRecognition() {
        speechRecognizer?.stopListening()
        isListening = false
        stopRestartCheck()
        updateVoiceButton()
    }
    
    private fun startRestartCheck() {
        stopRestartCheck()
        restartCheckHandler = android.os.Handler(android.os.Looper.getMainLooper())
        restartCheckHandler?.postDelayed(object : Runnable {
            override fun run() {
                if (isListening) {
                    val timeSinceLastRecognition = System.currentTimeMillis() - lastRecognitionTime
                    if (timeSinceLastRecognition > 15000) { // 15초 이상 응답이 없으면
                        Log.w("PingTalk", "No recognition response for ${timeSinceLastRecognition}ms, attempting restart")
                        if (speechRecognizer != null) {
                            try {
                                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
                                }
                                speechRecognizer?.startListening(intent)
                                lastRecognitionTime = System.currentTimeMillis()
                                Log.d("PingTalk", "Restarted listening due to timeout")
                            } catch (e: Exception) {
                                Log.e("PingTalk", "Error restarting after timeout: ${e.message}", e)
                                isListening = false
                                updateVoiceButton()
                            }
                        } else {
                            Log.w("PingTalk", "SpeechRecognizer is null, reinitializing")
                            initializeSpeechRecognizer()
                            if (speechRecognizer != null && isListening) {
                                startVoiceRecognition()
                            } else {
                                isListening = false
                                updateVoiceButton()
                            }
                        }
                    }
                    restartCheckHandler?.postDelayed(this, RESTART_CHECK_INTERVAL)
                }
            }
        }, RESTART_CHECK_INTERVAL)
    }
    
    private fun stopRestartCheck() {
        restartCheckHandler?.removeCallbacksAndMessages(null)
        restartCheckHandler = null
    }
    
    private fun requestAudioPermission() {
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            RECORD_AUDIO_PERMISSION_CODE
        )
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == RECORD_AUDIO_PERMISSION_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                initializeSpeechRecognizer()
                Toast.makeText(this, "Permission granted. Try voice again.", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(this, "Audio permission denied", Toast.LENGTH_SHORT).show()
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        speechRecognizer?.destroy()
    }

    override fun onResume() {
        super.onResume()
        Wearable.getMessageClient(this).addListener(this)
        
        // SpeechRecognizer가 null이면 재초기화 (권한이 있는 경우)
        if (speechRecognizer == null && 
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) 
            == PackageManager.PERMISSION_GRANTED) {
            Log.d("PingTalk", "App resumed, reinitializing speech recognizer")
            initializeSpeechRecognizer()
        }
        
        // 이전에 리스닝 중이었으면 다시 시작
        if (wasListeningBeforePause) {
            Log.d("PingTalk", "App resumed, restoring voice recognition state")
            wasListeningBeforePause = false
            // 잠시 후 재시작 (UI가 준비될 시간 확보)
            btnVoice.postDelayed({
                if (speechRecognizer != null) {
                    startVoiceRecognition()
                } else {
                    Log.w("PingTalk", "Cannot restore voice recognition: SpeechRecognizer is null")
                    isListening = false
                    updateVoiceButton()
                }
            }, 300)
        } else {
            // 이전에 리스닝 중이 아니었으면 상태 정리
            isListening = false
            updateVoiceButton()
        }
        
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
        // 백그라운드로 갈 때 음성인식 정리 (상태는 저장)
        if (isListening) {
            Log.d("PingTalk", "App paused, stopping voice recognition but preserving state")
            wasListeningBeforePause = true
            speechRecognizer?.stopListening()
            stopRestartCheck()
            // isListening은 true로 유지 (onResume에서 복원할 때 사용)
        } else {
            wasListeningBeforePause = false
        }
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
        
        // VOICE 버튼: 상태에 따라 색상 변경
        updateVoiceButton()
        btnVoice.setTextColor(Color.WHITE)
        btnVoice.alpha = 1.0f
    }
    
    private fun getButtonTexts(): Quadruple<String, String, String, String> {
        return Quadruple("BLUE", "RED", "RESET", "UNDO")
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
    
    private fun vibrate() {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // API 26 이상: VibrationEffect 사용
                val vibrationEffect = VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE)
                vibrator.vibrate(vibrationEffect)
            } else {
                // API 26 미만: 직접 vibrate 사용
                @Suppress("DEPRECATION")
                vibrator.vibrate(200)
            }
            Log.d("PingTalk", "Vibration triggered")
        } catch (e: Exception) {
            Log.e("PingTalk", "Error vibrating: ${e.message}", e)
        }
    }
}

