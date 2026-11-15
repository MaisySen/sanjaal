#!/bin/bash
# Installs the split package on the emulator, walks screens, saves screenshots and UI dumps.
mkdir -p out
adb install-multiple -r pkg/base.apk pkg/split_config.arm64_v8a.apk pkg/split_config.en.apk pkg/split_config.xhdpi.apk > out/install.txt 2>&1
cat out/install.txt
adb shell getprop ro.product.cpu.abilist > out/abis.txt
PKG=com.kcha.chat
for p in CAMERA RECORD_AUDIO POST_NOTIFICATIONS READ_MEDIA_IMAGES READ_MEDIA_VIDEO READ_CONTACTS ACCESS_FINE_LOCATION; do adb shell pm grant $PKG android.permission.$p 2>/dev/null; done
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 > out/launch.txt 2>&1
snap() { n=$1; adb exec-out screencap -p > out/$n.png; adb shell uiautomator dump /sdcard/$n.xml >/dev/null 2>&1; adb pull /sdcard/$n.xml out/$n.xml >/dev/null 2>&1; }
for i in 1 2 3 4 5 6; do sleep 6; snap s$i; done
adb logcat -d -t 400 > out/logcat.txt
adb shell dumpsys activity activities | grep -E "mResumedActivity|ResumedActivity" > out/activity.txt
adb shell wm size > out/size.txt
