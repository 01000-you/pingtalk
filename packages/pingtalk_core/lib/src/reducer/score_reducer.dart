import '../models/match_state.dart';
import '../models/score_command.dart';

class ScoreReducer {
  /// Applies a command to the current match state.
  ///
  /// Notes:
  /// - Scores are clamped at >= 0.
  /// - Maximum score and deuce rules are applied.
  /// - Set completion is handled automatically.
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
        next = current.copyWith(
          scoreA: 0,
          scoreB: 0,
          setScoresA: const [],
          setScoresB: const [],
          setHistory: const [],
          currentSet: 0,
        );
        break;
      case CommandType.inc:
        if (command.side == ScoreSide.home) {
          final newScore = current.scoreA + 1;
          if (_canIncrementScore(newScore, current.scoreB, current.rules)) {
            next = current.copyWith(scoreA: newScore);
          }
        } else if (command.side == ScoreSide.away) {
          final newScore = current.scoreB + 1;
          if (_canIncrementScore(newScore, current.scoreA, current.rules)) {
            next = current.copyWith(scoreB: newScore);
          }
        }
        break;
      case CommandType.dec:
        if (command.side == ScoreSide.home) {
          next = current.copyWith(scoreA: (current.scoreA - 1).clamp(0, 1 << 30));
        } else if (command.side == ScoreSide.away) {
          next = current.copyWith(scoreB: (current.scoreB - 1).clamp(0, 1 << 30));
        }
        break;
      case CommandType.undo:
        // Undo는 reducer를 거치지 않고 모바일 앱에서 직접 처리
        // 여기서는 아무것도 하지 않음 (변경 없음)
        return current;
    }

    // 세트 종료 체크 및 처리
    next = _checkSetCompletion(next, appliedAt, appliedBy);

    final changed =
        (next.scoreA != current.scoreA) ||
        (next.scoreB != current.scoreB) ||
        (next.setScoresA.length != current.setScoresA.length) ||
        (next.setScoresB.length != current.setScoresB.length) ||
        (next.currentSet != current.currentSet);
    if (!changed) return current;

    return next.copyWith(
      version: current.version + 1,
      lastUpdatedAt: appliedAt,
      lastUpdatedBy: appliedBy,
    );
  }

  /// 점수 증가가 가능한지 확인 (최대 점수 및 듀스 규칙)
  static bool _canIncrementScore(
    int newScore,
    int opponentScore,
    GameRules rules,
  ) {
    // 최대 점수 체크
    if (!rules.deuceEnabled) {
      // 듀스 규칙 없으면 최대 점수까지만
      return newScore <= rules.maxScore;
    }

    // 듀스 규칙 적용
    // 최대 점수 미만이면 자유롭게 증가 가능
    if (newScore < rules.maxScore) {
      return true;
    }

    // 최대 점수 이상일 때는 듀스 상태
    // 듀스 상태에서는 점수는 계속 증가 가능하지만,
    // 승리하려면 상대방보다 듀스 마진(2점) 이상 앞서야 함
    // 점수 증가 자체는 제한하지 않음 (승리 조건은 _checkSetCompletion에서 체크)
    return true;
  }

  /// 세트 종료 체크 및 처리
  static MatchState _checkSetCompletion(
    MatchState state,
    DateTime appliedAt,
    UpdatedBy appliedBy,
  ) {
    final rules = state.rules;
    final scoreA = state.scoreA;
    final scoreB = state.scoreB;

    // 승리 조건 확인
    bool aWins = false;
    bool bWins = false;

    if (!rules.deuceEnabled) {
      // 듀스 규칙 없으면 최대 점수 도달 시 승리
      aWins = scoreA >= rules.maxScore && scoreA > scoreB;
      bWins = scoreB >= rules.maxScore && scoreB > scoreA;
    } else {
      // 듀스 규칙 적용
      if (scoreA >= rules.maxScore || scoreB >= rules.maxScore) {
        final diff = (scoreA - scoreB).abs();
        if (diff >= rules.deuceMargin) {
          aWins = scoreA > scoreB;
          bWins = scoreB > scoreA;
        }
      }
    }

    if (aWins || bWins) {
      // 세트 종료: 세트 스코어 업데이트 및 다음 세트로
      final newSetScoresA = List<int>.from(state.setScoresA);
      final newSetScoresB = List<int>.from(state.setScoresB);
      final newSetHistory = List<SetScore>.from(state.setHistory);

      // 현재 세트의 승패 기록
      if (aWins) {
        newSetScoresA.add(1);
        newSetScoresB.add(0);
      } else {
        newSetScoresA.add(0);
        newSetScoresB.add(1);
      }

      // 현재 세트의 게임 스코어 히스토리 기록
      newSetHistory.add(SetScore(
        setNumber: state.currentSet + 1,
        scoreA: scoreA,
        scoreB: scoreB,
        completedAt: appliedAt,
      ));

      return state.copyWith(
        scoreA: 0,
        scoreB: 0,
        setScoresA: newSetScoresA,
        setScoresB: newSetScoresB,
        setHistory: newSetHistory,
        currentSet: state.currentSet + 1,
      );
    }

    return state;
  }
}
