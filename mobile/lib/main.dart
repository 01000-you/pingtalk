import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pingtalk_core/pingtalk_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'splash_screen.dart';

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

class PingTalkApp extends StatelessWidget {
  const PingTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PingTalk',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BFA5),
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashWrapper(),
    );
  }
}

class SplashWrapper extends StatefulWidget {
  const SplashWrapper({super.key});

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
          MaterialPageRoute(builder: (context) => const ScoreboardPage()),
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
  const ScoreboardPage({super.key});

  @override
  State<ScoreboardPage> createState() => _ScoreboardPageState();
}

class _ScoreboardPageState extends State<ScoreboardPage> {
  static const MethodChannel _watchChannel = MethodChannel('pingtalk/watch');
  static const String _prefsKeyState = 'match_state';
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

  @override
  void initState() {
    super.initState();
    // 초기 상태 설정
    _state = MatchState(
      matchId: 'local',
      playerAName: 'Home',
      playerBName: 'Away',
      scoreA: 0,
      scoreB: 0,
      version: 0,
      lastUpdatedAt: DateTime.now().toUtc(),
      lastUpdatedBy: UpdatedBy.phone,
    );
    _addToHistory(_state!);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _loadState();
    } catch (e) {
      // SharedPreferences 초기화 실패 시 기본값 사용
      // (플러그인이 아직 준비되지 않았을 수 있음)
    }
    _watchChannel.setMethodCallHandler(_onWatchMethodCall);
    setState(() {
      _isInitialized = true;
    });
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
    _methodCallSub?.cancel();
    super.dispose();
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
        
