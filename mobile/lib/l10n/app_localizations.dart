import 'package:flutter/material.dart';

enum AppLocale {
  ko('ko', '한국어'),
  en('en', 'English'),
  zh('zh', '中文'),
  ja('ja', '日本語');

  final String code;
  final String displayName;
  const AppLocale(this.code, this.displayName);
}

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  // 메인 화면
  String get appTitle => 'PINGTALK';
  String get home => _getText('HOME', 'HOME', '主队', 'ホーム');
  String get away => _getText('AWAY', 'AWAY', '客队', 'アウェイ');
  String get undo => _getText('실행 취소', 'Undo', '撤销', '元に戻す');
  String get settings => _getText('설정', 'Settings', '设置', '設定');
  String get reset => _getText('초기화', 'Reset', '重置', 'リセット');
  
  // 워치 상태
  String get watchDisconnected => _getText('워치: 미연결', 'Watch: Disconnected', '手表：未连接', 'ウォッチ：未接続');
  String get watchConnecting => _getText('워치: 연결 중...', 'Watch: Connecting...', '手表：连接中...', 'ウォッチ：接続中...');
  String get watchConnected => _getText('워치: 연결됨', 'Watch: Connected', '手表：已连接', 'ウォッチ：接続済み');
  String get watchSyncing => _getText('워치: 동기화 중...', 'Watch: Syncing...', '手表：同步中...', 'ウォッチ：同期中...');
  String get watchSynced => _getText('워치: 동기화됨', 'Watch: Synced', '手表：已同步', 'ウォッチ：同期済み');
  String get watchSyncFailed => _getText('워치: 동기화 실패', 'Watch: Sync Failed', '手表：同步失败', 'ウォッチ：同期失敗');
  
  // 워치 앱 (워치에서 사용)
  String get watchPhoneDisconnected => _getText('폰: 미연결', 'Phone: Disconnected', '手机：未连接', '電話：未接続');
  String get watchPhoneConnected => _getText('폰: 연결됨', 'Phone: Connected', '手机：已连接', '電話：接続済み');
  String get watchPhoneSynced => _getText('폰: 동기화됨', 'Phone: Synced', '手机：已同步', '電話：同期済み');
  String get watchPhoneSent => _getText('폰: 전송됨', 'Phone: Sent', '手机：已发送', '電話：送信済み');
  String get watchPhoneSendFailed => _getText('폰: 전송 실패', 'Phone: Send Failed', '手机：发送失败', '電話：送信失敗');
  String get watchResetButton => _getText('초기화 (RESET)', 'Reset', '重置', 'リセット');
  String get watchResetTitle => _getText('초기화', 'Reset', '重置', 'リセット');
  String get watchResetMessage => _getText('모든 점수와 세트 스코어,\nUndo 히스토리가 삭제됩니다.\n정말 초기화하시겠습니까?', 
    'All scores, set scores,\nand undo history will be deleted.\nAre you sure you want to reset?',
    '所有分数、局分\n和撤销历史将被删除。\n确定要重置吗？',
    'すべてのスコア、セットスコア、\n元に戻す履歴が削除されます。\n本当にリセットしますか？');
  String get watchResetConfirm => _getText('확인', 'Confirm', '确认', '確認');
  String get watchResetCancel => _getText('취소', 'Cancel', '取消', 'キャンセル');
  
  // 초기화 다이얼로그
  String get resetTitle => _getText('초기화', 'Reset', '重置', 'リセット');
  String get resetMessage => _getText('모든 점수와 세트 스코어, Undo 히스토리가 삭제됩니다. 정말 초기화하시겠습니까?',
    'All scores, set scores, and undo history will be deleted. Are you sure you want to reset?',
    '所有分数、局分和撤销历史将被删除。确定要重置吗？',
    'すべてのスコア、セットスコア、元に戻す履歴が削除されます。本当にリセットしますか？');
  String get resetConfirm => _getText('초기화', 'Reset', '重置', 'リセット');
  String get resetCancel => _getText('취소', 'Cancel', '取消', 'キャンセル');
  
  // 세트 히스토리
  String get setHistory => _getText('세트 히스토리', 'Set History', '局分历史', 'セット履歴');
  String get set => _getText('세트', 'Set', '局', 'セット');
  String get winner => _getText('승자', 'Winner', '获胜者', '勝者');
  String get noCompletedSets => _getText('완료된 세트가 없습니다', 'No completed sets', '没有已完成的局', '完了したセットがありません');
  
  // 게임 설정
  String get gameSettings => _getText('게임 설정', 'Game Settings', '游戏设置', 'ゲーム設定');
  String get gameRules => _getText('게임 규칙', 'Game Rules', '游戏规则', 'ゲームルール');
  String get maxScore => _getText('최대 점수', 'Max Score', '最高分', '最大スコア');
  String get deuceEnabled => _getText('듀스 규칙 사용', 'Enable Deuce Rules', '启用平分规则', 'デュースルールを有効にする');
  String get deuceMargin => _getText('듀스 차이', 'Deuce Margin', '平分差', 'デュース差');
  String get save => _getText('저장', 'Save', '保存', '保存');
  String get language => _getText('언어', 'Language', '语言', '言語');
  
  // 스플래시
  String get splashTagline => _getText('스코어 관리의 새로운 기준', 'The New Standard for Score Management', '分数管理的新标准', 'スコア管理の新しい基準');
  
  // 일반 버튼
  String get ok => _getText('확인', 'OK', '确定', '了解');
  
  // 가이드
  String get guideTitle => _getText('사용 가이드', 'User Guide', '使用指南', '使い方ガイド');
  String get guideAppSection => _getText('📱 앱 사용법', '📱 App Usage', '📱 应用使用', '📱 アプリの使い方');
  String get guideWatchSection => _getText('⌚ 워치 사용법', '⌚ Watch Usage', '⌚ 手表使用', '⌚ ウォッチの使い方');
  
  // 앱 가이드 항목
  String get guideAppScoreIncrement => _getText('점수 증가', 'Score Increment', '增加分数', 'スコア増加');
  String get guideAppScoreIncrementDesc => _getText('점수 카드를 탭하면 해당 팀의 점수가 1점 증가합니다.', 
    'Tap the score card to increase the team\'s score by 1 point.',
    '点击分数卡片可增加该队1分。',
    'スコアカードをタップすると、そのチームのスコアが1点増加します。');
  String get guideAppUndo => _getText('되돌리기 (Undo)', 'Undo', '撤销', '元に戻す');
  String get guideAppUndoDesc => _getText('상단 중앙의 Undo 버튼을 눌러 마지막 점수 변경을 취소할 수 있습니다.',
    'Press the Undo button at the top center to cancel the last score change.',
    '点击顶部中央的撤销按钮可取消最后一次分数更改。',
    '上部中央の元に戻すボタンを押すと、最後のスコア変更をキャンセルできます。');
  String get guideAppReset => _getText('초기화 (Reset)', 'Reset', '重置', 'リセット');
  String get guideAppResetDesc => _getText('상단 중앙의 Reset 버튼을 눌러 모든 점수를 초기화할 수 있습니다.',
    'Press the Reset button at the top center to reset all scores.',
    '点击顶部中央的重置按钮可重置所有分数。',
    '上部中央のリセットボタンを押すと、すべてのスコアをリセットできます。');
  String get guideAppSetHistory => _getText('세트 히스토리 보기', 'View Set History', '查看局分历史', 'セット履歴を見る');
  String get guideAppSetHistoryDesc => _getText('화면을 우측으로 스와이프하면 완료된 세트 히스토리를 확인할 수 있습니다.',
    'Swipe right on the screen to view completed set history.',
    '向右滑动屏幕可查看已完成的局分历史。',
    '画面を右にスワイプすると、完了したセット履歴を確認できます。');
  String get guideAppVideoRecording => _getText('동영상 녹화', 'Video Recording', '视频录制', '動画録画');
  String get guideAppVideoRecordingDesc => _getText('좌측 하단의 녹화 버튼을 눌러 경기를 녹화할 수 있습니다. 미리보기 버튼으로 현재 카메라 각도를 확인할 수 있습니다.',
    'Press the record button at the bottom left to record the match. Use the preview button to check the current camera angle.',
    '点击左下角的录制按钮可录制比赛。使用预览按钮可查看当前相机角度。',
    '左下の録画ボタンを押すと試合を録画できます。プレビューボタンで現在のカメラ角度を確認できます。');
  String get guideAppStopwatch => _getText('스톱워치', 'Stopwatch', '秒表', 'ストップウォッチ');
  String get guideAppStopwatchDesc => _getText('우측 하단의 스톱워치로 경기 시간을 측정할 수 있습니다. 탭으로 시작/일시정지, 초기화 버튼으로 리셋합니다.',
    'Use the stopwatch at the bottom right to measure match time. Tap to start/pause, use the reset button to reset.',
    '使用右下角的秒表可测量比赛时间。点击开始/暂停，使用重置按钮重置。',
    '右下のストップウォッチで試合時間を測定できます。タップで開始/一時停止、リセットボタンでリセットします。');
  String get guideAppSettings => _getText('설정', 'Settings', '设置', '設定');
  String get guideAppSettingsDesc => _getText('상단 중앙의 설정 버튼에서 게임 규칙, 언어, 자동 위치 교체 기능을 변경할 수 있습니다.',
    'Change game rules, language, and auto-swap position features from the settings button at the top center.',
    '从顶部中央的设置按钮可更改游戏规则、语言和自动位置交换功能。',
    '上部中央の設定ボタンから、ゲームルール、言語、自動位置交換機能を変更できます。');
  
  // 워치 가이드 항목
  String get guideWatchScoreIncrement => _getText('점수 증가', 'Score Increment', '增加分数', 'スコア増加');
  String get guideWatchScoreIncrementDesc => _getText('HOME 또는 AWAY 버튼을 눌러 해당 팀의 점수를 1점 증가시킬 수 있습니다.',
    'Press the HOME or AWAY button to increase the team\'s score by 1 point.',
    '点击HOME或AWAY按钮可增加该队1分。',
    'HOMEまたはAWAYボタンを押すと、そのチームのスコアが1点増加します。');
  String get guideWatchUndo => _getText('되돌리기 (Undo)', 'Undo', '撤销', '元に戻す');
  String get guideWatchUndoDesc => _getText('UNDO 버튼을 눌러 마지막 점수 변경을 취소할 수 있습니다.',
    'Press the UNDO button to cancel the last score change.',
    '点击UNDO按钮可取消最后一次分数更改。',
    'UNDOボタンを押すと、最後のスコア変更をキャンセルできます。');
  String get guideWatchReset => _getText('초기화 (Reset)', 'Reset', '重置', 'リセット');
  String get guideWatchResetDesc => _getText('RESET 버튼을 길게 눌러 모든 점수를 초기화할 수 있습니다.',
    'Long press the RESET button to reset all scores.',
    '长按RESET按钮可重置所有分数。',
    'RESETボタンを長押しすると、すべてのスコアをリセットできます。');
  String get guideWatchVoice => _getText('음성 인식 (Voice)', 'Voice Recognition', '语音识别', '音声認識');
  String get guideWatchVoiceDesc => _getText('VOICE 버튼을 눌러 음성 인식을 시작/중지할 수 있습니다. "블루" 또는 "레드"라고 말하면 해당 팀의 점수가 1점 증가합니다.',
    'Press the VOICE button to start/stop voice recognition. Say "Blue" or "Red" to increase that team\'s score by 1 point.',
    '点击VOICE按钮可开始/停止语音识别。说"Blue"或"Red"可增加该队1分。',
    'VOICEボタンを押すと音声認識を開始/停止できます。「ブルー」または「レッド」と言うと、そのチームのスコアが1点増加します。');
  String get guideWatchAlwaysOn => _getText('Always On', 'Always On', '常亮', '常時表示');
  String get guideWatchAlwaysOnDesc => _getText('ALWAYS ON 버튼을 눌러 화면이 항상 켜져있도록 설정할 수 있습니다. 경기 중 화면이 꺼지는 것을 방지합니다.',
    'Press the ALWAYS ON button to keep the screen always on. This prevents the screen from turning off during the match.',
    '点击ALWAYS ON按钮可使屏幕保持常亮。这可以防止比赛期间屏幕关闭。',
    'ALWAYS ONボタンを押すと、画面を常時表示に設定できます。試合中に画面が消えるのを防ぎます。');
  String get guideWatchSync => _getText('동기화', 'Synchronization', '同步', '同期');
  String get guideWatchSyncDesc => _getText('워치와 앱이 연결되면 실시간으로 점수가 동기화됩니다. 연결 상태는 앱 상단 우측에서 확인할 수 있습니다.',
    'When the watch and app are connected, scores are synchronized in real time. Connection status can be checked at the top right of the app.',
    '当手表和应用程序连接时，分数会实时同步。连接状态可在应用程序右上角查看。',
    'ウォッチとアプリが接続されると、スコアがリアルタイムで同期されます。接続状態はアプリの右上で確認できます。');

  String _getText(String ko, String en, String zh, String ja) {
    switch (locale.languageCode) {
      case 'ko':
        return ko;
      case 'en':
        return en;
      case 'zh':
        return zh;
      case 'ja':
        return ja;
      default:
        return ko;
    }
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['ko', 'en', 'zh', 'ja'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

