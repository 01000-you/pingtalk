#!/bin/bash

# Keystore 생성 스크립트
# 이 스크립트는 PingTalk 앱의 릴리즈 서명용 Keystore를 생성합니다.

echo "=========================================="
echo "PingTalk Keystore 생성"
echo "=========================================="
echo ""
echo "이 스크립트는 릴리즈 빌드용 Keystore를 생성합니다."
echo "생성된 Keystore 파일과 비밀번호는 안전하게 보관하세요."
echo ""

# Keystore 파일이 이미 존재하는지 확인
if [ -f "pingtalk-release-key.jks" ]; then
    echo "⚠️  경고: pingtalk-release-key.jks 파일이 이미 존재합니다."
    read -p "기존 파일을 덮어쓰시겠습니까? (y/N): " overwrite
    if [ "$overwrite" != "y" ] && [ "$overwrite" != "Y" ]; then
        echo "작업을 취소했습니다."
        exit 0
    fi
    rm -f pingtalk-release-key.jks
fi

echo ""
echo "Keystore 생성을 시작합니다..."
echo "다음 정보를 입력하세요:"
echo ""

# 비밀번호 입력
read -sp "Keystore 비밀번호를 입력하세요: " store_password
echo ""
read -sp "Keystore 비밀번호를 다시 입력하세요: " store_password_confirm
echo ""

if [ "$store_password" != "$store_password_confirm" ]; then
    echo "❌ 비밀번호가 일치하지 않습니다. 다시 시도하세요."
    exit 1
fi

read -sp "키 비밀번호를 입력하세요 (Enter로 Keystore 비밀번호와 동일하게): " key_password
echo ""

if [ -z "$key_password" ]; then
    key_password="$store_password"
fi

# 개발자 정보 입력
read -p "이름 (예: 홍길동): " name
read -p "조직 단위 (선택, Enter로 건너뛰기): " org_unit
read -p "조직명 (예: PingTalk): " org_name
read -p "도시 (예: 서울): " city
read -p "시/도 (예: 서울특별시): " state
read -p "국가 코드 (2자리, 예: KR): " country

# 기본값 설정
name=${name:-"PingTalk Developer"}
org_name=${org_name:-"PingTalk"}
city=${city:-"Seoul"}
state=${state:-"Seoul"}
country=${country:-"KR"}

# DN 구성
dn="CN=$name"
if [ -n "$org_unit" ]; then
    dn="$dn, OU=$org_unit"
fi
dn="$dn, O=$org_name, L=$city, ST=$state, C=$country"

echo ""
echo "입력된 정보:"
echo "  이름: $name"
if [ -n "$org_unit" ]; then
    echo "  조직 단위: $org_unit"
fi
echo "  조직: $org_name"
echo "  도시: $city"
echo "  시/도: $state"
echo "  국가: $country"
echo ""

read -p "위 정보가 맞습니까? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "작업을 취소했습니다."
    exit 0
fi

echo ""
echo "Keystore를 생성하는 중..."

# Keystore 생성
keytool -genkey -v \
    -keystore pingtalk-release-key.jks \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -alias pingtalk \
    -storepass "$store_password" \
    -keypass "$key_password" \
    -dname "$dn"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Keystore가 성공적으로 생성되었습니다!"
    echo ""
    echo "다음 단계:"
    echo "1. key.properties 파일을 생성하고 비밀번호를 입력하세요:"
    echo "   cp key.properties.example key.properties"
    echo "   # key.properties 파일을 열어서 비밀번호를 입력하세요"
    echo ""
    echo "2. Keystore 파일과 비밀번호를 안전한 곳에 백업하세요!"
    echo ""
else
    echo ""
    echo "❌ Keystore 생성에 실패했습니다."
    exit 1
fi

