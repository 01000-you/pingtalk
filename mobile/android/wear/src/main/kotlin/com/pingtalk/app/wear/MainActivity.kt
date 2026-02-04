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
import android.content.SharedPreferences

class MainActivity : AppCompatActivity(), MessageClient.OnMessageReceivedListener {
    companion object {
        private const val REQUEST_CODE_SPEECH = 1000
        private const val PREFS_NAME = "PingTalkPrefs"
        private const val KEY_WAS_LISTENING = "was_listening"
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
    private lateinit var btnAlwaysOn: Button

    private var isAlwaysOn: Boolean = false // Always On 상태 (기본값: false)
    private var speechRecognizer: SpeechRecognizer? = null
    private var isListening: Boolean = false
    private var wasListeningBeforePause: Boolean = false // 백그라운드 가기 전 리스닝 상태 저장
    private val RECORD_AUDIO_PERMISSION_CODE = 100
    private var lastRecognitionTime: Long = 0 // 마지막 인식 시간 추적
    private var lastRestartAttemptTime: Long = 0 // 마지막 재시작 시도 시간
    private var consecutiveRestartFailures: Int = 0 // 연속 재시작 실패 횟수
    private var restartCheckHandler: android.os.Handler? = null
    private var isRetrying: Boolean = false // 재시도 중인지 플래그 (중복 재시도 방지)
    private var consecutiveBusyErrors: Int = 0 // 연속 BUSY 에러 횟수
    private var consecutiveClientErrors: Int = 0 // 연속 CLIENT 에러 횟수
    private var lastBusyErrorTime: Long = 0 // 마지막 BUSY 에러 발생 시간
    private var lastClientErrorTime: Long = 0 // 마지막 CLIENT 에러 발생 시간
    private var lastRetryTime: Long = 0 // 마지막 재시도 시간
    private val RESTART_CHECK_INTERVAL = 10000L // 10초마다 체크
    private val MAX_CONSECUTIVE_FAILURES = 3 // 최대 연속 실패 횟수
    private val MAX_CONSECUTIVE_BUSY_ERRORS = 5 // 최대 연속 BUSY 에러 횟수
    private val MAX_CONSECUTIVE_CLIENT_ERRORS = 5 // 최대 연속 CLIENT 에러 횟수
    private val BUSY_ERROR_RESET_INTERVAL = 3000L // BUSY 에러 카운터 리셋 간격 (3초)
    private val CLIENT_ERROR_RESET_INTERVAL = 3000L // CLIENT 에러 카운터 리셋 간격 (3초)
    private val MIN_RETRY_INTERVAL = 2000L // 최소 재시도 간격 (2초)
    private val MAX_RETRY_INTERVAL = 5000L // 최대 재시도 간격 (5초)

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
        btnAlwaysOn = findViewById(R.id.btnAlwaysOn)
        
        // Always On 초기 설정 (기본값: true)
        updateAlwaysOnState()

        btnHome.setOnClickListener {
            // 진동 발생
            vibrate()
            selectedSide = "HOME"
            sendCommand("inc", "HOME")
            render()
        }
        btnAway.setOnClickListener {
            // 진동 발생
            vibrate()
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
        
        btnAlwaysOn.setOnClickListener {
            isAlwaysOn = !isAlwaysOn
            updateAlwaysOnState()
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
                        11 -> "Speech recognition service error (11). Reinitializing..."
                        else -> "Unknown error: $error"
                    }
                    
                    // NO_MATCH와 SPEECH_TIMEOUT는 정상적인 상황 (인식할 말이 없거나 타임아웃)
                    val isNormalStatus = error == SpeechRecognizer.ERROR_NO_MATCH || 
                                        error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                    
                    if (isNormalStatus) {
                        Log.d("PingTalk", "Speech recognition status: $errorMessage ($error) - continuing to listen")
                    } else {
                        Log.e("PingTalk", "Speech recognition error: $errorMessage ($error)")
                        Log.e("PingTalk", "Error details - code: $error, isListening: $isListening, recognizer: ${speechRecognizer != null}")
                    }
                    
                    runOnUiThread {
                        // NO_MATCH나 SPEECH_TIMEOUT 같은 경우는 계속 리스닝
                        val shouldContinueListening = error == SpeechRecognizer.ERROR_NO_MATCH || 
                                                      error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                        
                        // ERROR_RECOGNIZER_BUSY는 잠시 후 재시도
                        val isBusyError = error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY
                        
                        // ERROR_CLIENT는 보통 이미 리스닝 중인데 다시 시작하려고 할 때 발생 (재시도 가능)
                        val isClientError = error == SpeechRecognizer.ERROR_CLIENT
                        
                        // ERROR 11은 SpeechRecognizer 서비스 에러 (재시도 가능)
                        val isError11 = error == 11
                        
                        if (!shouldContinueListening && !isBusyError && !isClientError && !isError11) {
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
                                Log.d("PingTalk", "Attempting to reinitialize SpeechRecognizer after error $error")
                                try {
                                    speechRecognizer?.stopListening()
                                    speechRecognizer?.destroy()
                                } catch (e: Exception) {
                                    Log.w("PingTalk", "Error cleaning up SpeechRecognizer: ${e.message}", e)
                                }
                                speechRecognizer = null
                                
                                // 재초기화 시도 (약간의 지연 후)
                                btnVoice.postDelayed({
                                    if (isListening) {
                                        try {
                                            initializeSpeechRecognizer()
                                            if (speechRecognizer != null) {
                                                // 재초기화 성공 시 다시 시작
                                                btnVoice.postDelayed({
                                                    if (isListening && speechRecognizer != null) {
                                                        startVoiceRecognition()
                                                    }
                                                }, 500) // 0.5초 후 재시작
                                            } else {
                                                Log.e("PingTalk", "Failed to reinitialize SpeechRecognizer after error $error")
                                                isListening = false
                                                updateVoiceButton()
                                            }
                                        } catch (e: Exception) {
                                            Log.e("PingTalk", "Failed to reinitialize SpeechRecognizer: ${e.message}", e)
                                            isListening = false
                                            updateVoiceButton()
                                        }
                                    }
                                }, 500) // 0.5초 후 재초기화
                            }
                        } else if (isBusyError || isClientError || isError11) {
                            // ERROR 11인 경우 SpeechRecognizer 재초기화 시도
                            if (isError11) {
                                Log.w("PingTalk", "Error 11 detected, reinitializing SpeechRecognizer")
                                try {
                                    speechRecognizer?.stopListening()
                                    speechRecognizer?.destroy()
                                } catch (e: Exception) {
                                    Log.w("PingTalk", "Error cleaning up SpeechRecognizer: ${e.message}", e)
                                }
                                speechRecognizer = null
                                
                                // 재초기화 시도
                                btnVoice.postDelayed({
                                    if (isListening) {
                                        try {
                                            initializeSpeechRecognizer()
                                            if (speechRecognizer != null) {
                                                // 재초기화 성공 시 다시 시작
                                                btnVoice.postDelayed({
                                                    if (isListening && speechRecognizer != null) {
                                                        try {
                                                            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                                                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 10)
                                                            }
                                                            speechRecognizer?.startListening(intent)
                                                            lastRetryTime = System.currentTimeMillis()
                                                            Log.d("PingTalk", "Restarted listening after error 11 reinitialization")
                                                        } catch (e: Exception) {
                                                            Log.e("PingTalk", "Error restarting after error 11: ${e.message}", e)
                                                            isListening = false
                                                            updateVoiceButton()
                                                        }
                                                    }
                                                }, 500) // 0.5초 후 재시작
                                            } else {
                                                Log.e("PingTalk", "Failed to reinitialize SpeechRecognizer after error 11")
                                                isListening = false
                                                updateVoiceButton()
                                            }
                                        } catch (e: Exception) {
                                            Log.e("PingTalk", "Error reinitializing SpeechRecognizer after error 11: ${e.message}", e)
                                            isListening = false
                                            updateVoiceButton()
                                        }
                                    }
                                }, 500) // 0.5초 후 재초기화
                                return@runOnUiThread
                            }
                            
                            // 이미 재시도 중이면 무시 (중복 재시도 방지)
                            if (isRetrying) {
                                Log.w("PingTalk", "Already retrying, ignoring ${if (isBusyError) "busy" else "client"} error")
                                return@runOnUiThread
                            }
                            
                            // isListening이 false면 재시도하지 않음
                            if (!isListening) {
                                Log.w("PingTalk", "Not listening, ignoring ${if (isBusyError) "busy" else "client"} error")
                                return@runOnUiThread
                            }
                            
                            val currentTime = System.currentTimeMillis()
                            
                            // 마지막 재시도 후 최소 간격이 지나지 않았으면 대기
                            val timeSinceLastRetry = currentTime - lastRetryTime
                            if (timeSinceLastRetry < MIN_RETRY_INTERVAL) {
                                val waitTime = MIN_RETRY_INTERVAL - timeSinceLastRetry
                                Log.d("PingTalk", "Too soon to retry (${timeSinceLastRetry}ms < ${MIN_RETRY_INTERVAL}ms), waiting ${waitTime}ms more")
                                btnVoice.postDelayed({
                                    // 재시도는 onError가 다시 호출되면 처리됨
                                }, waitTime)
                                return@runOnUiThread
                            }
                            
                            // BUSY 에러 연속 발생 추적
                            if (isBusyError) {
                                // 3초 이상 지났으면 카운터 리셋
                                if (currentTime - lastBusyErrorTime > BUSY_ERROR_RESET_INTERVAL) {
                                    consecutiveBusyErrors = 0
                                }
                                consecutiveBusyErrors++
                                lastBusyErrorTime = currentTime
                                
                                Log.w("PingTalk", "Recognizer busy (consecutive: $consecutiveBusyErrors/$MAX_CONSECUTIVE_BUSY_ERRORS)")
                                
                                // 연속 BUSY 에러가 너무 많으면 SpeechRecognizer 재초기화
                                if (consecutiveBusyErrors >= MAX_CONSECUTIVE_BUSY_ERRORS) {
                                    Log.e("PingTalk", "Too many consecutive BUSY errors ($consecutiveBusyErrors), reinitializing SpeechRecognizer")
                                    consecutiveBusyErrors = 0
                                    
                                    // 현재 SpeechRecognizer 정리
                                    try {
                                        speechRecognizer?.stopListening()
                                        speechRecognizer?.destroy()
                                    } catch (e: Exception) {
                                        Log.w("PingTalk", "Error cleaning up SpeechRecognizer: ${e.message}", e)
                                    }
                                    speechRecognizer = null
                                    
                                    // 재초기화 시도 (정리 시간 확보를 위해 지연)
                                    btnVoice.postDelayed({
                                        try {
                                            initializeSpeechRecognizer()
                                            if (speechRecognizer != null && isListening) {
                                                // 재초기화 성공 시 다시 시작
                                                btnVoice.postDelayed({
                                                    if (isListening && speechRecognizer != null) {
                                                        try {
                                                            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                                                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 10)
                                                            }
                                                            speechRecognizer?.startListening(intent)
                                                            Log.d("PingTalk", "Restarted listening after SpeechRecognizer reinitialization")
                                                            lastRecognitionTime = System.currentTimeMillis()
                                                            lastRetryTime = System.currentTimeMillis()
                                                        } catch (e: Exception) {
                                                            Log.e("PingTalk", "Error restarting after reinitialization: ${e.message}", e)
                                                            isListening = false
                                                            updateVoiceButton()
                                                        }
                                                    }
                                                }, 1000) // 1초 후 재시작
                                            } else {
                                                Log.e("PingTalk", "Failed to reinitialize SpeechRecognizer or not listening")
                                                isListening = false
                                                updateVoiceButton()
                                                Toast.makeText(this@MainActivity, "Voice recognition unavailable. Please try again.", Toast.LENGTH_LONG).show()
                                            }
                                        } catch (e: Exception) {
                                            Log.e("PingTalk", "Error reinitializing SpeechRecognizer: ${e.message}", e)
                                            isListening = false
                                            updateVoiceButton()
                                            Toast.makeText(this@MainActivity, "Voice recognition error. Please restart.", Toast.LENGTH_LONG).show()
                                        }
                                    }, 500) // 0.5초 후 재초기화
                                    return@runOnUiThread
                                }
                            }
                            
                            // CLIENT 에러 연속 발생 추적
                            if (isClientError) {
                                // 3초 이상 지났으면 카운터 리셋
                                if (currentTime - lastClientErrorTime > CLIENT_ERROR_RESET_INTERVAL) {
                                    consecutiveClientErrors = 0
                                }
                                consecutiveClientErrors++
                                lastClientErrorTime = currentTime
                                
                                Log.w("PingTalk", "Client error (consecutive: $consecutiveClientErrors/$MAX_CONSECUTIVE_CLIENT_ERRORS)")
                                
                                // 연속 CLIENT 에러가 너무 많으면 SpeechRecognizer 재초기화
                                if (consecutiveClientErrors >= MAX_CONSECUTIVE_CLIENT_ERRORS) {
                                    Log.e("PingTalk", "Too many consecutive CLIENT errors ($consecutiveClientErrors), reinitializing SpeechRecognizer")
                                    consecutiveClientErrors = 0
                                    
                                    // 현재 SpeechRecognizer 정리
                                    try {
                                        speechRecognizer?.stopListening()
                                        speechRecognizer?.destroy()
                                    } catch (e: Exception) {
                                        Log.w("PingTalk", "Error cleaning up SpeechRecognizer: ${e.message}", e)
                                    }
                                    speechRecognizer = null
                                    
                                    // 재초기화 시도 (정리 시간 확보를 위해 지연)
                                    btnVoice.postDelayed({
                                        try {
                                            initializeSpeechRecognizer()
                                            if (speechRecognizer != null && isListening) {
                                                // 재초기화 성공 시 다시 시작
                                                btnVoice.postDelayed({
                                                    if (isListening && speechRecognizer != null) {
                                                        try {
                                                            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                                                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 10)
                                                            }
                                                            speechRecognizer?.startListening(intent)
                                                            Log.d("PingTalk", "Restarted listening after SpeechRecognizer reinitialization")
                                                            lastRecognitionTime = System.currentTimeMillis()
                                                            lastRetryTime = System.currentTimeMillis()
                                                        } catch (e: Exception) {
                                                            Log.e("PingTalk", "Error restarting after reinitialization: ${e.message}", e)
                                                            isListening = false
                                                            updateVoiceButton()
                                                        }
                                                    }
                                                }, 1000) // 1초 후 재시작
                                            } else {
                                                Log.e("PingTalk", "Failed to reinitialize SpeechRecognizer or not listening")
                                                isListening = false
                                                updateVoiceButton()
                                                Toast.makeText(this@MainActivity, "Voice recognition unavailable. Please try again.", Toast.LENGTH_LONG).show()
                                            }
                                        } catch (e: Exception) {
                                            Log.e("PingTalk", "Error reinitializing SpeechRecognizer: ${e.message}", e)
                                            isListening = false
                                            updateVoiceButton()
                                            Toast.makeText(this@MainActivity, "Voice recognition error. Please restart.", Toast.LENGTH_LONG).show()
                                        }
                                    }, 500) // 0.5초 후 재초기화
                                    return@runOnUiThread
                                }
                            }
                            
                            // 재시도 간격 계산 (점진적 증가)
                            val consecutiveErrors = if (isBusyError) consecutiveBusyErrors else consecutiveClientErrors
                            val baseDelay = if (isClientError) 2000L else 2000L // CLIENT와 BUSY 모두 기본 2초
                            val exponentialDelay = minOf(baseDelay * (1 shl minOf(consecutiveErrors - 1, 2)), MAX_RETRY_INTERVAL) // 최대 5초
                            val retryDelay = maxOf(exponentialDelay, MIN_RETRY_INTERVAL) // 최소 2초
                            
                            Log.w("PingTalk", "Recognizer ${if (isBusyError) "busy" else "client error"} (consecutive: $consecutiveErrors), will retry after ${retryDelay}ms delay")
                            isRetrying = true
                            
                            // BUSY나 CLIENT 에러의 경우 먼저 stopListening을 호출하여 상태 정리
                            if (speechRecognizer != null) {
                                try {
                                    speechRecognizer?.stopListening()
                                    Log.d("PingTalk", "Stopped listening before retry after ${if (isBusyError) "busy" else "client"} error")
                                } catch (e: Exception) {
                                    Log.w("PingTalk", "Error stopping listening: ${e.message}", e)
                                }
                            }
                            
                            // stopListening 후 추가 대기 시간 확보
                            btnVoice.postDelayed({
                                btnVoice.postDelayed({
                                    isRetrying = false // 재시도 플래그 리셋
                                    if (isListening && speechRecognizer != null) {
                                        try {
                                            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 10)
                                            }
                                            speechRecognizer?.startListening(intent)
                                            lastRetryTime = System.currentTimeMillis()
                                            Log.d("PingTalk", "Retried listening after ${if (isBusyError) "busy" else "client"} error (delay: ${retryDelay}ms)")
                                            // 재시도 성공 시 에러 카운터는 유지 (onResults에서 리셋)
                                        } catch (e: Exception) {
                                            Log.e("PingTalk", "Error retrying after ${if (isBusyError) "busy" else "client"} error: ${e.message}", e)
                                            isListening = false
                                            updateVoiceButton()
                                        }
                                    } else {
                                        Log.w("PingTalk", "Cannot retry: isListening=$isListening, recognizer=${speechRecognizer != null}")
                                        isRetrying = false
                                    }
                                }, retryDelay) // 계산된 재시도 간격
                            }, 500) // stopListening 후 0.5초 추가 대기
                        } else if (shouldContinueListening) {
                            // NO_MATCH나 SPEECH_TIMEOUT는 정상적인 상황이므로 조용히 재시작
                            // (SpeechRecognizer는 onError 후 자동으로 중단되므로 재시작 필요)
                            if (isListening && speechRecognizer != null && !isRetrying) {
                                try {
                                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 10)
                                    }
                                    speechRecognizer?.startListening(intent)
                                    // 정상적인 상황이므로 로그는 조용히 (디버그 레벨만)
                                    Log.d("PingTalk", "Continuing to listen after: $errorMessage")
                                } catch (e: Exception) {
                                    Log.e("PingTalk", "Error continuing listening: ${e.message}", e)
                                    isListening = false
                                    updateVoiceButton()
                                }
                            } else if (isRetrying) {
                                Log.d("PingTalk", "Skipping restart: already retrying")
                            }
                        }
                    }
                }

                override fun onResults(results: Bundle?) {
                    // 결과 처리 후에도 계속 리스닝하도록 자동 종료하지 않음
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val confidence = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
                    
                    Log.d("PingTalk", "=== Voice Recognition Results ===")
                    
                    // Bundle의 모든 키 확인 (디버깅용)
                    if (results != null) {
                        Log.d("PingTalk", "Bundle keys: ${results.keySet().joinToString(", ")}")
                        results.keySet().forEach { key ->
                            val value = results.get(key)
                            Log.d("PingTalk", "  Key: $key, Value: $value (type: ${value?.javaClass?.simpleName})")
                        }
                    }
                    
                    if (matches != null && matches.isNotEmpty()) {
                        Log.d("PingTalk", "Total matches: ${matches.size}")
                        Log.d("PingTalk", "=== All Recognition Results ===")
                        matches.forEachIndexed { index, text ->
                            val conf = if (confidence != null && index < confidence.size) {
                                confidence[index]
                            } else {
                                null
                            }
                            Log.d("PingTalk", "Match[$index]: \"$text\" (confidence: $conf)")
                        }
                        Log.d("PingTalk", "=== End All Results ===")
                        
                        // 모든 결과를 확인하여 매칭되는 첫 번째 결과를 찾음 (임계값 낮춤 - 컨피던스 무시)
                        var matched = false
                        for (index in matches.indices) {
                            val match = matches[index]
                            val recognizedText = match.lowercase(Locale.getDefault())
                            val conf = if (confidence != null && index < confidence.size) {
                                confidence[index]
                            } else {
                                null
                            }
                            // 컨피던스 점수와 관계없이 모든 결과 확인 (임계값 없음)
                            Log.d("PingTalk", "Checking match[$index]: \"$recognizedText\" (confidence: $conf)")
                            
                            when {
                                // 블루 관련 단어들
                                recognizedText.contains("블루") || 
                                recognizedText.contains("blue") ||
                                recognizedText.contains("blu") ||
                                recognizedText.contains("불우") ||
                                recognizedText.contains("불루") ||
                                recognizedText.contains("블루윙") ||
                                recognizedText.contains("블루빈") ||
                                recognizedText.contains("블루윈") ||
                                recognizedText.contains("블루윤") ||
                                recognizedText.contains("blue wing") ||
                                recognizedText.contains("blue bean") ||
                                recognizedText.contains("blue win") -> {
                                    Log.d("PingTalk", "Action: HOME score increment (matched: \"$recognizedText\")")
                                    // 진동 발생
                                    vibrate()
                                    // HOME 점수 증가
                                    selectedSide = "HOME"
                                    sendCommand("inc", "HOME")
                                    render()
                                    Toast.makeText(this@MainActivity, "Blue +1", Toast.LENGTH_SHORT).show()
                                    matched = true
                                    break // 매칭되면 종료
                                }
                                // 레드 관련 단어들
                                recognizedText.contains("레드") || 
                                recognizedText.contains("red") ||
                                recognizedText.contains("redd") ||
                                recognizedText.contains("레디") ||
                                recognizedText.contains("래드") ||
                                recognizedText.contains("래디") ||
                                recognizedText.contains("레드윙") ||
                                recognizedText.contains("레드빈") ||
                                recognizedText.contains("레드윈") ||
                                recognizedText.contains("레드윤") ||
                                recognizedText.contains("read") ||
                                recognizedText.contains("ready") ||
                                recognizedText.contains("red wing") ||
                                recognizedText.contains("red bean") ||
                                recognizedText.contains("red win") -> {
                                    Log.d("PingTalk", "Action: AWAY score increment (matched: \"$recognizedText\")")
                                    // 진동 발생
                                    vibrate()
                                    // AWAY 점수 증가
                                    selectedSide = "AWAY"
                                    sendCommand("inc", "AWAY")
                                    render()
                                    Toast.makeText(this@MainActivity, "Red +1", Toast.LENGTH_SHORT).show()
                                    matched = true
                                    break // 매칭되면 종료
                                }
                            }
                        }
                        
                        if (!matched) {
                            Log.d("PingTalk", "No matching command found in any of ${matches.size} results")
                        }
                    } else {
                        Log.d("PingTalk", "No recognition results")
                    }
                    Log.d("PingTalk", "=== End Recognition Results ===")
                    
                    // 마지막 인식 시간 업데이트 및 재시작 실패 횟수 리셋
                    lastRecognitionTime = System.currentTimeMillis()
                    consecutiveRestartFailures = 0 // 인식 성공 시 실패 횟수 리셋
                    consecutiveBusyErrors = 0 // 인식 성공 시 BUSY 에러 카운터 리셋
                    consecutiveClientErrors = 0 // 인식 성공 시 CLIENT 에러 카운터 리셋
                    isRetrying = false // 재시도 플래그 리셋
                    
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
                                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 10)
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
                    val confidence = partialResults?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
                    
                    if (matches != null && matches.isNotEmpty()) {
                        Log.d("PingTalk", "=== Partial Results ===")
                        matches.forEachIndexed { index, text ->
                            val conf = if (confidence != null && index < confidence.size) {
                                confidence[index]
                            } else {
                                null
                            }
                            Log.d("PingTalk", "Partial[$index]: \"$text\" (confidence: $conf)")
                        }
                        Log.d("PingTalk", "=== End Partial Results ===")
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
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 10)
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
    
    private fun updateAlwaysOnState() {
        if (isAlwaysOn) {
            // Always On 활성화
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            btnAlwaysOn.text = "ALWAYS ON"
            btnAlwaysOn.setBackgroundColor(Color.rgb(100, 200, 100)) // 초록색
            Log.d("PingTalk", "Always On enabled")
        } else {
            // Always On 비활성화
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            btnAlwaysOn.text = "ALWAYS OFF"
            btnAlwaysOn.setBackgroundColor(Color.rgb(150, 150, 150)) // 회색
            Log.d("PingTalk", "Always On disabled")
        }
    }
    
    private fun stopVoiceRecognition() {
        speechRecognizer?.stopListening()
        isListening = false
        isRetrying = false // 재시도 플래그 리셋
        consecutiveBusyErrors = 0 // BUSY 에러 카운터 리셋
        consecutiveClientErrors = 0 // CLIENT 에러 카운터 리셋
        stopRestartCheck()
        updateVoiceButton()
        // SharedPreferences에서도 상태 제거
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_WAS_LISTENING, false)
            .apply()
    }
    
    private fun startRestartCheck() {
        stopRestartCheck()
        consecutiveRestartFailures = 0 // 재시작 체크 시작 시 실패 횟수 초기화
        restartCheckHandler = android.os.Handler(android.os.Looper.getMainLooper())
        restartCheckHandler?.postDelayed(object : Runnable {
            override fun run() {
                if (isListening) {
                    val timeSinceLastRecognition = System.currentTimeMillis() - lastRecognitionTime
                    val timeSinceLastRestart = System.currentTimeMillis() - lastRestartAttemptTime
                    
                    // 연속 실패가 너무 많으면 포기
                    if (consecutiveRestartFailures >= MAX_CONSECUTIVE_FAILURES) {
                        Log.e("PingTalk", "Too many consecutive restart failures ($consecutiveRestartFailures), giving up")
                        isListening = false
                        updateVoiceButton()
                        Toast.makeText(this@MainActivity, "Voice recognition stopped. Please restart manually.", Toast.LENGTH_LONG).show()
                        return
                    }
                    
                    // 15초 이상 응답이 없고, 마지막 재시작 시도 후 5초 이상 지났으면 재시작
                    if (timeSinceLastRecognition > 15000 && timeSinceLastRestart > 5000) {
                        Log.w("PingTalk", "No recognition response for ${timeSinceLastRecognition}ms, attempting restart (failures: $consecutiveRestartFailures)")
                        lastRestartAttemptTime = System.currentTimeMillis()
                        
                        if (speechRecognizer != null) {
                            try {
                                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 10)
                                }
                                speechRecognizer?.startListening(intent)
                                lastRecognitionTime = System.currentTimeMillis()
                                Log.d("PingTalk", "Restarted listening due to timeout")
                                // 재시작 성공 시 실패 횟수는 onResults에서 리셋됨
                            } catch (e: Exception) {
                                Log.e("PingTalk", "Error restarting after timeout: ${e.message}", e)
                                consecutiveRestartFailures++
                                if (consecutiveRestartFailures >= MAX_CONSECUTIVE_FAILURES) {
                                    isListening = false
                                    updateVoiceButton()
                                }
                            }
                        } else {
                            Log.w("PingTalk", "SpeechRecognizer is null, reinitializing")
                            try {
                                initializeSpeechRecognizer()
                                if (speechRecognizer != null && isListening) {
                                    startVoiceRecognition()
                                    consecutiveRestartFailures = 0 // 재초기화 성공
                                } else {
                                    consecutiveRestartFailures++
                                    if (consecutiveRestartFailures >= MAX_CONSECUTIVE_FAILURES) {
                                        isListening = false
                                        updateVoiceButton()
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e("PingTalk", "Error reinitializing: ${e.message}", e)
                                consecutiveRestartFailures++
                                if (consecutiveRestartFailures >= MAX_CONSECUTIVE_FAILURES) {
                                    isListening = false
                                    updateVoiceButton()
                                }
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
        
        // SharedPreferences에서 리스닝 상태 복원 (앱이 완전히 종료되어도 복원 가능)
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val shouldRestoreFromPrefs = prefs.getBoolean(KEY_WAS_LISTENING, false)
        Log.d("PingTalk", "onResume: wasListeningBeforePause=$wasListeningBeforePause, shouldRestoreFromPrefs=$shouldRestoreFromPrefs")
        
        // 메모리의 플래그와 SharedPreferences 모두 확인
        val shouldRestore = wasListeningBeforePause || shouldRestoreFromPrefs
        
        if (shouldRestoreFromPrefs && !wasListeningBeforePause) {
            Log.d("PingTalk", "App resumed, found saved listening state in SharedPreferences - will restore")
            wasListeningBeforePause = true
        }
        
        // SpeechRecognizer가 null이면 재초기화 (권한이 있는 경우)
        if (speechRecognizer == null && 
            ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) 
            == PackageManager.PERMISSION_GRANTED) {
            Log.d("PingTalk", "App resumed, reinitializing speech recognizer")
            initializeSpeechRecognizer()
        }
        
        // 이전에 리스닝 중이었으면 다시 시작
        if (shouldRestore) {
            Log.d("PingTalk", "App resumed, restoring voice recognition state (shouldRestore=$shouldRestore)")
            
            // 복원 시 SpeechRecognizer를 완전히 재초기화하여 ERROR_CLIENT 방지
            if (speechRecognizer != null) {
                Log.d("PingTalk", "Destroying existing SpeechRecognizer before restore to prevent ERROR_CLIENT")
                try {
                    speechRecognizer?.stopListening()
                    speechRecognizer?.destroy()
                } catch (e: Exception) {
                    Log.w("PingTalk", "Error destroying SpeechRecognizer: ${e.message}", e)
                }
                speechRecognizer = null
            }
            
            // SpeechRecognizer 재초기화
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) 
                == PackageManager.PERMISSION_GRANTED) {
                Log.d("PingTalk", "Reinitializing SpeechRecognizer for clean restore")
                initializeSpeechRecognizer()
            }
            
            // 충분한 대기 시간 후 재시작 (ERROR_CLIENT 방지 및 딜레이 최소화)
            btnVoice.postDelayed({
                if (speechRecognizer != null) {
                    Log.d("PingTalk", "Attempting to restore voice recognition...")
                    // 복원 전에 isListening을 false로 설정 (startVoiceRecognition이 정상 동작하도록)
                    isListening = false
                    updateVoiceButton()
                    startVoiceRecognition()
                    // 복원 성공 여부 확인 (isListening이 true가 되었는지)
                    btnVoice.postDelayed({
                        if (isListening) {
                            Log.d("PingTalk", "Voice recognition restored successfully, clearing SharedPreferences")
                            // 복원 성공 시 SharedPreferences에서 상태 제거
                            prefs.edit().putBoolean(KEY_WAS_LISTENING, false).apply()
                        } else {
                            Log.w("PingTalk", "Voice recognition restoration failed (isListening is still false)")
                            // 복원 실패 시에도 SharedPreferences는 유지 (다음 onResume에서 재시도)
                        }
                    }, 1000) // 1초 후 복원 성공 여부 확인
                } else {
                    Log.w("PingTalk", "Cannot restore voice recognition: SpeechRecognizer is null after initialization")
                    isListening = false
                    updateVoiceButton()
                    // SpeechRecognizer가 null이면 SharedPreferences는 유지 (다음 onResume에서 재시도)
                }
            }, 1000) // 1초 후 재시작 (SpeechRecognizer 완전 정리 및 재초기화 시간 확보)
            
            wasListeningBeforePause = false // 플래그 리셋
        } else {
            // 이전에 리스닝 중이 아니었으면 상태 정리
            Log.d("PingTalk", "No need to restore voice recognition")
            isListening = false
            updateVoiceButton()
            // SharedPreferences에서도 상태 제거
            prefs.edit().putBoolean(KEY_WAS_LISTENING, false).apply()
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
            // SpeechRecognizer 완전히 정리 (ERROR_CLIENT 방지)
            try {
                speechRecognizer?.stopListening()
                stopRestartCheck()
            } catch (e: Exception) {
                Log.w("PingTalk", "Error stopping listening in onPause: ${e.message}", e)
            }
            // SharedPreferences에 상태 저장 (앱이 완전히 종료되어도 복원 가능)
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean(KEY_WAS_LISTENING, true)
                .apply()
            Log.d("PingTalk", "Saved listening state to SharedPreferences: true")
            // isListening은 true로 유지 (onResume에서 복원할 때 사용)
            // SpeechRecognizer는 onResume에서 재초기화하므로 여기서는 destroy하지 않음
        } else {
            wasListeningBeforePause = false
            // SharedPreferences에서 상태 제거
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean(KEY_WAS_LISTENING, false)
                .apply()
            Log.d("PingTalk", "Cleared listening state from SharedPreferences")
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

