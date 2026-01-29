import '../models/match_state.dart';
import '../models/score_command.dart';

class ScoreReducer {
  /// Applies a command to the current match state.
  ///
  /// Notes:
  /// - Scores are clamped at >= 0.
  /// - `version` increments only when a state change occurs.
  static MatchState apply({
    required MatchState current,
    required ScoreCommand command,
    required DateTime appliedAt,
    required UpdatedBy appliedBy,
  }) {
    if (command.matchId != current.matchId) {
      // Ignore commands for other matches.
      return current;
    }

    MatchState next = current;

    switch (command.type) {
      case CommandType.reset:
        next = current.copyWith(scoreA: 0, scoreB: 0);
        break;
      case CommandType.inc:
        if (command.side == ScoreSide.home) {
          next = current.copyWith(scoreA: current.scoreA + 1);
        } else if (command.side == ScoreSide.away) {
          next = current.copyWith(scoreB: current.scoreB + 1);
        }
        break;
      case CommandType.dec:
        if (command.side == ScoreSide.home) {
          next = current.copyWith(scoreA: (current.scoreA - 1).clamp(0, 1 << 30));
        } else if (command.side == ScoreSide.away) {
          next = current.copyWith(scoreB: (current.scoreB - 1).clamp(0, 1 << 30));
        }
        break;
    }

    final changed =
        (next.scoreA != current.scoreA) || (next.scoreB != current.scoreB);
    if (!changed) return current;

    return next.copyWith(
      version: current.version + 1,
      lastUpdatedAt: appliedAt,
      lastUpdatedBy: appliedBy,
    );
  }
}

