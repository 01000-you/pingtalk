import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pingtalk_core/pingtalk_core.dart';

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
      home: const ScoreboardPage(),
    );
  }
}

class ScoreboardPage extends StatefulWidget {
  const ScoreboardPage({super.key});

  @override
  State<ScoreboardPage> createState() => _ScoreboardPageState();
}

class _ScoreboardPageState extends State<ScoreboardPage> {
  static const MethodChannel _watchChannel = MethodChannel('pingtalk/watch');

  late MatchState _state;
  String _watchStatus = '워치: 미연동';
  StreamSubscription<dynamic>? _methodCallSub;

  @override
  void initState() {
    super.initState();

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

    _watchChannel.setMethodCallHandler(_onWatchMethodCall);
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
        _applyCommand(cmd, appliedBy: UpdatedBy.watch);
        await _pushStateToWatch();
        return;
      case 'ping':
        setState(() => _watchStatus = '워치: 연결됨');
        return;
      default:
        return;
    }
  }

  String _newCommandId() => 'cmd_${DateTime.now().microsecondsSinceEpoch}';

  void _applyCommand(ScoreCommand command, {required UpdatedBy appliedBy}) {
    final next = ScoreReducer.apply(
      current: _state,
      command: command,
      appliedAt: DateTime.now().toUtc(),
      appliedBy: appliedBy,
    );
    if (identical(next, _state)) return;

    setState(() {
      _state = next;
      _watchStatus = '워치: 상태 전송 대기';
    });
  }

  Future<void> _pushStateToWatch() async {
    try {
      await _watchChannel.invokeMethod('state', _state.toJson());
      if (!mounted) return;
      setState(() => _watchStatus = '워치: 동기화됨(v${_state.version})');
    } catch (_) {
      if (!mounted) return;
      setState(() => _watchStatus = '워치: 전송 실패(미연결?)');
    }
  }

  void _inc(ScoreSide side) {
    _applyCommand(
      ScoreCommand(
        id: _newCommandId(),
        matchId: _state.matchId,
        type: CommandType.inc,
        side: side,
        issuedAt: DateTime.now().toUtc(),
        issuedBy: UpdatedBy.phone,
      ),
      appliedBy: UpdatedBy.phone,
    );
    unawaited(_pushStateToWatch());
  }

  void _dec(ScoreSide side) {
    _applyCommand(
      ScoreCommand(
        id: _newCommandId(),
        matchId: _state.matchId,
        type: CommandType.dec,
        side: side,
        issuedAt: DateTime.now().toUtc(),
        issuedBy: UpdatedBy.phone,
      ),
      appliedBy: UpdatedBy.phone,
    );
    unawaited(_pushStateToWatch());
  }

  void _reset() {
    _applyCommand(
      ScoreCommand(
        id: _newCommandId(),
        matchId: _state.matchId,
        type: CommandType.reset,
        issuedAt: DateTime.now().toUtc(),
        issuedBy: UpdatedBy.phone,
      ),
      appliedBy: UpdatedBy.phone,
    );
    unawaited(_pushStateToWatch());
  }

  @override
  Widget build(BuildContext context) {
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

                  // 중앙 리셋 버튼
                  IconButton(
                    onPressed: _reset,
                    tooltip: '초기화',
                    icon: Icon(
                      Icons.restart_alt,
                      color: scheme.onSurface.withValues(alpha: 0.9),
                    ),
                  ),

                  // 우측 워치 상태 표시
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _watchStatus,
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
              child: OrientationBuilder(
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
                            score: _state.scoreA,
                            onInc: () => _inc(ScoreSide.home),
                            onDec: () => _dec(ScoreSide.home),
                          ),
                        ),
                        Container(height: 1, color: scheme.onSurface.withValues(alpha: 0.12)),
                        Expanded(
                          child: _ScoreHalf(
                            background: awayBg,
                            accent: awayAccent,
                            label: 'AWAY',
                            score: _state.scoreB,
                            onInc: () => _inc(ScoreSide.away),
                            onDec: () => _dec(ScoreSide.away),
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
                            score: _state.scoreA,
                            onInc: () => _inc(ScoreSide.home),
                            onDec: () => _dec(ScoreSide.home),
                          ),
                        ),
                        Container(width: 1, color: scheme.onSurface.withValues(alpha: 0.12)),
                        Expanded(
                          child: _ScoreHalf(
                            background: awayBg,
                            accent: awayAccent,
                            label: 'AWAY',
                            score: _state.scoreB,
                            onInc: () => _inc(ScoreSide.away),
                            onDec: () => _dec(ScoreSide.away),
                          ),
                        ),
                      ],
                    );
                  }
                },
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
  final VoidCallback onDec;

  const _ScoreHalf({
    required this.background,
    required this.accent,
    required this.label,
    required this.score,
    required this.onInc,
    required this.onDec,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBg = theme.colorScheme.onSurface;

    // 전형적인 점수판 느낌: 해당 팀 영역을 "위(+)" / "아래(-)"로 크게 나눠
    // 각 절반 전체가 터치 영역이 되도록 구성.
    final plusBg = accent.withValues(alpha: 0.10);
    final minusBg = Colors.black.withValues(alpha: 0.18);

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Stack(
          children: [
            // 전체 터치 영역 (상: + / 하: -)
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
                        onTap: onDec,
                        background: minusBg,
                        splashColor: accent.withValues(alpha: 0.14),
                        semanticLabel: '$label -1',
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 14, right: 14),
                            child: Icon(Icons.remove, color: accent, size: 44),
                          ),
                        ),
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

            // 중앙 점수(큰 글씨)
            Positioned.fill(
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
