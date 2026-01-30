import 'match_state.dart';

enum CommandType { inc, dec, reset, undo }

class ScoreCommand {
  final String id;
  final String matchId;
  final CommandType type;
  final ScoreSide? side;
  final DateTime issuedAt;

  /// Where the command was initiated.
  final UpdatedBy issuedBy;

  /// Optional device identifier (watch/phone).
  final String? deviceId;

  const ScoreCommand({
    required this.id,
    required this.matchId,
    required this.type,
    required this.issuedAt,
    required this.issuedBy,
    this.side,
    this.deviceId,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'matchId': matchId,
        'type': type.name,
        'side': side?.name.toUpperCase(),
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'issuedBy': issuedBy.name,
        'deviceId': deviceId,
      };

  static ScoreCommand fromJson(Map<String, Object?> json) {
    final sideRaw = (json['side'] as String?)?.toLowerCase();
    final ScoreSide? side = switch (sideRaw) {
      null => null,
      // Backward compatibility
      'a' => ScoreSide.home,
      'b' => ScoreSide.away,
      // Preferred
      'home' => ScoreSide.home,
      'away' => ScoreSide.away,
      _ => null,
    };

    return ScoreCommand(
      id: json['id'] as String,
      matchId: json['matchId'] as String,
      type: CommandType.values.byName(json['type'] as String),
      side: side,
      issuedAt: DateTime.parse(
        (json['issuedAt'] as String?) ?? DateTime.now().toIso8601String(),
      ),
      issuedBy: UpdatedBy.values.byName(
        (json['issuedBy'] as String?) ?? UpdatedBy.watch.name,
      ),
      deviceId: json['deviceId'] as String?,
    );
  }
}

