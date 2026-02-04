import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pingtalk_core/pingtalk_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'l10n/app_localizations.dart';
import 'splash_screen.dart';

// 스와이프 민감도를 낮춘 커스텀 ScrollPhysics
class _LessSensitivePageScrollPhysics extends PageScrollPhysics {
  const _LessSensitivePageScrollPhysics({super.parent});

  @override
  _LessSensitivePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _LessSensitivePageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get dragStartDistanceMotionThreshold => 10.0; // 기본값 3.0보다 높게 설정
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 가로/세로 모드 모두 허용
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const PingTalkApp());
}

class PingTalkApp extends StatefulWidget {
  const PingTalkApp({super.key});

  @override
  State<PingTalkApp> createState() => _PingTalkAppState();
}

class _PingTalkAppState extends State<PingTalkApp> {
  Locale _locale = _getSystemLocale();

  void _setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  // 시스템 로케일을 감지하여 지원하는 언어로 변환
  static Locale _getSystemLocale() {
    final systemLocale = ui.PlatformDispatcher.instance.locale;
    final systemLanguageCode = systemLocale.languageCode;

    // 지원하는 언어 목록
    const supportedLanguages = ['ko', 'en', 'zh', 'ja'];

    // 시스템 언어가 지원 목록에 있으면 사용, 없으면 한국어 기본값
    if (supportedLanguages.contains(systemLanguageCode)) {
      return Locale(systemLanguageCode);
    }

    // 중국어 변형 처리 (zh-Hans, zh-Hant 등)
    if (systemLanguageCode.startsWith('zh')) {
      return const Locale('zh');
    }

    // 기본값: 한국어
    return const Locale('ko');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PingBoard',
      locale: _locale,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BFA5),
          brightness: Brightness.dark,
        ),
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', ''),
        Locale('en', ''),
        Locale('zh', ''),
        Locale('ja', ''),
      ],
      home: SplashWrapper(onLocaleChanged: _setLocale),
    );
  }
}

class SplashWrapper extends StatefulWidget {
  final ValueChanged<Locale> onLocaleChanged;

  const SplashWrapper({super.key, required this.onLocaleChanged});

  @override
  State<SplashWrapper> createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<SplashWrapper> {
  @override
  void initState() {
    super.initState();
    // 스플래시 화면을 2초간 표시한 후 메인 화면으로 전환
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) =>
                ScoreboardPage(onLocaleChanged: widget.onLocaleChanged),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}

enum WatchConnectionStatus {
  disconnected,
  connecting,
  connected,
  syncing,
  synced,
  syncFailed,
}

class ScoreboardPage extends StatefulWidget {
  final ValueChanged<Locale> onLocaleChanged;

  const ScoreboardPage({super.key, required this.onLocaleChanged});

  @override
  State<ScoreboardPage> createState() => _ScoreboardPageState();
}

class _ScoreboardPageState extends State<ScoreboardPage> {
  static const MethodChannel _watchChannel = MethodChannel('pingtalk/watch');
  static const MethodChannel _mediaChannel = MethodChannel('pingtalk/media');
  static const String _prefsKeyState = 'match_state';
  static const String _prefsKeySwipeGuideShown = 'swipe_guide_shown';
  static const String _prefsKeyLocale = 'app_locale';
  static const String _prefsKeyAutoSwapEnabled = 'auto_swap_enabled';
  // static const String _prefsKeyHistory = 'match_history'; // 향후 경기 기록 기능용
  static const int _maxHistorySize = 100;

  MatchState? _state;
  WatchConnectionStatus _watchStatus = WatchConnectionStatus.disconnected;
  StreamSubscription<dynamic>? _methodCallSub;

  // 상태 히스토리 (Undo용)
  final List<MatchState> _stateHistory = [];

  // 처리된 명령 ID (idempotency용)
  final Set<String> _processedCommandIds = {};

  SharedPreferences? _prefs;
  bool _isInitialized = false;
  bool _showSwipeGuide = false;
  PageController? _pageController;
  Locale _currentLocale = const Locale('ko');

  // 스톱워치 관련 상태
  int _elapsedSeconds = 0;
  bool _isStopwatchRunning = false;
  Timer? _stopwatchTimer;
  int _stopwatchPausedSeconds = 0;

  // 카메라 관련 상태
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCameraPreviewVisible = false;
  Timer? _cameraPreviewTimer;
  bool _isRecording = false;
  CameraLensDirection _currentCameraDirection = CameraLensDirection.front;

  // 좌우 배치에서 블루/레드 카드 위치 (true: 블루가 왼쪽, false: 레드가 왼쪽)
  // 위아래 배치일 때는 사용되지 않음
  bool _isBlueOnLeft = true;

  // 게임 종료 시 자동 위치 교체 기능 활성화 여부
  bool _autoSwapEnabled = true;

  // 점수판이 좌우 배치인지 확인하는 헬퍼 함수
  // OrientationBuilder의 orientation을 사용하거나, 없으면 MediaQuery의 orientation 사용
  bool _isRowLayout(BuildContext context, Orientation? orientation) {
    final screenSize = MediaQuery.of(context).size;
    // orientation이 제공되면 사용, 없으면 MediaQuery에서 가져옴
    final actualOrientation = orientation ?? MediaQuery.of(context).orientation;
    final isPortrait = actualOrientation == Orientation.portrait;
    // 가로 모드이거나 세로 모드에서도 화면이 넓으면 좌우 배치
    return !isPortrait || screenSize.width > screenSize.height * 0.7;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _pageController?.addListener(_onPageChanged);
    // 초기 상태 설정
    _state = MatchState(
      matchId: 'local',
      playerAName: 'Blue',
      playerBName: 'Red',
      scoreA: 0,
      scoreB: 0,
      version: 0,
      lastUpdatedAt: DateTime.now().toUtc(),
      lastUpdatedBy: UpdatedBy.phone,
    );
    _addToHistory(_state!);
    _initialize();
    // 점수판 화면에서 화면이 꺼지지 않도록 설정
    WakelockPlus.enable();
  }

  void _onPageChanged() {
    if (_pageController?.page != null &&
        _pageController!.page! > 0.5 &&
        _showSwipeGuide) {
      // 히스토리 페이지로 스와이프했으면 가이드 숨기기
      _hideSwipeGuide();
    }
  }

  Future<void> _hideSwipeGuide() async {
    if (!_showSwipeGuide) return;
    setState(() {
      _showSwipeGuide = false;
    });
    if (_prefs != null) {
      await _prefs!.setBool(_prefsKeySwipeGuideShown, true);
    }
  }

  Future<void> _initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadState();
      await _loadLocale();
      await _loadAutoSwapSetting();
    } catch (e) {
      // SharedPreferences 초기화 실패 시 기본값 사용
      // (플러그인이 아직 준비되지 않았을 수 있음)
    }
    _watchChannel.setMethodCallHandler(_onWatchMethodCall);
    await _initializeCamera();

