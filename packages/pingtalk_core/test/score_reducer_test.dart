import 'package:pingtalk_core/pingtalk_core.dart';
import 'package:test/test.dart';

void main() {
  test('increment/decrement/reset update version and clamp to zero', () {
    final initial = MatchState(
      matchId: 'm1',
      playerAName: 'A',
      playerBName: 'B',
      scoreA: 0,
      scoreB: 0,
      version: 0,
      lastUpdatedAt: DateTime.utc(2026),
      lastUpdatedBy: UpdatedBy.phone,
    );

    final incA = ScoreCommand(
      id: 'c1',
      matchId: 'm1',
      type: CommandType.inc,
      side: ScoreSide.home,
      issuedAt: DateTime.utc(2026),
      issuedBy: UpdatedBy.watch,
    );

    final s1 = ScoreReducer.apply(
      current: initial,
      command: incA,
      appliedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
      appliedBy: UpdatedBy.phone,
    );
    expect(s1.scoreA, 1);
    expect(s1.version, 1);

    final decA = ScoreCommand(
      id: 'c2',
      matchId: 'm1',
      type: CommandType.dec,
      side: ScoreSide.home,
      issuedAt: DateTime.utc(2026),
      issuedBy: UpdatedBy.watch,
    );

    final s2 = ScoreReducer.apply(
      current: s1,
      command: decA,
      appliedAt: DateTime.utc(2026, 1, 1, 0, 0, 2),
      appliedBy: UpdatedBy.phone,
    );
    expect(s2.scoreA, 0);
    expect(s2.version, 2);

    // clamp at 0 (no change => no version bump)
    final s3 = ScoreReducer.apply(
      current: s2,
      command: decA,
      appliedAt: DateTime.utc(2026, 1, 1, 0, 0, 3),
      appliedBy: UpdatedBy.phone,
    );
    expect(s3.scoreA, 0);
    expect(s3.version, 2);

    final reset = ScoreCommand(
      id: 'c3',
      matchId: 'm1',
      type: CommandType.reset,
      issuedAt: DateTime.utc(2026),
      issuedBy: UpdatedBy.watch,
    );

    final s4 = ScoreReducer.apply(
      current: s1.copyWith(scoreB: 5),
      command: reset,
      appliedAt: DateTime.utc(2026, 1, 1, 0, 0, 4),
      appliedBy: UpdatedBy.phone,
    );
    expect(s4.scoreA, 0);
    expect(s4.scoreB, 0);
    expect(s4.version, 2);
  });
}

