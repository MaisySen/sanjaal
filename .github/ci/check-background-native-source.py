#!/usr/bin/env python3
"""Exact tree proof for a batched compile, not physical/runtime acceptance."""
import json, pathlib, subprocess
root=pathlib.Path(__file__).resolve().parents[2]
manifest=json.loads((root/'docs/background-native-compile-trees.json').read_text())
for path,expected in manifest['trees'].items():
    actual=subprocess.check_output(['git','rev-parse','HEAD:'+path],cwd=root,text=True).strip()
    if actual!=expected: raise SystemExit('Reviewed tree differs: '+path)
checks={
 'app/lib/native_call_root.dart':'const nativeCallRootEnabled = false;',
 'app/ios/Runner/NativeCallEngine.swift':'static let enabled = false',
 'app/android/app/src/main/kotlin/au/fintex/sanjaal/NativeCallWakeReceiver.kt':'const val ENABLED = false',
}
for path,value in checks.items():
    if value not in (root/path).read_text():raise SystemExit('Activation gate changed: '+path)
print('Exact reviewed compile trees and inactive gates verified, no runtime acceptance implied.')