    // 스와이프 가이드 표시 여부 확인 (초기화 완료 후)
    final guideShown = _prefs?.getBool(_prefsKeySwipeGuideShown) ?? false;
    if (mounted) {
      setState(() {
        _isInitialized = true;
        _showSwipeGuide = !guideShown;
      });
    }
  }

  Future<void> _loadAutoSwapSetting() async {
    if (_prefs == null) return;
    final enabled = _prefs!.getBool(_prefsKeyAutoSwapEnabled);
    if (mounted) {
      setState(() {
        _autoSwapEnabled = enabled ?? true; // 기본값은 true
      });
    }
  }

  Future<void> _saveAutoSwapSetting(bool enabled) async {
    if (_prefs == null) return;
    await _prefs!.setBool(_prefsKeyAutoSwapEnabled, enabled);
    if (mounted) {
      setState(() {
        _autoSwapEnabled = enabled;
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // 카메라 권한 확인
      final cameraStatus = await Permission.camera.status;
      final microphoneStatus = await Permission.microphone.status;

      // Android 13+ 미디어 권한 확인
      final storageStatus = await Permission.storage.status;
      final photosStatus = await Permission.photos.status;

      if (!cameraStatus.isGranted) {
        await Permission.camera.request();
      }
      if (!microphoneStatus.isGranted) {
        await Permission.microphone.request();
      }
      // Android 13 이상에서는 photos 권한, 이하는 storage 권한
      if (!photosStatus.isGranted && !storageStatus.isGranted) {
        await Permission.photos.request();
        if (!await Permission.photos.isGranted) {
          await Permission.storage.request();
        }
      }

      // 권한이 허용된 경우에만 카메라 초기화
      if (await Permission.camera.isGranted) {
        _cameras = await availableCameras();
        if (_cameras != null && _cameras!.isNotEmpty) {
          // 전면 카메라 우선 사용
          final camera = _cameras!.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras!.first,
          );

          _cameraController = CameraController(
            camera,
            ResolutionPreset.medium,
            enableAudio: true,
          );

          await _cameraController!.initialize();
          if (mounted) {
            setState(() {
              _isCameraInitialized = true;
              _currentCameraDirection = camera.lensDirection;
            });
          }
        }
      }
    } catch (e) {
      // 카메라 초기화 실패 시 무시 (카메라가 없는 기기일 수 있음)
      print('Camera initialization failed: $e');
    }
  }

  void _showCameraPreview() {
    if (!_isCameraInitialized || _cameraController == null) return;

    setState(() {
      _isCameraPreviewVisible = true;
    });

    _resetCameraPreviewTimer();
  }

  void _resetCameraPreviewTimer() {
    // 30초 후 자동으로 닫기
    _cameraPreviewTimer?.cancel();
    _cameraPreviewTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        _hideCameraPreview();
      }
    });
  }

  void _hideCameraPreview() {
    _cameraPreviewTimer?.cancel();
    setState(() {
      _isCameraPreviewVisible = false;
    });
  }

  void _showVideoSavedNotification(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const baseBg = Color(0xFF0B1220);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: scheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '동영상이 갤러리에 저장되었습니다',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: baseBg,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: scheme.primary.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        elevation: 8,
      ),
    );
  }

  Future<void> _switchCamera() async {
    if (!_isCameraInitialized || _cameras == null || _cameras!.isEmpty) return;
    if (_isRecording) return; // 녹화 중에는 카메라 전환 불가

    try {
      // 현재 카메라 방향의 반대 방향 찾기
      final newDirection = _currentCameraDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;

      final newCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == newDirection,
        orElse: () => _cameras!.first,
      );

      // 기존 카메라 컨트롤러 해제
      await _cameraController?.dispose();

      // 새 카메라 컨트롤러 생성
      _cameraController = CameraController(
        newCamera,
        ResolutionPreset.medium,
        enableAudio: true,
      );

      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _currentCameraDirection = newCamera.lensDirection;
        });
      }
    } catch (e) {
      print('Failed to switch camera: $e');
    }
  }

  Future<void> _startRecording() async {
    if (!_isCameraInitialized || _cameraController == null || _isRecording) {
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      print('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording || _cameraController == null) return;

    try {
      final file = await _cameraController!.stopVideoRecording();
      setState(() {
        _isRecording = false;
      });

      // 갤러리에 저장 (네이티브 코드로 MediaStore에 등록)
      try {
        final result = await _mediaChannel.invokeMethod('saveVideoToGallery', {
          'videoPath': file.path,
        });
        if (result == true) {
          print('Video saved to gallery: ${file.path}');
          // 성공 메시지 표시
          if (mounted) {
            _showVideoSavedNotification(context);
          }
        } else {
          print('Failed to save video to gallery');
        }
      } catch (e) {
        print('Error saving to gallery: $e');
        // 저장 실패해도 파일은 저장됨
        print('Video saved to: ${file.path}');
      }
    } catch (e) {
      print('Failed to stop recording: $e');
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _loadLocale() async {
    if (_prefs == null) return;

    // SharedPreferences에 저장된 언어가 있으면 사용
    final savedLocaleCode = _prefs!.getString(_prefsKeyLocale);
    if (savedLocaleCode != null) {
      setState(() {
        _currentLocale = Locale(savedLocaleCode);
      });
      widget.onLocaleChanged(_currentLocale);
      return;
    }

    // 저장된 언어가 없으면 시스템 로케일 사용
    final systemLocale = ui.PlatformDispatcher.instance.locale;
    final systemLanguageCode = systemLocale.languageCode;

    // 지원하는 언어 목록
    const supportedLanguages = ['ko', 'en', 'zh', 'ja'];

    String localeCode;
    if (supportedLanguages.contains(systemLanguageCode)) {
      localeCode = systemLanguageCode;
    } else if (systemLanguageCode.startsWith('zh')) {
      // 중국어 변형 처리
      localeCode = 'zh';
    } else {
      // 지원하지 않는 언어면 한국어 기본값
      localeCode = 'ko';
    }

    // 시스템 로케일을 SharedPreferences에 저장 (다음 실행 시에도 유지)
    await _prefs!.setString(_prefsKeyLocale, localeCode);

    setState(() {
      _currentLocale = Locale(localeCode);
    });
    widget.onLocaleChanged(_currentLocale);

    // 워치에도 초기 언어 설정 전달
    await _pushLanguageToWatch(localeCode);
  }

  Future<void> _saveLocale(String localeCode) async {
    if (_prefs == null) return;
    await _prefs!.setString(_prefsKeyLocale, localeCode);
    final newLocale = Locale(localeCode);
    setState(() {
      _currentLocale = newLocale;
    });
    widget.onLocaleChanged(newLocale);
    // 워치에 언어 변경 알림
    await _pushLanguageToWatch(localeCode);
  }

  Future<void> _pushLanguageToWatch(String localeCode) async {
    try {
      print('PingTalk: Pushing language to watch: $localeCode');
      await _watchChannel.invokeMethod('setLanguage', {'locale': localeCode});
      print('PingTalk: Language pushed successfully');
    } catch (e) {
      print('PingTalk: Failed to push language to watch: $e');
      // 워치 연결 실패 시 무시
    }
  }

  Future<void> _loadState() async {
    if (_prefs == null) return;
    final stateJson = _prefs!.getString(_prefsKeyState);
    if (stateJson != null) {
      try {
        final map = jsonDecode(stateJson) as Map<String, Object?>;
        final loadedState = MatchState.fromJson(map);
        setState(() {
          _state = loadedState;
          // 히스토리 초기화 후 로드된 상태 추가
          _stateHistory.clear();
          _addToHistory(loadedState);
        });
        return;
      } catch (e) {
        // JSON 파싱 실패 시 기본값 유지
      }
    }
  }

  Future<void> _saveState() async {
    if (_prefs == null || _state == null) return;
    await _prefs!.setString(_prefsKeyState, jsonEncode(_state!.toJson()));
  }

  void _addToHistory(MatchState state) {
    _stateHistory.add(state);
    // 히스토리 크기 제한
    if (_stateHistory.length > _maxHistorySize) {
      _stateHistory.removeAt(0);
    }
  }

  @override
  void dispose() {
    _pageController?.removeListener(_onPageChanged);
    _pageController?.dispose();
    _methodCallSub?.cancel();
    _stopwatchTimer?.cancel();
    _cameraPreviewTimer?.cancel();
    _cameraController?.dispose();
    // 화면 켜짐 유지 해제
    WakelockPlus.disable();
    super.dispose();
  }

  void _startStopwatch() {
    if (_isStopwatchRunning) return;
    setState(() {
      _isStopwatchRunning = true;
    });
    _stopwatchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds = _stopwatchPausedSeconds + timer.tick;
        });
      }
    });
  }

  void _pauseStopwatch() {
    if (!_isStopwatchRunning) return;
    _stopwatchTimer?.cancel();
    setState(() {
      _isStopwatchRunning = false;
      _stopwatchPausedSeconds = _elapsedSeconds;
    });
  }

  void _resetStopwatch() {
    _stopwatchTimer?.cancel();
    setState(() {
      _isStopwatchRunning = false;
      _elapsedSeconds = 0;
      _stopwatchPausedSeconds = 0;
    });
  }

  void _toggleStopwatch() {
    if (_isStopwatchRunning) {
      _pauseStopwatch();
    } else {
      _startStopwatch();
    }
  }

  Future<void> _onWatchMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'command':
        final args = (call.arguments as Map?)?.cast<String, Object?>();
        if (args == null) return;

        final cmd = ScoreCommand.fromJson(args);

        // Idempotency 체크: 이미 처리된 명령은 무시
        if (_processedCommandIds.contains(cmd.id)) {
          // 이미 처리된 명령이지만 워치에 상태를 다시 보내줌
          await _pushStateToWatch();
          return;
        }

        // Undo 명령은 별도 처리
        if (cmd.type == CommandType.undo) {
          // Undo 가능 여부 확인
          if (!_canUndo) {
            // Undo 불가능하면 현재 상태만 전송
            await _pushStateToWatch();
            return;
          }

          // 명령 ID 기록
          _processedCommandIds.add(cmd.id);

          // Undo 실행
          _undo();
          return;
        }

        // Reset 명령은 히스토리를 먼저 초기화
        if (cmd.type == CommandType.reset) {
          _stateHistory.clear();
        }

        _applyCommand(cmd, appliedBy: UpdatedBy.watch);
        await _pushStateToWatch();
        return;
      case 'ping':
        setState(() {
          _watchStatus = WatchConnectionStatus.connected;
        });
        // 연결 시 최신 상태와 언어 설정을 워치로 전송
        await _pushStateToWatch();
        await _pushLanguageToWatch(_currentLocale.languageCode);
        return;
      default:
        return;
    }
  }

  String _newCommandId() => 'cmd_${DateTime.now().microsecondsSinceEpoch}';

  void _applyCommand(ScoreCommand command, {required UpdatedBy appliedBy}) {
    if (_state == null) return;

    // 게임 종료 감지를 위해 이전 세트 스코어 길이 저장
    final previousSetScoresLength = _state!.setScoresA.length;

    final next = ScoreReducer.apply(
      current: _state!,
      command: command,
      appliedAt: DateTime.now().toUtc(),
      appliedBy: appliedBy,
    );
    if (identical(next, _state)) return;

    // 명령 ID 기록 (idempotency)
    _processedCommandIds.add(command.id);
    // 오래된 명령 ID는 정리 (메모리 관리)
    if (_processedCommandIds.length > 1000) {
      _processedCommandIds.remove(_processedCommandIds.first);
    }

    // 게임 종료 감지: 세트 스코어 길이가 변경되었는지 확인
    final gameEnded = next.setScoresA.length > previousSetScoresLength;

    // 점수 카드가 좌우로 배치될 때만 게임 종료 시 카드 위치 교체 (설정이 활성화된 경우만)
    if (gameEnded && mounted && _autoSwapEnabled) {
      // 점수판이 실제로 좌우 배치인지 확인
      // _isRowLayout 함수를 사용하여 점수판 렌더링 로직과 동일하게 확인
      if (_isRowLayout(context, null)) {
        _isBlueOnLeft = !_isBlueOnLeft;
      }
    }

    setState(() {
      _state = next;
      _watchStatus = WatchConnectionStatus.syncing;
    });

    // 히스토리에 추가 (리셋 명령도 추가 - 리셋된 상태에서 시작)
    _addToHistory(next);

    // 상태 저장
    unawaited(_saveState());
  }

  Future<void> _pushStateToWatch() async {
    if (_state == null) return;
    try {
      await _watchChannel.invokeMethod('state', _state!.toJson());
      if (!mounted) return;
      setState(() {
        _watchStatus = WatchConnectionStatus.synced;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _watchStatus = WatchConnectionStatus.syncFailed;
      });
    }
  }

  void _undo() {
    if (_stateHistory.length <= 1) return; // 최소 1개는 유지

    // 마지막 상태 제거 (현재 상태)
    _stateHistory.removeLast();

    // 이전 상태로 복원
    final previousState = _stateHistory.last;
    setState(() {
      _state = previousState;
    });

    // 상태 저장
    unawaited(_saveState());

    // 워치에 동기화
    unawaited(_pushStateToWatch());
  }

  bool get _canUndo => _stateHistory.length > 1;

  void _showGuideDialog(BuildContext context, ColorScheme scheme) {
    showDialog(
      context: context,
      builder: (context) => _GuideDialog(scheme: scheme),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    if (_state == null) return;

    showDialog(
      context: context,
      builder: (context) => _SettingsDialog(
        rules: _state!.rules,
        currentLocale: _currentLocale.languageCode,
        autoSwapEnabled: _autoSwapEnabled,
        onSave: (rules) {
          setState(() {
            _state = _state!.copyWith(rules: rules);
          });
          unawaited(_saveState());
          Navigator.of(context).pop();
        },
        onLocaleChanged: (localeCode) {
          unawaited(_saveLocale(localeCode));
        },
        onAutoSwapChanged: (enabled) {
          unawaited(_saveAutoSwapSetting(enabled));
        },
      ),
    );
  }

  void _inc(ScoreSide side) {
    if (_state == null) return;
    _applyCommand(
      ScoreCommand(
        id: _newCommandId(),
        matchId: _state!.matchId,
        type: CommandType.inc,
        side: side,
        issuedAt: DateTime.now().toUtc(),
        issuedBy: UpdatedBy.phone,
      ),
      appliedBy: UpdatedBy.phone,
    );
    unawaited(_pushStateToWatch());
  }

  void _reset() {
    if (_state == null) return;

    // 확인 다이얼로그 표시
    showDialog(
      context: context,
      builder: (context) => _ResetConfirmDialog(
        onConfirm: () {
          // 히스토리 초기화
          _stateHistory.clear();

          // 점수 초기화
          _applyCommand(
            ScoreCommand(
              id: _newCommandId(),
              matchId: _state!.matchId,
              type: CommandType.reset,
              issuedAt: DateTime.now().toUtc(),
              issuedBy: UpdatedBy.phone,
            ),
            appliedBy: UpdatedBy.phone,
          );
          unawaited(_pushStateToWatch());

          Navigator.of(context).pop();
        },
      ),
    );
  }

  String _getWatchStatusText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return '워치: 미연동';
    switch (_watchStatus) {
      case WatchConnectionStatus.disconnected:
        return l10n.watchDisconnected;
      case WatchConnectionStatus.connecting:
        return l10n.watchConnecting;
      case WatchConnectionStatus.connected:
        return l10n.watchConnected;
      case WatchConnectionStatus.syncing:
        return l10n.watchSyncing;
      case WatchConnectionStatus.synced:
        return l10n.watchSynced;
      case WatchConnectionStatus.syncFailed:
        return l10n.watchSyncFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 초기화 전이거나 상태가 없으면 로딩 표시
    if (!_isInitialized || _state == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    const baseBg = Color(0xFF0B1220);
    // 좌/우 배경은 같은 톤(다크)인데 확실히 다른 느낌이 나도록 분리
    const homeBg = Color(0xFF0E2238); // HOME: 블루/청록 계열
    const awayBg = Color(0xFF2A1420); // AWAY: 버건디/레드 계열
    const homeAccent = Color(0xFF3DDCFF); // HOME: 청록-하늘 대비
    const awayAccent = Color(0xFFFFC14D); // AWAY: 따뜻한 대비

    return Scaffold(
      backgroundColor: baseBg,
      body: SafeArea(
        bottom: true,
        child: Stack(
          children: [
            PageView(
              controller: _pageController ?? PageController(initialPage: 0),
              physics: const _LessSensitivePageScrollPhysics(),
              children: [
                // 메인 스코어 화면
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 좌측 타이틀
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'PINGBOARD',
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.9),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),

                          // 중앙 버튼들
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Undo 버튼
                              IconButton(
                                onPressed: _canUndo ? _undo : null,
                                tooltip: 'UNDO',
                                icon: Icon(
                                  Icons.undo,
                                  color: _canUndo
                                      ? scheme.onSurface.withValues(alpha: 0.9)
                                      : scheme.onSurface.withValues(alpha: 0.3),
                                ),
                              ),
                              // 리셋 버튼
                              IconButton(
                                onPressed: _reset,
                                tooltip: 'RESET',
                                icon: Icon(
                                  Icons.restart_alt,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.9,
                                  ),
                                ),
                              ),
                              // 설정 버튼
                              Builder(
                                builder: (context) {
                                  final l10n = AppLocalizations.of(context);
                                  return IconButton(
                                    onPressed: () =>
                                        _showSettingsDialog(context),
                                    tooltip: l10n?.settings ?? '설정',
                                    icon: Icon(
                                      Icons.settings,
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),

                          // 우측 워치 상태 표시
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              _getWatchStatusText(context),
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          OrientationBuilder(
                            builder: (context, orientation) {
                              // 점수판이 실제로 좌우 배치인지 확인
                              final useRowLayout = _isRowLayout(
                                context,
                                orientation,
                              );

                              if (useRowLayout) {
                                // 좌우 배치 (게임 종료 시 위치 교체)
                                final leftBg = _isBlueOnLeft ? homeBg : awayBg;
                                final leftAccent = _isBlueOnLeft
                                    ? homeAccent
                                    : awayAccent;
                                final leftLabel = _isBlueOnLeft
                                    ? 'Blue'
                                    : 'Red';
                                final leftScore = _isBlueOnLeft
                                    ? _state!.scoreA
                                    : _state!.scoreB;
                                final leftOnInc = _isBlueOnLeft
                                    ? () => _inc(ScoreSide.home)
                                    : () => _inc(ScoreSide.away);

                                final rightBg = _isBlueOnLeft ? awayBg : homeBg;
                                final rightAccent = _isBlueOnLeft
                                    ? awayAccent
                                    : homeAccent;
                                final rightLabel = _isBlueOnLeft
                                    ? 'Red'
                                    : 'Blue';
                                final rightScore = _isBlueOnLeft
                                    ? _state!.scoreB
                                    : _state!.scoreA;
                                final rightOnInc = _isBlueOnLeft
                                    ? () => _inc(ScoreSide.away)
                                    : () => _inc(ScoreSide.home);

                                return Row(
                                  children: [
                                    Expanded(
                                      child: _ScoreHalf(
                                        background: leftBg,
                                        accent: leftAccent,
                                        label: leftLabel,
                                        score: leftScore,
                                        onInc: leftOnInc,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                    Expanded(
                                      child: _ScoreHalf(
                                        background: rightBg,
                                        accent: rightAccent,
                                        label: rightLabel,
                                        score: rightScore,
                                        onInc: rightOnInc,
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                // 위아래 배치 (위치 교체 안 함)
                                return Column(
                                  children: [
                                    Expanded(
                                      child: _ScoreHalf(
                                        background: homeBg,
                                        accent: homeAccent,
                                        label: 'Blue',
                                        score: _state!.scoreA,
                                        onInc: () => _inc(ScoreSide.home),
                                      ),
                                    ),
                                    Container(
                                      height: 1,
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.12,
                                      ),
                                    ),
                                    Expanded(
                                      child: _ScoreHalf(
                                        background: awayBg,
                                        accent: awayAccent,
                                        label: 'Red',
                                        score: _state!.scoreB,
                                        onInc: () => _inc(ScoreSide.away),
                                      ),
                                    ),
                                  ],
                                );
                              }
                            },
                          ),
                          // 세트 스코어 표시 (정중앙 플로팅) - 게임 점수와 유사한 디자인 (항상 표시)
                          Positioned.fill(
                            child: Center(
                              child: OrientationBuilder(
                                builder: (context, orientation) {
                                  // 점수판이 실제로 좌우 배치인지 확인
                                  final useRowLayout = _isRowLayout(
                                    context,
                                    orientation,
                                  );
                                  final isPortrait =
                                      orientation == Orientation.portrait;

                                  return _SetScoreDisplay(
                                    homeScore: _state!.setScoresA.fold<int>(
                                      0,
                                      (sum, score) => sum + score,
                                    ),
                                    awayScore: _state!.setScoresB.fold<int>(
                                      0,
                                      (sum, score) => sum + score,
                                    ),
                                    homeBg: homeBg,
                                    awayBg: awayBg,
                                    homeAccent: homeAccent,
                                    awayAccent: awayAccent,
                                    scheme: scheme,
                                    isPortrait: isPortrait,
                                    useRowLayout: useRowLayout,
                                    isBlueOnLeft: _isBlueOnLeft,
                                  );
                                },
                              ),
                            ),
                          ),
                          // 스톱워치 표시 (우측 하단 플로팅)
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: OrientationBuilder(
                              builder: (context, orientation) {
                                return _StopwatchDisplay(
                                  elapsedSeconds: _elapsedSeconds,
                                  isRunning: _isStopwatchRunning,
                                  onTap: _toggleStopwatch,
                                  onLongPress: _resetStopwatch,
                                  onReset: _resetStopwatch,
                                  scheme: scheme,
                                  isPortrait:
                                      orientation == Orientation.portrait,
                                );
                              },
                            ),
                          ),
                          // 가이드 버튼 (우측 하단 플로팅, 타이머 위)
                          Positioned(
                            right: 16,
                            bottom: 80,
                            child: GestureDetector(
                              onTap: () => _showGuideDialog(context, scheme),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.2,
                                    ),
                                    width: 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.help_outline,
                                  color: scheme.primary,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                          // 카메라 녹화 버튼 (좌측 하단 플로팅)
                          Positioned(
                            left: 16,
                            bottom: 16,
                            child: _CameraControlButtons(
                              isCameraInitialized: _isCameraInitialized,
                              showPreview: _isCameraPreviewVisible,
                              isRecording: _isRecording,
                              onShowPreview: _showCameraPreview,
                              onStartRecording: _startRecording,
                              onStopRecording: _stopRecording,
                              scheme: scheme,
                            ),
                          ),
                          // 우측 중앙 스와이프 힌트 (문고리)
                          Positioned(
                            right: 8,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.chevron_right,
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.5,
                                  ),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // 세트 히스토리 화면
                _SetHistoryPage(
                  state: _state!,
                  homeBg: homeBg,
                  awayBg: awayBg,
                  homeAccent: homeAccent,
                  awayAccent: awayAccent,
                  scheme: scheme,
                ),
              ],
            ),
            // 스와이프 가이드 오버레이
            if (_showSwipeGuide)
              _SwipeGuideOverlay(onDismiss: _hideSwipeGuide, scheme: scheme),
            // 카메라 미리보기 오버레이
            if (_isCameraPreviewVisible && _cameraController != null)
              _CameraPreviewOverlay(
                cameraController: _cameraController!,
                onDismiss: _hideCameraPreview,
                onGestureDetected: _resetCameraPreviewTimer,
                onSwitchCamera: _switchCamera,
                currentCameraDirection: _currentCameraDirection,
                scheme: scheme,
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreHalf extends StatelessWidget {
  final Color background;
  final Color accent;
  final String label;
  final int score;
  final VoidCallback onInc;

  const _ScoreHalf({
    required this.background,
    required this.accent,
    required this.label,
    required this.score,
    required this.onInc,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBg = theme.colorScheme.onSurface;

    // 전형적인 점수판 느낌: 해당 팀 영역을 "위(+)" / "아래(비활성)"로 크게 나눠
    // 디자인은 유지하되 하단은 터치 비활성화
    final plusBg = accent.withValues(alpha: 0.10);
    final minusBg = Colors.black.withValues(alpha: 0.18);

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Stack(
          children: [
            // 전체 터치 영역 (상: + / 하: +) - 디자인은 상하 구분 유지
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: [
                    Expanded(
                      child: _TouchZone(
                        onTap: onInc,
                        background: plusBg,
                        splashColor: accent.withValues(alpha: 0.20),
                        semanticLabel: '$label +1',
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 14, right: 14),
                            child: Icon(Icons.add, color: accent, size: 44),
                          ),
                        ),
                      ),
                    ),
                    // 가운데 구분선 (대비)
                    Container(height: 1, color: onBg.withValues(alpha: 0.18)),
                    Expanded(
                      child: _TouchZone(
                        onTap: onInc,
                        background: minusBg,
                        splashColor: accent.withValues(alpha: 0.14),
                        semanticLabel: '$label +1',
                        child: Container(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 좌측 라벨(항상 보이도록 오버레이)
            Positioned(
              left: 14,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.55),
                    width: 1,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

            // 중앙 점수(큰 글씨) - 클릭해도 + 버튼 동작
            Positioned.fill(
              child: GestureDetector(
                onTap: onInc,
                behavior: HitTestBehavior.translucent,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$score',
                      style: TextStyle(
                        color: onBg.withValues(alpha: 0.96),
                        fontSize: 260,
                        fontWeight: FontWeight.w900,
                        height: 0.95,
                        letterSpacing: -3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetScoreDisplay extends StatelessWidget {
  final int homeScore;
  final int awayScore;
  final Color homeBg;
  final Color awayBg;
  final Color homeAccent;
  final Color awayAccent;
  final ColorScheme scheme;
  final bool isPortrait;
  final bool useRowLayout;
  final bool isBlueOnLeft;

  const _SetScoreDisplay({
    required this.homeScore,
    required this.awayScore,
    required this.homeBg,
    required this.awayBg,
    required this.homeAccent,
    required this.awayAccent,
    required this.scheme,
    required this.isPortrait,
    required this.useRowLayout,
    required this.isBlueOnLeft,
  });

  Widget _buildScoreCell({
    required int score,
    required Color bgColor,
    required Color accentColor,
    required List<Radius> borderRadius,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.only(
          topLeft: borderRadius[0],
          topRight: borderRadius[1],
          bottomRight: borderRadius[2],
          bottomLeft: borderRadius[3],
        ),
      ),
      child: Center(
        child: Text(
          '$score',
          style: TextStyle(
            color: accentColor,
            fontSize: 40,
            fontWeight: FontWeight.w900,
            height: 0.95,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: isPortrait ? null : 110,
      height: isPortrait ? 115 : 90,
      constraints: isPortrait
          ? const BoxConstraints(minWidth: 70, maxWidth: 110)
          : null,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: isPortrait
          ? IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HOME 세트 스코어
                  Expanded(
                    child: _buildScoreCell(
                      score: homeScore,
                      bgColor: homeBg,
                      accentColor: homeAccent,
                      borderRadius: const [
                        Radius.circular(12),
                        Radius.circular(12),
                        Radius.circular(0),
                        Radius.circular(0),
                      ],
                    ),
                  ),
                  // 구분선
                  Container(
                    height: 1,
                    color: scheme.onSurface.withValues(alpha: 0.12),
                  ),
                  // AWAY 세트 스코어
                  Expanded(
                    child: _buildScoreCell(
                      score: awayScore,
                      bgColor: awayBg,
                      accentColor: awayAccent,
                      borderRadius: const [
                        Radius.circular(0),
                        Radius.circular(0),
                        Radius.circular(12),
                        Radius.circular(12),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : useRowLayout
          ? Row(
              children: [
                // 좌우 배치: isBlueOnLeft에 따라 블루/레드 위치 결정
                Expanded(
                  child: _buildScoreCell(
                    score: isBlueOnLeft ? homeScore : awayScore,
                    bgColor: isBlueOnLeft ? homeBg : awayBg,
                    accentColor: isBlueOnLeft ? homeAccent : awayAccent,
                    borderRadius: const [
                      Radius.circular(12),
                      Radius.circular(0),
                      Radius.circular(0),
                      Radius.circular(12),
                    ],
                  ),
                ),
                // 구분선
                Container(
                  width: 1,
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
                // 우측 세트 스코어
                Expanded(
                  child: _buildScoreCell(
                    score: isBlueOnLeft ? awayScore : homeScore,
                    bgColor: isBlueOnLeft ? awayBg : homeBg,
                    accentColor: isBlueOnLeft ? awayAccent : homeAccent,
                    borderRadius: const [
                      Radius.circular(0),
                      Radius.circular(12),
                      Radius.circular(12),
                      Radius.circular(0),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                // 위아래 배치일 때는 기본 순서 유지
                Expanded(
                  child: _buildScoreCell(
                    score: homeScore,
                    bgColor: homeBg,
                    accentColor: homeAccent,
                    borderRadius: const [
                      Radius.circular(12),
                      Radius.circular(0),
                      Radius.circular(0),
                      Radius.circular(12),
                    ],
                  ),
                ),
                // 구분선
                Container(
                  width: 1,
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
                // AWAY 세트 스코어
                Expanded(
                  child: _buildScoreCell(
                    score: awayScore,
                    bgColor: awayBg,
                    accentColor: awayAccent,
                    borderRadius: const [
                      Radius.circular(0),
                      Radius.circular(12),
                      Radius.circular(12),
                      Radius.circular(0),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SwipeGuideOverlay extends StatelessWidget {
  final VoidCallback onDismiss;
  final ColorScheme scheme;

  const _SwipeGuideOverlay({required this.onDismiss, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 화살표 아이콘
              Icon(Icons.swipe_left, color: scheme.primary, size: 64),
              const SizedBox(height: 24),
              // 텍스트
              Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context);
                  if (l10n == null) return const SizedBox.shrink();
                  return Text(
                    l10n.swipeGuideMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              // 닫기 버튼
              Builder(
                builder: (context) {
                  final l10n = AppLocalizations.of(context);
                  if (l10n == null) return const SizedBox.shrink();
                  return ElevatedButton(
                    onPressed: onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.ok,
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetHistoryPage extends StatelessWidget {
  final MatchState state;
  final Color homeBg;
  final Color awayBg;
  final Color homeAccent;
  final Color awayAccent;
  final ColorScheme scheme;

  const _SetHistoryPage({
    required this.state,
    required this.homeBg,
    required this.awayBg,
    required this.homeAccent,
    required this.awayAccent,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    const baseBg = Color(0xFF0B1220);

    return Container(
      color: baseBg,
      child: Stack(
        children: [
          Column(
            children: [
              // 헤더
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.history,
                      color: scheme.onSurface.withValues(alpha: 0.9),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Builder(
                      builder: (context) {
                        final l10n = AppLocalizations.of(context);
                        return Text(
                          l10n?.setHistory ?? '세트 히스토리',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.9),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // 테이블
              Expanded(
                child: Builder(
                  builder: (context) {
                    final history = state.setHistory;
                    if (history.isEmpty) {
                      final l10n = AppLocalizations.of(context);
                      return Center(
                        child: Text(
                          l10n?.noCompletedSets ?? '완료된 세트가 없습니다',
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                        ),
                      );
                    }
                    return SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Table(
                          border: TableBorder(
                            horizontalInside: BorderSide(
                              color: scheme.onSurface.withValues(alpha: 0.1),
                              width: 1,
                            ),
                            top: BorderSide(
                              color: scheme.onSurface.withValues(alpha: 0.1),
                              width: 1,
                            ),
                            bottom: BorderSide(
                              color: scheme.onSurface.withValues(alpha: 0.1),
                              width: 1,
                            ),
                          ),
                          columnWidths: const {
                            0: FlexColumnWidth(1),
                            1: FlexColumnWidth(2),
                            2: FlexColumnWidth(2),
                            3: FlexColumnWidth(2),
                          },
                          children: [
                            // 헤더 행
                            TableRow(
                              decoration: BoxDecoration(
                                color: scheme.onSurface.withValues(alpha: 0.05),
                              ),
                              children: [
                                Builder(
                                  builder: (context) {
                                    final l10n = AppLocalizations.of(context);
                                    return _buildTableCell(
                                      l10n?.set ?? '세트',
                                      scheme,
                                      isHeader: true,
                                    );
                                  },
                                ),
                                _buildTableCell(
                                  'Blue',
                                  scheme,
                                  isHeader: true,
                                  accent: homeAccent,
                                ),
                                _buildTableCell(
                                  'Red',
                                  scheme,
                                  isHeader: true,
                                  accent: awayAccent,
                                ),
                                Builder(
                                  builder: (context) {
                                    final l10n = AppLocalizations.of(context);
                                    return _buildTableCell(
                                      l10n?.winner ?? '승자',
                                      scheme,
                                      isHeader: true,
                                    );
                                  },
                                ),
                              ],
                            ),
                            // 데이터 행
                            ...history.map((setScore) {
                              final winner = setScore.scoreA > setScore.scoreB
                                  ? 'Blue'
                                  : setScore.scoreB > setScore.scoreA
                                  ? 'Red'
                                  : '-';
                              final winnerColor =
                                  setScore.scoreA > setScore.scoreB
                                  ? homeAccent
                                  : setScore.scoreB > setScore.scoreA
                                  ? awayAccent
                                  : scheme.onSurface.withValues(alpha: 0.5);

                              return TableRow(
                                children: [
                                  _buildTableCell(
                                    '${setScore.setNumber}',
                                    scheme,
                                  ),
                                  _buildTableCell(
                                    '${setScore.scoreA}',
                                    scheme,
                                    accent: homeAccent,
                                  ),
                                  _buildTableCell(
                                    '${setScore.scoreB}',
                                    scheme,
                                    accent: awayAccent,
                                  ),
                                  _buildTableCell(
                                    winner,
                                    scheme,
                                    accent: winnerColor,
                                    isBold: true,
                                  ),
                                ],
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 하단 세트 스코어 요약 표시
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.onSurface.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // 총 세트 스코어 라벨
                    Text(
                      '총 세트 스코어',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Blue 총점
                    Row(
                      children: [
                        Text(
                          'Blue',
                          style: TextStyle(
                            color: homeAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${state.setScoresA.fold<int>(0, (sum, score) => sum + score)}',
                          style: TextStyle(
                            color: homeAccent,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      color: scheme.onSurface.withValues(alpha: 0.2),
                    ),
                    // Red 총점
                    Row(
                      children: [
                        Text(
                          'Red',
                          style: TextStyle(
                            color: awayAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${state.setScoresB.fold<int>(0, (sum, score) => sum + score)}',
                          style: TextStyle(
                            color: awayAccent,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 좌측 중앙 스와이프 힌트 (문고리)
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.chevron_left,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(
    String text,
    ColorScheme scheme, {
    Color? accent,
    bool isHeader = false,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color:
              accent ??
              scheme.onSurface.withValues(alpha: isHeader ? 0.9 : 0.8),
          fontSize: isHeader ? 14 : 16,
          fontWeight: isHeader || isBold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _ResetConfirmDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const _ResetConfirmDialog({required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();
    const baseBg = Color(0xFF0B1220);

    return Dialog(
      backgroundColor: baseBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.onSurface.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.restart_alt, color: scheme.error, size: 32),
            ),
            const SizedBox(height: 20),
            // 제목
            Text(
              l10n.resetTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            // 메시지
            Text(
              l10n.resetMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.8),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // 버튼들
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: scheme.onSurface.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Text(
                      l10n.resetCancel,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.9),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.error,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.resetConfirm,
                      style: TextStyle(
                        color: scheme.onError,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TouchZone extends StatelessWidget {
  final VoidCallback onTap;
  final Color background;
  final Color splashColor;
  final Widget child;
  final String semanticLabel;

  const _TouchZone({
    required this.onTap,
    required this.background,
    required this.splashColor,
    required this.child,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: background,
        child: InkWell(
          onTap: onTap,
          splashColor: splashColor,
          highlightColor: splashColor.withValues(alpha: 0.45),
          child: child,
        ),
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  final GameRules rules;
  final String currentLocale;
  final bool autoSwapEnabled;
  final void Function(GameRules) onSave;
  final void Function(String) onLocaleChanged;
  final void Function(bool) onAutoSwapChanged;

  const _SettingsDialog({
    required this.rules,
    required this.currentLocale,
    required this.autoSwapEnabled,
    required this.onSave,
    required this.onLocaleChanged,
    required this.onAutoSwapChanged,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late TextEditingController _maxScoreController;
  late bool _deuceEnabled;
  late TextEditingController _deuceMarginController;
  late bool _autoSwapEnabled;

  @override
  void initState() {
    super.initState();
    _maxScoreController = TextEditingController(
      text: widget.rules.maxScore.toString(),
    );
    _deuceEnabled = widget.rules.deuceEnabled;
    _deuceMarginController = TextEditingController(
      text: widget.rules.deuceMargin.toString(),
    );
    _autoSwapEnabled = widget.autoSwapEnabled;
  }

  @override
  void dispose() {
    _maxScoreController.dispose();
    _deuceMarginController.dispose();
    super.dispose();
  }

  void _save() {
    final maxScore = int.tryParse(_maxScoreController.text) ?? 11;
    final deuceMargin = int.tryParse(_deuceMarginController.text) ?? 2;

    final rules = widget.rules.copyWith(
      maxScore: maxScore.clamp(1, 99),
      deuceEnabled: _deuceEnabled,
      deuceMargin: deuceMargin.clamp(1, 10),
    );

    widget.onSave(rules);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();

    return AlertDialog(
      backgroundColor: const Color(0xFF0B1220),
      title: Text(l10n.gameSettings, style: TextStyle(color: scheme.onSurface)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 언어 설정
            Text(
              l10n.language,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...AppLocale.values.map((locale) {
              return RadioListTile<String>(
                title: Text(locale.displayName),
                value: locale.code,
                groupValue: widget.currentLocale,
                onChanged: (value) {
                  if (value != null) {
                    widget.onLocaleChanged(value);
                  }
                },
                activeColor: scheme.primary,
                contentPadding: EdgeInsets.zero,
              );
            }),
            const SizedBox(height: 24),
            // 게임 규칙
            Text(
              l10n.gameRules,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _maxScoreController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: scheme.onSurface),
              decoration: InputDecoration(
                labelText: l10n.maxScore,
                labelStyle: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: scheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: scheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: scheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 듀스 규칙
            Row(
              children: [
                Checkbox(
                  value: _deuceEnabled,
                  onChanged: (value) {
                    setState(() {
                      _deuceEnabled = value ?? false;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    l10n.deuceEnabled,
                    style: TextStyle(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
            if (_deuceEnabled) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _deuceMarginController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: scheme.onSurface),
                decoration: InputDecoration(
                  labelText: l10n.deuceMargin,
                  labelStyle: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: scheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: scheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: scheme.primary),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            // 좌우 반전 설정
            Text(
              '화면 설정',
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Checkbox(
                  value: _autoSwapEnabled,
                  onChanged: (value) {
                    setState(() {
                      _autoSwapEnabled = value ?? false;
                    });
                    widget.onAutoSwapChanged(_autoSwapEnabled);
                  },
                ),
                Expanded(
                  child: Text(
                    '게임 종료 시 자동 위치 교체',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            l10n.resetCancel,
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
          ),
        ),
        TextButton(
          onPressed: _save,
          child: Text(l10n.save, style: TextStyle(color: scheme.primary)),
        ),
      ],
    );
  }
}

class _CameraControlButtons extends StatelessWidget {
  final bool isCameraInitialized;
  final bool showPreview;
  final bool isRecording;
  final VoidCallback onShowPreview;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final ColorScheme scheme;

  const _CameraControlButtons({
    required this.isCameraInitialized,
    required this.showPreview,
    required this.isRecording,
    required this.onShowPreview,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCameraInitialized) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 미리보기 버튼
        if (!showPreview)
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.onSurface.withValues(alpha: 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: onShowPreview,
              icon: Icon(
                Icons.videocam,
                color: scheme.onSurface.withValues(alpha: 0.9),
                size: 20,
              ),
              tooltip: '미리보기',
            ),
          ),
        // 녹화 버튼
        GestureDetector(
          onTap: isRecording ? onStopRecording : onStartRecording,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isRecording
                  ? scheme.error
                  : Colors.black.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(
                color: isRecording
                    ? scheme.error
                    : scheme.onSurface.withValues(alpha: 0.2),
                width: isRecording ? 3 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              isRecording ? Icons.stop : Icons.fiber_manual_record,
              color: isRecording ? Colors.white : scheme.error,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }
}

class _CameraPreviewOverlay extends StatefulWidget {
  final CameraController cameraController;
  final VoidCallback onDismiss;
  final VoidCallback onGestureDetected;
  final VoidCallback onSwitchCamera;
  final CameraLensDirection currentCameraDirection;
  final ColorScheme scheme;

  const _CameraPreviewOverlay({
    required this.cameraController,
    required this.onDismiss,
    required this.onGestureDetected,
    required this.onSwitchCamera,
    required this.currentCameraDirection,
    required this.scheme,
  });

  @override
  State<_CameraPreviewOverlay> createState() => _CameraPreviewOverlayState();
}

class _CameraPreviewOverlayState extends State<_CameraPreviewOverlay> {
  double _currentZoomLevel = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 1.0;
  double _baseScale = 1.0;
  bool _isZoomSliderVisible = false;
  Size? _cameraPreviewSize;

  @override
  void initState() {
    super.initState();
    _initializeZoom();
    _updateCameraPreviewSize();
    // 카메라 값이 변경될 때마다 비율 업데이트
    widget.cameraController.addListener(_updateCameraPreviewSize);
    // 초기화 후 비율 다시 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateCameraPreviewSize();
    });
  }

  @override
  void dispose() {
    widget.cameraController.removeListener(_updateCameraPreviewSize);
    super.dispose();
  }

  void _updateCameraPreviewSize() {
    try {
      final cameraValue = widget.cameraController.value;
      final previewSize = cameraValue.previewSize;

      if (previewSize != null && previewSize.height > 0) {
        if (_cameraPreviewSize != previewSize) {
          setState(() {
            _cameraPreviewSize = previewSize;
          });
        }
      }
    } catch (e) {
      // Error updating camera preview size
    }
  }

  Future<void> _initializeZoom() async {
    try {
      _minZoomLevel = await widget.cameraController.getMinZoomLevel();
      _maxZoomLevel = await widget.cameraController.getMaxZoomLevel();
      // 초기 줌 레벨은 최소값으로 설정
      _currentZoomLevel = _minZoomLevel;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Failed to get zoom levels: $e');
      // 기본값 설정
      _minZoomLevel = 1.0;
      _maxZoomLevel = 1.0;
      _currentZoomLevel = 1.0;
    }
  }

  Future<void> _setZoomLevel(double zoom) async {
    try {
      final clampedZoom = zoom.clamp(_minZoomLevel, _maxZoomLevel);
      await widget.cameraController.setZoomLevel(clampedZoom);
      if (mounted) {
        setState(() {
          _currentZoomLevel = clampedZoom;
        });
      }
    } catch (e) {
      print('Failed to set zoom level: $e');
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentZoomLevel;
    // 제스처 시작 시 타이머 초기화
    widget.onGestureDetected();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final newZoom = _baseScale * details.scale;
    _setZoomLevel(newZoom);
    // 제스처 업데이트 시 타이머 초기화
    widget.onGestureDetected();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      behavior: HitTestBehavior.translucent,
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              onTap: () {
                // 미리보기 영역 터치 시 줌 슬라이더 토글 및 타이머 초기화
                widget.onGestureDetected();
                setState(() {
                  _isZoomSliderVisible = !_isZoomSliderVisible;
                });
              },
              onScaleStart: _handleScaleStart,
              onScaleUpdate: _handleScaleUpdate,
              child: OrientationBuilder(
                builder: (context, orientation) {
                  // 카메라의 실제 previewSize 가져오기
                  final cameraValue = widget.cameraController.value;
                  final previewSize = cameraValue.previewSize;

                  double aspectRatio = 16 / 9; // 기본값
                  if (previewSize != null && previewSize.height > 0) {
                    aspectRatio = previewSize.width / previewSize.height;
                  }

                  // 화면 크기에 맞춰 너비 기준으로 계산
                  final screenSize = MediaQuery.of(context).size;
                  final isPortrait = orientation == Orientation.portrait;

                  // 세로 모드에서는 카메라가 회전되므로 비율을 반대로 적용
                  final displayAspectRatio = isPortrait
                      ? (1 / aspectRatio)
                      : aspectRatio;

                  // 너비를 먼저 정하고 (화면 너비의 80%)
                  final containerWidth = screenSize.width * 0.8;

                  // 카메라 비율에 맞춰 높이 자동 계산 (세로 모드에서는 반대 비율 사용)
                  final containerHeight = containerWidth / displayAspectRatio;

                  // 화면 높이를 초과하지 않도록 제한 (최대 화면 높이의 80%)
                  final maxHeight = screenSize.height * 0.8;

                  final finalWidth = containerHeight > maxHeight
                      ? maxHeight *
                            displayAspectRatio // 높이가 너무 크면 높이 기준으로 너비 조정
                      : containerWidth;
                  final finalHeight = containerHeight > maxHeight
                      ? maxHeight
                      : containerHeight;

                  return Container(
                    width: finalWidth,
                    height: finalHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: widget.scheme.onSurface.withValues(alpha: 0.3),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // 카메라 미리보기 (카메라 비율 유지)
                        Positioned.fill(
                          child: AspectRatio(
                            aspectRatio: aspectRatio,
                            child: CameraPreview(widget.cameraController),
                          ),
                        ),
                        // 닫기 버튼
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: widget.onDismiss,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        // 카메라 전환 버튼
                        Positioned(
                          top: 8,
                          left: 8,
                          child: GestureDetector(
                            onTap: () {
                              widget.onGestureDetected();
                              widget.onSwitchCamera();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.currentCameraDirection ==
                                        CameraLensDirection.front
                                    ? Icons.camera_rear
                                    : Icons.camera_front,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        // 줌 슬라이더
                        if (_isZoomSliderVisible ||
                            _maxZoomLevel > _minZoomLevel)
                          Positioned(
                            right: 16,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: Container(
                                width: 40,
                                height: 200,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: Slider(
                                    value: _currentZoomLevel,
                                    min: _minZoomLevel,
                                    max: _maxZoomLevel,
                                    onChanged: (value) {
                                      _setZoomLevel(value);
                                    },
                                    activeColor: widget.scheme.primary,
                                    inactiveColor: widget.scheme.onSurface
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // 줌 레벨 표시
                        if (_isZoomSliderVisible)
                          Positioned(
                            bottom: 16,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_currentZoomLevel.toStringAsFixed(1)}x',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StopwatchDisplay extends StatelessWidget {
  final int elapsedSeconds;
  final bool isRunning;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onReset;
  final ColorScheme scheme;
  final bool isPortrait;

  const _StopwatchDisplay({
    required this.elapsedSeconds,
    required this.isRunning,
    required this.onTap,
    required this.onLongPress,
    required this.onReset,
    required this.scheme,
    required this.isPortrait,
  });

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isRunning
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.onSurface.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 아이콘
            Icon(
              isRunning ? Icons.pause : Icons.play_arrow,
              color: isRunning
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.7),
              size: 16,
            ),
            const SizedBox(width: 8),
            // 시간 표시
            Text(
              _formatTime(elapsedSeconds),
              style: TextStyle(
                color: isRunning
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.9),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            // 초기화 버튼 (시간이 0보다 크고 실행 중이 아닐 때만 표시)
            if (elapsedSeconds > 0 && !isRunning) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onReset,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.refresh,
                    size: 14,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GuideDialog extends StatelessWidget {
  final ColorScheme scheme;

  const _GuideDialog({required this.scheme});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return const SizedBox.shrink();
    return Dialog(
      backgroundColor: const Color(0xFF0B1220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.help_outline, color: scheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    l10n.guideTitle,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 내용
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 앱 사용법 섹션
                    _GuideSection(
                      title: l10n.guideAppSection,
                      scheme: scheme,
                      items: [
                        _GuideItem(
                          icon: Icons.touch_app,
                          title: l10n.guideAppScoreIncrement,
                          description: l10n.guideAppScoreIncrementDesc,
                        ),
                        _GuideItem(
                          icon: Icons.undo,
                          title: l10n.guideAppUndo,
                          description: l10n.guideAppUndoDesc,
                        ),
                        _GuideItem(
                          icon: Icons.restart_alt,
                          title: l10n.guideAppReset,
                          description: l10n.guideAppResetDesc,
                        ),
                        _GuideItem(
                          icon: Icons.swipe_right,
                          title: l10n.guideAppSetHistory,
                          description: l10n.guideAppSetHistoryDesc,
                        ),
                        _GuideItem(
                          icon: Icons.videocam,
                          title: l10n.guideAppVideoRecording,
                          description: l10n.guideAppVideoRecordingDesc,
                        ),
                        _GuideItem(
                          icon: Icons.timer,
                          title: l10n.guideAppStopwatch,
                          description: l10n.guideAppStopwatchDesc,
                        ),
                        _GuideItem(
                          icon: Icons.settings,
                          title: l10n.guideAppSettings,
                          description: l10n.guideAppSettingsDesc,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // 워치 사용법 섹션
                    _GuideSection(
                      title: l10n.guideWatchSection,
                      scheme: scheme,
                      items: [
                        _GuideItem(
                          icon: Icons.touch_app,
                          title: l10n.guideWatchScoreIncrement,
                          description: l10n.guideWatchScoreIncrementDesc,
                        ),
                        _GuideItem(
                          icon: Icons.undo,
                          title: l10n.guideWatchUndo,
                          description: l10n.guideWatchUndoDesc,
                        ),
                        _GuideItem(
                          icon: Icons.restart_alt,
                          title: l10n.guideWatchReset,
                          description: l10n.guideWatchResetDesc,
                        ),
                        _GuideItem(
                          icon: Icons.mic,
                          title: l10n.guideWatchVoice,
                          description: l10n.guideWatchVoiceDesc,
                        ),
                        _GuideItem(
                          icon: Icons.screen_lock_portrait,
                          title: l10n.guideWatchAlwaysOn,
                          description: l10n.guideWatchAlwaysOnDesc,
                        ),
                        _GuideItem(
                          icon: Icons.sync,
                          title: l10n.guideWatchSync,
                          description: l10n.guideWatchSyncDesc,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // 닫기 버튼
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    l10n.ok,
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  final String title;
  final List<_GuideItem> items;
  final ColorScheme scheme;

  const _GuideSection({
    required this.title,
    required this.items,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.primary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _GuideItemWidget(item: item, scheme: scheme),
          ),
        ),
      ],
    );
  }
}

class _GuideItem {
  final IconData icon;
  final String title;
  final String description;

  const _GuideItem({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _GuideItemWidget extends StatelessWidget {
  final _GuideItem item;
  final ColorScheme scheme;

  const _GuideItemWidget({required this.item, required this.scheme});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(item.icon, color: scheme.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.description,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
