/// Internal side identifier.
///
/// We use HOME/AWAY naming throughout the app and watch protocol.
enum ScoreSide { home, away }

enum UpdatedBy { phone, watch }

/// 게임 규칙 설정
class GameRules {
  /// 최대 점수 (예: 11점)
  final int maxScore;
  
  /// 듀스 규칙 활성화 여부
  final bool deuceEnabled;
  
  /// 듀스 시 필요한 점수 차이 (예: 2점)
  final int deuceMargin;

  const GameRules({
    this.maxScore = 11,
    this.deuceEnabled = true,
    this.deuceMargin = 2,
  });

  GameRules copyWith({
    int? maxScore,
    bool? deuceEnabled,
    int? deuceMargin,
  }) {
    return GameRules(
      maxScore: maxScore ?? this.maxScore,
      deuceEnabled: deuceEnabled ?? this.deuceEnabled,
      deuceMargin: deuceMargin ?? this.deuceMargin,
    );
  }

  Map<String, Object?> toJson() => {
        'maxScore': maxScore,
        'deuceEnabled': deuceEnabled,
        'deuceMargin': deuceMargin,
      };

  static GameRules fromJson(Map<String, Object?> json) {
    return GameRules(
      maxScore: (json['maxScore'] as num?)?.toInt() ?? 11,
      deuceEnabled: json['deuceEnabled'] as bool? ?? true,
      deuceMargin: (json['deuceMargin'] as num?)?.toInt() ?? 2,
    );
  }
}

class MatchState {
  final String matchId;
  final String playerAName;
  final String playerBName;
  final int scoreA;
  final int scoreB;

  /// 세트 스코어 (각 세트의 승패 기록)
  /// 예: [1, 0] = A가 1세트, B가 0세트 승리
  final List<int> setScoresA;
  final List<int> setScoresB;

  /// 현재 세트 번호 (0부터 시작)
  final int currentSet;

  /// 게임 규칙
  final GameRules rules;

  /// Monotonic version number. Increment when state changes.
  final int version;

  final DateTime lastUpdatedAt;
  final UpdatedBy lastUpdatedBy;

  const MatchState({
    required this.matchId,
    required this.playerAName,
    required this.playerBName,
    required this.scoreA,
    required this.scoreB,
    this.setScoresA = const [],
    this.setScoresB = const [],
    this.currentSet = 0,
    this.rules = const GameRules(),
    required this.version,
    required this.lastUpdatedAt,
    required this.lastUpdatedBy,
  });

  MatchState copyWith({
    String? matchId,
    String? playerAName,
    String? playerBName,
    int? scoreA,
    int? scoreB,
    List<int>? setScoresA,
    List<int>? setScoresB,
    int? currentSet,
    GameRules? rules,
    int? version,
    DateTime? lastUpdatedAt,
    UpdatedBy? lastUpdatedBy,
  }) {
    return MatchState(
      matchId: matchId ?? this.matchId,
      playerAName: playerAName ?? this.playerAName,
      playerBName: playerBName ?? this.playerBName,
      scoreA: scoreA ?? this.scoreA,
      scoreB: scoreB ?? this.scoreB,
      setScoresA: setScoresA ?? this.setScoresA,
      setScoresB: setScoresB ?? this.setScoresB,
      currentSet: currentSet ?? this.currentSet,
      rules: rules ?? this.rules,
      version: version ?? this.version,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
    );
  }

  Map<String, Object?> toJson() => {
        'matchId': matchId,
        'playerAName': playerAName,
        'playerBName': playerBName,
        'scoreA': scoreA,
        'scoreB': scoreB,
        'setScoresA': setScoresA,
        'setScoresB': setScoresB,
        'currentSet': currentSet,
        'rules': rules.toJson(),
        'version': version,
        'lastUpdatedAt': lastUpdatedAt.toUtc().toIso8601String(),
        'lastUpdatedBy': lastUpdatedBy.name,
      };

  static MatchState fromJson(Map<String, Object?> json) {
    final setScoresARaw = json['setScoresA'];
    final setScoresBRaw = json['setScoresB'];
    
    List<int> parseSetScores(dynamic raw) {
      if (raw == null) return const [];
      if (raw is! List) return const [];
      try {
        return raw.map((e) => (e as num).toInt()).toList();
      } catch (_) {
        return const [];
      }
    }
    
    return MatchState(
      matchId: json['matchId'] as String? ?? 'local',
      playerAName: json['playerAName'] as String? ?? 'A',
      playerBName: json['playerBName'] as String? ?? 'B',
      scoreA: (json['scoreA'] as num?)?.toInt() ?? 0,
      scoreB: (json['scoreB'] as num?)?.toInt() ?? 0,
      setScoresA: parseSetScores(setScoresARaw),
      setScoresB: parseSetScores(setScoresBRaw),
      currentSet: (json['currentSet'] as num?)?.toInt() ?? 0,
      rules: json['rules'] != null && json['rules'] is Map
          ? GameRules.fromJson(json['rules'] as Map<String, Object?>)
          : const GameRules(),
      version: (json['version'] as num?)?.toInt() ?? 0,
      lastUpdatedAt: DateTime.parse(
        (json['lastUpdatedAt'] as String?) ?? DateTime.now().toIso8601String(),
      ),
      lastUpdatedBy: UpdatedBy.values.byName(
        (json['lastUpdatedBy'] as String?) ?? UpdatedBy.phone.name,
      ),
    );
  }
}

