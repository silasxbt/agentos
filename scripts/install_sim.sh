#!/bin/zsh
# 编译 → 用开发者证书重签(App Shortcuts 需要 Team ID) → 安装到模拟器
# 用法: scripts/install_sim.sh <SIM_UDID>
set -e
UD=${1:?需要模拟器 UDID}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
cd "$(dirname "$0")/.."
xcodebuild -project BinanceVoiceAgent.xcodeproj -scheme BinanceVoiceAgent \
  -sdk iphonesimulator -destination "id=$UD" -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES build | grep -E "error:|BUILD"
APP=build/Build/Products/Debug-iphonesimulator/BinanceVoiceAgent.app
ID=$(security find-identity -v -p codesigning | grep "Apple Development" | grep -v REVOKED | head -1 | awk '{print $2}')
if [[ -n "$ID" ]]; then
  codesign --force -s "$ID" --preserve-metadata=entitlements,flags "$APP/PlugIns/BinanceVoiceWidget.appex"
  codesign --force -s "$ID" --preserve-metadata=entitlements,flags "$APP"
  echo "signed: $(codesign -dvv "$APP" 2>&1 | grep TeamIdentifier)"
else
  echo "WARN: 没有 Apple Development 证书,App Shortcuts 在模拟器上会报 Something went wrong"
fi
xcrun simctl terminate "$UD" com.hackathon.BinanceVoiceAgent 2>/dev/null || true
xcrun simctl install "$UD" "$APP"
xcrun simctl launch "$UD" com.hackathon.BinanceVoiceAgent
