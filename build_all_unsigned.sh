#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"
PROJECT="$ROOT/PicaX.xcodeproj"
PBXPROJ="$PROJECT/project.pbxproj"
PBXPROJ_BAK="$BUILD/project.pbxproj.backup.autobuild"

APP_NAME="PicaX"
WATCH_APP_NAME="PicaX Watch App"

DD_IOS="$BUILD/DerivedData-iOS"
WATCH_BUILD="$BUILD/WatchBuild"
DD_MAC="$BUILD/DerivedData-macOS"

IOS_IPA="$BUILD/PicaX-unsigned.ipa"
WITH_WATCH_IPA="$BUILD/PicaX-with-watch-unsigned.ipa"
WATCH_ZIP="$BUILD/PicaX-WatchApp-unsigned.zip"
DMG_PATH="$BUILD/PicaX.dmg"

cd "$ROOT"
mkdir -p "$BUILD"

restore_project() {
  if [ -f "$PBXPROJ_BAK" ]; then
    cp "$PBXPROJ_BAK" "$PBXPROJ"
    echo "✅ 已恢复 project.pbxproj"
  fi
}

trap restore_project EXIT

echo "========== 备份并临时禁用主 Target 的 Watch 自动依赖 =========="

cp "$PBXPROJ" "$PBXPROJ_BAK"

export PBXPROJ
python3 - <<'PY'
import os
from pathlib import Path

pbx = Path(os.environ["PBXPROJ"])
text = pbx.read_text()

# 移除 PicaX 主 Target 的 Embed Watch Content build phase
text = text.replace('\t\t\t\t6D9FF26B2FEEB200008AA850 /* Embed Watch Content */,\n', '')

# 移除 PicaX 主 Target 对 PicaX Watch App 的 target dependency
text = text.replace('\t\t\t\t6D9FF26D2FEEB200008AA850 /* PBXTargetDependency */,\n', '')

pbx.write_text(text)
PY

echo "========== 清理本次目标产物 =========="

rm -rf "$DD_IOS"
rm -rf "$WATCH_BUILD"
rm -rf "$DD_MAC"

rm -rf "$BUILD/Payload-iOS"
rm -rf "$BUILD/Payload-WithWatch"
rm -rf "$BUILD/PicaX-WatchApp-Payload"
rm -rf "$BUILD/dmg-root"

rm -f "$IOS_IPA"
rm -f "$WITH_WATCH_IPA"
rm -f "$WATCH_ZIP"
rm -f "$DMG_PATH"

echo "========== 1/4 构建 iOS App =========="

xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$DD_IOS" \
  TARGETED_DEVICE_FAMILY="1,2" \
  REGISTER_APP_GROUPS=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE="" \
  PROVISIONING_PROFILE_SPECIFIER=""

IOS_APP_PATH="$(find "$DD_IOS/Build/Products/Release-iphoneos" -maxdepth 2 -name "$APP_NAME.app" -type d | head -n 1)"

if [ -z "$IOS_APP_PATH" ]; then
  echo "❌ 找不到 iOS App：$APP_NAME.app"
  exit 1
fi

echo "✅ iOS App：$IOS_APP_PATH"

echo "========== 2/4 构建 Watch App =========="

# 注意：这里不能用 clean build。
# 因为 WATCH_BUILD 是我们自己指定/创建的目录，xcodebuild clean 可能会报：
# Could not delete ... because it was not created by the build system.
xcodebuild build \
  -project "$PROJECT" \
  -target "$WATCH_APP_NAME" \
  -configuration Release \
  -sdk watchos \
  SYMROOT="$WATCH_BUILD" \
  OBJROOT="$WATCH_BUILD/Intermediates" \
  REGISTER_APP_GROUPS=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE="" \
  PROVISIONING_PROFILE_SPECIFIER=""

WATCH_APP_PATH="$(find "$WATCH_BUILD" -path "*Release-watchos*" -name "$WATCH_APP_NAME.app" -type d | head -n 1)"

if [ -z "$WATCH_APP_PATH" ]; then
  echo "❌ 找不到 Watch App：$WATCH_APP_NAME.app"
  echo "当前找到的 .app："
  find "$WATCH_BUILD" -name "*.app" -type d || true
  exit 1
fi

echo "✅ Watch App：$WATCH_APP_PATH"

echo "========== 生成 1：独立 iOS 未签名 IPA =========="

mkdir -p "$BUILD/Payload-iOS/Payload"

ditto "$IOS_APP_PATH" "$BUILD/Payload-iOS/Payload/$APP_NAME.app"

# 确保独立 iOS IPA 不带 Watch
rm -rf "$BUILD/Payload-iOS/Payload/$APP_NAME.app/Watch"

cd "$BUILD/Payload-iOS"
zip -qry "$IOS_IPA" Payload

