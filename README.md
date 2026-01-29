# PingTalk (점수판 + 워치 연동)

## 목표
- **모바일(Flutter)**: 1:1 게임 점수판(좌/우 또는 A/B), 되돌리기/리셋, 워치 연동의 “정답(Authority)”
- **웨어러블(네이티브)**:
  - **Apple Watch**: 최소 조작(+1/-1, A/B 선택, 리셋) + 현재 점수 표시
  - **Galaxy Watch (Wear OS)**: 동일

## 핵심 원칙(현재 합의)
- **폰이 권한(정답) 점수**를 보유한다.
- 워치는 “점수 변경 명령”을 폰에 보내고, 폰은 처리 후 **최신 상태를 워치로 푸시**한다.

## 리포 구조(예정)
- `docs/`: 논의/스펙/프로토콜 문서
- `packages/pingtalk_core/`: 점수/프로토콜 **순수 Dart 코어**
- `mobile/`: Flutter 앱(점수판 UI + 워치 브리지 채널)
- `watch/`: 워치 네이티브 프로젝트(예정)
  - Wear OS는 우선 **`mobile/android/wear` 모듈**로 포함(같은 Gradle wrapper로 바로 빌드/실행)

## 개발 시작(필수 선행)
### 로컬 실행(Windows)
```bash
cd mobile
flutter pub get
flutter run -d windows
```

### Android 실행(에뮬레이터/실기기)
Android SDK/JDK 설정이 필요합니다. 상세는 `docs/02-개발환경설정.md`를 참고하세요.