        _applyCommand(cmd, appliedBy: UpdatedBy.watch);
        await _pushStateToWatch();
        return;
      case 'ping':
        setState(() {
          _watchStatus = WatchConnectionStatus.connected;
        });
        // 연결 시 최신 상태를 워치로 전송
        await _pushStateToWatch();
        return;
      default:
        return;
    }
  }

  String _newCommandId() => 'cmd_${DateTime.now().microsecondsSinceEpoch}';

  void _applyCommand(ScoreCommand command, {required UpdatedBy appliedBy}) {
    if (_state == null) return;
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

    setState(() {
      _state = next;
      _watchStatus = WatchConnectionStatus.syncing;
    });
    
    // 히스토리에 추가
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

  void _showSettingsDialog(BuildContext context) {
    if (_state == null) return;
    
    showDialog(
      context: context,
      builder: (context) => _SettingsDialog(
        rules: _state!.rules,
        onSave: (rules) {
          setState(() {
            _state = _state!.copyWith(
              rules: rules,
            );
          });
          unawaited(_saveState());
          Navigator.of(context).pop();
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

  String _getWatchStatusText() {
    switch (_watchStatus) {
      case WatchConnectionStatus.disconnected:
        return '워치: 미연동';
      case WatchConnectionStatus.connecting:
        return '워치: 연결 중...';
      case WatchConnectionStatus.connected:
        return '워치: 연결됨';
      case WatchConnectionStatus.syncing:
        return '워치: 동기화 중...';
      case WatchConnectionStatus.synced:
        return '워치: 동기화됨(v${_state?.version ?? 0})';
      case WatchConnectionStatus.syncFailed:
        return '워치: 전송 실패';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 초기화 전이거나 상태가 없으면 로딩 표시
    if (!_isInitialized || _state == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 좌측 타이틀
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'PINGTALK',
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
                        tooltip: '되돌리기',
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
                        tooltip: '초기화',
                        icon: Icon(
                          Icons.restart_alt,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                      // 설정 버튼
                      IconButton(
                        onPressed: () => _showSettingsDialog(context),
                        tooltip: '설정',
                        icon: Icon(
                          Icons.settings,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),

                  // 우측 워치 상태 표시
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _getWatchStatusText(),
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
                      final isPortrait = orientation == Orientation.portrait;
                      
                      if (isPortrait) {
                        // 세로 모드: 상하 배치
                        return Column(
                          children: [
                            Expanded(
                              child: _ScoreHalf(
                                background: homeBg,
                                accent: homeAccent,
                                label: 'HOME',
                                score: _state!.scoreA,
                                onInc: () => _inc(ScoreSide.home),
                              ),
                            ),
                            Container(height: 1, color: scheme.onSurface.withValues(alpha: 0.12)),
                            Expanded(
                              child: _ScoreHalf(
                                background: awayBg,
                                accent: awayAccent,
                                label: 'AWAY',
                                score: _state!.scoreB,
                                onInc: () => _inc(ScoreSide.away),
                              ),
                            ),
                          ],
                        );
                      } else {
                        // 가로 모드: 좌우 배치
                        return Row(
                          children: [
                            Expanded(
                              child: _ScoreHalf(
                                background: homeBg,
                                accent: homeAccent,
                                label: 'HOME',
                                score: _state!.scoreA,
                                onInc: () => _inc(ScoreSide.home),
                              ),
                            ),
                            Container(width: 1, color: scheme.onSurface.withValues(alpha: 0.12)),
                            Expanded(
                              child: _ScoreHalf(
                                background: awayBg,
                                accent: awayAccent,
                                label: 'AWAY',
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
                          return _SetScoreDisplay(
                            homeScore: _state!.setScoresA.fold<int>(0, (sum, score) => sum + score),
                            awayScore: _state!.setScoresB.fold<int>(0, (sum, score) => sum + score),
                            homeBg: homeBg,
                            awayBg: awayBg,
                            homeAccent: homeAccent,
                            awayAccent: awayAccent,
                            scheme: scheme,
                            isPortrait: orientation == Orientation.portrait,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
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
                    Container(
                      height: 1,
                      color: onBg.withValues(alpha: 0.18),
                    ),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.55), width: 1),
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
                        fontSize: 280,
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

  const _SetScoreDisplay({
    required this.homeScore,
    required this.awayScore,
    required this.homeBg,
    required this.awayBg,
    required this.homeAccent,
    required this.awayAccent,
    required this.scheme,
    required this.isPortrait,
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
            fontSize: 32,
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
      width: isPortrait ? null : 100,
      height: isPortrait ? 103 : 80,
      constraints: isPortrait
          ? const BoxConstraints(
              minWidth: 60,
              maxWidth: 100,
            )
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
          : Row(
              children: [
                // HOME 세트 스코어
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

class _ResetConfirmDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const _ResetConfirmDialog({required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              child: Icon(
                Icons.restart_alt,
                color: scheme.error,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),
            // 제목
            Text(
              '모든 점수 초기화',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            // 메시지
            Text(
              '모든 점수와 세트 스코어, Undo 히스토리가 삭제됩니다.\n정말 초기화하시겠습니까?',
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
                      '취소',
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
                      '초기화',
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
  final void Function(GameRules) onSave;

  const _SettingsDialog({
    required this.rules,
    required this.onSave,
  });

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late TextEditingController _maxScoreController;
  late bool _deuceEnabled;
  late TextEditingController _deuceMarginController;

  @override
  void initState() {
    super.initState();
    _maxScoreController = TextEditingController(text: widget.rules.maxScore.toString());
    _deuceEnabled = widget.rules.deuceEnabled;
    _deuceMarginController = TextEditingController(text: widget.rules.deuceMargin.toString());
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
    
    return AlertDialog(
      backgroundColor: const Color(0xFF0B1220),
      title: Text(
        '게임 설정',
        style: TextStyle(color: scheme.onSurface),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 게임 규칙
            Text(
              '게임 규칙',
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
                labelText: '최대 점수',
                labelStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.3)),
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
                    '듀스 규칙 활성화',
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
                  labelText: '듀스 점수 차이',
                  labelStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: scheme.primary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7))),
        ),
        TextButton(
          onPressed: _save,
          child: Text('저장', style: TextStyle(color: scheme.primary)),
        ),
      ],
    );
  }
}
