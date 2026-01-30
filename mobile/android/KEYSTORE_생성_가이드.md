# Keystore 생성 가이드

## 1. Keystore 생성

`mobile/android` 디렉토리에서 다음 명령어를 실행하세요:

```bash
cd mobile/android
keytool -genkey -v -keystore pingtalk-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias pingtalk
```

### 입력 정보

명령어 실행 시 다음 정보를 입력하세요:

- **Keystore 비밀번호**: 안전한 비밀번호 입력 (나중에 필요하므로 반드시 기록)
- **키 비밀번호**: Keystore 비밀번호와 동일하게 입력하거나 별도로 설정
- **이름**: 개발자 이름 또는 회사명
- **조직 단위**: 부서명 (선택)
- **조직**: 회사명 또는 개인명
- **도시/지역**: 도시명
- **주/도**: 주 또는 도 이름
- **국가 코드**: 2자리 국가 코드 (예: KR, US)

### 예시

```
키 저장소 비밀번호 입력: [비밀번호 입력]
새 비밀번호 다시 입력: [비밀번호 재입력]
이름과 성을 입력하십시오.
  [Unknown]: 홍길동
조직 단위 이름을 입력하십시오.
  [Unknown]: 개발팀
조직 이름을 입력하십시오.
  [Unknown]: PingTalk
구/군/시 이름을 입력하십시오?
  [Unknown]: 서울
시/도 이름을 입력하십시오.
  [Unknown]: 서울특별시
이 조직의 두 자리 국가 코드를 입력하십시오.
  [Unknown]: KR
CN=홍길동, OU=개발팀, O=PingTalk, L=서울, ST=서울특별시, C=KR이(가) 맞습니까?
  [아니오]: y
```

## 2. key.properties 파일 생성

`key.properties.example` 파일을 복사하여 `key.properties` 파일을 생성하세요:

```bash
cd mobile/android
cp key.properties.example key.properties
```

그리고 `key.properties` 파일을 열어서 실제 값을 입력하세요:

```properties
storePassword=실제_keystore_비밀번호
keyPassword=실제_키_비밀번호
keyAlias=pingtalk
storeFile=pingtalk-release-key.jks
```

## 3. 보안 주의사항

⚠️ **중요:**

- `key.properties` 파일과 `pingtalk-release-key.jks` 파일은 **절대 Git에 커밋하지 마세요**
- 이 파일들은 `.gitignore`에 포함되어 있습니다
- Keystore 파일과 비밀번호를 안전한 곳에 백업하세요
- 분실 시 앱 업데이트가 불가능하므로 여러 곳에 백업하는 것을 권장합니다

## 4. 빌드 테스트

Keystore 설정이 완료되면 릴리즈 빌드를 테스트하세요:

```bash
cd mobile
flutter build appbundle --release
```

빌드가 성공하면 `mobile/build/app/outputs/bundle/release/app-release.aab` 파일이 생성됩니다.

