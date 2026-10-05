#!/bin/zsh
# ./build.sh          → build/Portly.app (this Mac's architecture)
# ./build.sh install  → also copy to /Applications (where the Homebrew cask puts it) and (re)launch
# ./build.sh dist     → universal build/Portly-<version>.zip for a GitHub release, plus its sha256 for the cask
set -euo pipefail
cd "${0:A:h}"

VERSION=$(<VERSION)
APP=build/Portly.app
MODE=${1:-}

rm -rf build
mkdir -p $APP/Contents/MacOS
cp Info.plist $APP/Contents/
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" $APP/Contents/Info.plist

compile() {  # compile <arch> <output>
  swiftc -O -swift-version 5 -parse-as-library -target "$1-apple-macos14.0" Sources/*.swift -o "$2"
}

if [[ $MODE == dist ]]; then
  compile arm64 build/Portly-arm64
  compile x86_64 build/Portly-x86_64
  lipo -create build/Portly-arm64 build/Portly-x86_64 -output $APP/Contents/MacOS/Portly
  rm build/Portly-arm64 build/Portly-x86_64
else
  compile "$(uname -m)" $APP/Contents/MacOS/Portly
fi
codesign --force --sign - $APP
echo "built $APP ($VERSION)"

case $MODE in
  install)
    pkill -x Portly || true
    rm -rf /Applications/Portly.app
    cp -R $APP /Applications/
    open /Applications/Portly.app
    echo "installed /Applications/Portly.app"
    ;;
  dist)
    ZIP=build/Portly-$VERSION.zip
    ditto -c -k --keepParent --norsrc --noextattr --noqtn $APP $ZIP
    echo "packed $ZIP"
    echo "sha256 $(shasum -a 256 $ZIP | cut -d' ' -f1)"
    ;;
esac