if [ ! -f "$IOS_IPA" ]; then
  echo "❌ 生成独立 iOS IPA 失败"
  exit 1
fi

echo "✅ 已生成：$IOS_IPA"
ls -lh "$IOS_IPA"

echo "========== 生成 2：包含 Watch App 的未签名 IPA =========="

mkdir -p "$BUILD/Payload-WithWatch/Payload/$APP_NAME.app"

ditto "$IOS_APP_PATH" "$BUILD/Payload-WithWatch/Payload/$APP_NAME.app"

mkdir -p "$BUILD/Payload-WithWatch/Payload/$APP_NAME.app/Watch"
rm -rf "$BUILD/Payload-WithWatch/Payload/$APP_NAME.app/Watch/$WATCH_APP_NAME.app"

ditto "$WATCH_APP_PATH" "$BUILD/Payload-WithWatch/Payload/$APP_NAME.app/Watch/$WATCH_APP_NAME.app"

if [ ! -d "$BUILD/Payload-WithWatch/Payload/$APP_NAME.app/Watch/$WATCH_APP_NAME.app" ]; then
  echo "❌ Watch App 嵌入失败"
  exit 1
fi

cd "$BUILD/Payload-WithWatch"
zip -qry "$WITH_WATCH_IPA" Payload

if [ ! -f "$WITH_WATCH_IPA" ]; then
  echo "❌ 生成内嵌 Watch IPA 失败"
  exit 1
fi

echo "✅ 已生成：$WITH_WATCH_IPA"
ls -lh "$WITH_WATCH_IPA"

echo "========== 生成 3：独立 Watch App 未签名 ZIP =========="

mkdir -p "$BUILD/PicaX-WatchApp-Payload"

ditto "$WATCH_APP_PATH" "$BUILD/PicaX-WatchApp-Payload/$WATCH_APP_NAME.app"

cd "$BUILD"
zip -qry "$WATCH_ZIP" "PicaX-WatchApp-Payload"

if [ ! -f "$WATCH_ZIP" ]; then
  echo "❌ 生成 Watch ZIP 失败"
  exit 1
fi

echo "✅ 已生成：$WATCH_ZIP"
ls -lh "$WATCH_ZIP"

echo "========== 4/4 构建 macOS App =========="

set +e

xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk macosx \
  -destination 'platform=macOS' \
  -derivedDataPath "$DD_MAC" \
  REGISTER_APP_GROUPS=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE="" \
  PROVISIONING_PROFILE_SPECIFIER=""

MAC_BUILD_STATUS=$?

set -e

MAC_APP_PATH="$(find "$DD_MAC/Build/Products" -name "$APP_NAME.app" -type d 2>/dev/null | head -n 1)"

if [ -z "$MAC_APP_PATH" ]; then
  echo "⚠️ 原生 macOS 构建没找到 $APP_NAME.app，尝试 Mac Catalyst"

  rm -rf "$DD_MAC"

  xcodebuild clean build \
    -project "$PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -sdk macosx \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$DD_MAC" \
    SUPPORTS_MACCATALYST=YES \
    REGISTER_APP_GROUPS=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE="" \
    PROVISIONING_PROFILE_SPECIFIER=""

  MAC_APP_PATH="$(find "$DD_MAC/Build/Products" -name "$APP_NAME.app" -type d | head -n 1)"
fi

if [ -z "$MAC_APP_PATH" ]; then
  echo "❌ 找不到 macOS App：$APP_NAME.app"
  exit 1
fi

echo "✅ macOS App：$MAC_APP_PATH"

echo "========== 生成 4：拖拽安装 DMG =========="

mkdir -p "$BUILD/dmg-root"

ditto "$MAC_APP_PATH" "$BUILD/dmg-root/$APP_NAME.app"

rm -f "$BUILD/dmg-root/Applications"
ln -s /Applications "$BUILD/dmg-root/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$BUILD/dmg-root" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [ ! -f "$DMG_PATH" ]; then
  echo "❌ 生成 DMG 失败"
  exit 1
fi

echo "✅ 已生成：$DMG_PATH"
ls -lh "$DMG_PATH"

echo "========== 最终产物 =========="

ls -lh \
  "$IOS_IPA" \
  "$WITH_WATCH_IPA" \
  "$WATCH_ZIP" \
  "$DMG_PATH"

echo "========== 验证 IPA/ZIP 内容 =========="

echo "--- 独立 iOS IPA Watch 检查 ---"
unzip -l "$IOS_IPA" | grep -i "Watch" || echo "✅ 独立 iOS IPA 不包含 Watch"

echo "--- 内嵌 Watch IPA 检查 ---"
unzip -l "$WITH_WATCH_IPA" | grep -i "Watch" | head -40

echo "--- 独立 Watch ZIP 检查 ---"
unzip -l "$WATCH_ZIP" | head -40

echo "🎉 全部完成"
