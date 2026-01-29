/// Internal side identifier.
///
/// We use HOME/AWAY naming throughout the app and watch protocol.
enum ScoreSide { home, away }

enum UpdatedBy { phone, watch }

class MatchState {
  final String matchId;
  final String playerAName;
  final String playerBName;
  final int scoreA;
  final int scoreB;

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
        'version': version,
        'lastUpdatedAt': lastUpdatedAt.toUtc().toIso8601String(),
        'lastUpdatedBy': lastUpdatedBy.name,
      };

  static MatchState fromJson(Map<String, Object?> json) {
    return MatchState(
      matchId: json['matchId'] as String,
      playerAName: json['playerAName'] as String? ?? 'A',
      playerBName: json['playerBName'] as String? ?? 'B',
      scoreA: (json['scoreA'] as num?)?.toInt() ?? 0,
      scoreB: (json['scoreB'] as num?)?.toInt() ?? 0,
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

