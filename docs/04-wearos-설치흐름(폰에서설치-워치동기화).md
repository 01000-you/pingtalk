# Wear OS(갤럭시 워치) 설치 흐름: “폰에서 설치하면 워치에도 설치 가능”

## 핵심 요약
갤럭시 워치(Wear OS)는 워치에 동작할 코드/UI가 필요하므로 **워치 앱이 별도로 존재**해야 합니다.  
다만 “사용자가 폰에서 앱 설치 → 워치에서도 설치 가능/동기화” 경험을 만들려면 **폰용 앱 + 워치용 앱을 같은 Play Console 앱(동일 packageName)으로 함께 배포**하면 됩니다.

---

## 0) 전제 (지원 기기)
- 대상: **Galaxy Watch 4 이상 (Wear OS)**
- 구형 Tizen 워치는 별도 방식이 필요합니다.

---

## 1) packageName(= applicationId) 통일이 필수
Play Store에서 “같은 앱”으로 묶이려면 **폰용/워치용이 동일 packageName**이어야 합니다.

현재 Flutter(폰) 앱의 Android packageName:
- `mobile/android/app/build.gradle.kts`
  - `applicationId = "com.example.mobile"`
  - `namespace = "com.example.mobile"`

> 출시 전에는 반드시 `com.example.mobile`을 실제 고유 도메인 기반 ID로 변경하세요.  
> 예: `com.pingtalk.app`

---

## 2) 배포 아티팩트 2개가 필요
### A) 폰용(Flutter) 아티팩트
- Android App Bundle(AAB) 생성:
```bash
cd mobile
flutter build appbundle
```
- 결과: `mobile/build/app/outputs/bundle/release/app-release.aab`

### B) 워치용(Wear OS) 아티팩트
- 워치용은 **별도 Android(Wear OS) 앱**을 만들어 AAB를 생성합니다.
- 중요한 조건:
  - packageName(= applicationId) **폰과 동일**
  - `minSdk`는 보통 **26 이상**
  - `uses-feature android.hardware.type.watch` 포함
  - Data Layer 통신 구현(워치 ↔ 폰)

---

## 3) Play Console에서 “한 앱”으로 묶어 배포
1. Play Console에서 새 앱 생성 (packageName 기준)
2. 릴리스(Internal testing 권장)에
   - 폰용 AAB 업로드
   - 워치용 AAB 업로드 (Wear OS 타겟)
3. 같은 트랙(예: Internal testing)으로 배포

그러면 사용자는:
- 폰 Play 스토어에서 앱을 설치했을 때
- 같은 계정으로 로그인된 워치에서도 해당 앱이 **설치 가능**으로 표시되거나,
- 워치 Play 스토어의 “휴대전화의 앱(또는 기기에서 사용 가능)” 섹션에서 설치할 수 있게 됩니다.

---

## 4) 개발/테스트에서 확인하는 방법
### 가장 현실적인 테스트 흐름
- 1) Internal testing 트랙 배포
- 2) 테스터 계정(구글 계정)을 **폰/워치 둘 다** 로그인
- 3) 폰 Play 스토어에서 설치
- 4) 워치 Play 스토어에서 “휴대전화의 앱/사용 가능”에서 설치 확인

### 즉시 확인(개발용)
Play 배포 전이라도, 워치 앱은 아래처럼 사이드로드로 테스트할 수 있습니다.
- 워치 개발자 옵션: ADB 디버깅 ON
- `adb install`로 워치에 워치 APK 설치

---

## 5) 우리 프로젝트 프로토콜(권장)
워치는 **명령(command)** 을 폰으로 보내고, 폰은 적용 후 **상태(state)** 를 워치로 돌려줍니다.
- `side`: `"HOME" | "AWAY"`
- 자세한 JSON은 `docs/01-동기화프로토콜.md` 참고

