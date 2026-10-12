#!/bin/sh
set -eu
udid=$1
app=$2
out=$3
bundle=com.iframed.you
mkdir -p "$out"
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$app"

shot() {
  name=$1
  shift
  xcrun simctl terminate "$udid" $bundle 2>/dev/null || true
  xcrun simctl launch "$udid" $bundle -demoFrame YES "$@" >/dev/null
  sleep 4
  xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null
}

ax() {
  key=$1
  value=$2
  xcrun simctl spawn "$udid" defaults write com.apple.Accessibility "$key" -bool "$value"
}

rtl="-AppleLanguages (ar) -AppleTextDirection YES -NSForceRightToLeftWritingDirection YES"
for screen in shopping chores setup connect climate; do
  shot "rtl-ar-$screen" -demoScreen "$screen" $rtl
done
shot rtl-ar-chores-editor -demoScreen chores -demoScroll editor $rtl
shot rtl-ar-pairing-code -demoScreen pairing -demoPairing code $rtl
shot rtl-ar-calendar-form -demoScreen setup -demoScroll calendarForm $rtl
shot rtl-pseudo-shopping -demoScreen shopping -NSForceRightToLeftWritingDirection YES -AppleTextDirection YES
shot rtl-pseudo-chores -demoScreen chores -NSForceRightToLeftWritingDirection YES -AppleTextDirection YES
for screen in shopping chores setup connect climate; do
  shot "double-$screen" -demoScreen "$screen" -NSDoubleLocalizedStrings YES
done
shot double-pairing-name -demoScreen pairing -demoPairing name -NSDoubleLocalizedStrings YES
shot double-pairing-confirming -demoScreen pairing -demoPairing confirming -NSDoubleLocalizedStrings YES
shot xs-shopping -demoScreen shopping -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXS
shot xs-climate -demoScreen climate -UIPreferredContentSizeCategoryName UICTContentSizeCategoryXS
shot ax5-pairing-code -demoScreen pairing -demoPairing code -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
shot ax5-chores-editor -demoScreen chores -demoScroll editor -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
shot ax5-connect -demoScreen connect -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
shot ax5-climate-many -demoScreen climate -demoClimate many -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
shot ax5-setup-calendar-form -demoScreen setup -demoScroll calendarForm -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL

ax ReduceMotionEnabled true
ax EnhancedBackgroundContrastEnabled true
shot reduce-motion-transparency-shopping -demoScreen shopping
shot reduce-motion-transparency-climate -demoScreen climate
shot reduce-motion-transparency-notice -demoScreen setup -demoScroll calendarForm
ax ReduceMotionEnabled false
ax EnhancedBackgroundContrastEnabled false

xcrun simctl ui "$udid" increase_contrast enabled
shot increase-contrast-shopping -demoScreen shopping
shot increase-contrast-chores -demoScreen chores
shot increase-contrast-climate -demoScreen climate
xcrun simctl ui "$udid" increase_contrast disabled

ax ButtonShapesEnabled true
shot button-shapes-shopping -demoScreen shopping
shot button-shapes-setup -demoScreen setup
shot button-shapes-climate -demoScreen climate
ax ButtonShapesEnabled false

ax InvertColorsEnabled true
shot smart-invert-shopping -demoScreen shopping
shot smart-invert-photos -demoScreen photos
ax InvertColorsEnabled false

xcrun simctl ui "$udid" appearance dark
shot dark-chores-editor -demoScreen chores -demoScroll editor
shot dark-pairing-code -demoScreen pairing -demoPairing code
xcrun simctl ui "$udid" appearance light
shot plain-shopping -demoScreen shopping
shot plain-chores-editor -demoScreen chores -demoScroll editor
shot plain-setup-calendar-form -demoScreen setup -demoScroll calendarForm
shot plain-climate -demoScreen climate -demoClimate many
echo "screens written to $out"
