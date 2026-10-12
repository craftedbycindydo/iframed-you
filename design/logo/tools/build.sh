#!/bin/zsh
set -e
LOGO=${0:A:h:h}
BT=$LOGO/build-test
source $BT/sims.env
SET=$1; shift
mkdir -p $BT/out
for name in "$@"; do
  SRC=$LOGO/$SET/$name/AppIcon.icon
  rm -rf $BT/IconTest/AppIcon.icon
  cp -R $SRC $BT/IconTest/AppIcon.icon
  LOG=$BT/out/$name.build.log
  xcodebuild -project $BT/IconTest.xcodeproj -scheme IconTest -sdk iphonesimulator -configuration Debug \
    -derivedDataPath $BT/build -destination 'generic/platform=iOS Simulator' \
    PRODUCT_BUNDLE_IDENTIFIER=dev.skylit.icon.$name build > $LOG 2>&1 || { echo "BUILD FAILED $name"; grep -E "error|warning" $LOG | head; exit 1; }
  APP=$BT/build/Build/Products/Debug-iphonesimulator/IconTest.app
  plutil -replace CFBundleDisplayName -string "$name" $APP/Info.plist
  rm -rf $BT/out/$name.app; cp -R $APP $BT/out/$name.app
  echo "== $name: $(grep -c 'warning' $LOG) warning lines, $(grep -ciE 'actool.*(warning|error)|AppIcon.*(warning|error)' $LOG) icon warnings"
  for U in $U26 $U18; do xcrun simctl install $U $BT/out/$name.app; done
done
