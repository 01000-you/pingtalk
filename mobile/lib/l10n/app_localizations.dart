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

