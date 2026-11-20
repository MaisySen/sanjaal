"""Current source deliberately leaves formal export declaration unanswered.
No exemption or non-exemption determination is inferred by this test.
"""
from pathlib import Path
import plistlib
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ExportDeclarationHold(unittest.TestCase):
 def test_no_unverified_build_declaration(self):
  info=plistlib.loads((ROOT/'app/ios/Runner/Info.plist').read_bytes())
  self.assertNotIn('ITSAppUsesNonExemptEncryption',info,'Export classification is unresolved; do not silently assert either legal answer')
  self.assertNotIn('ITSEncryptionExportComplianceCode',info,'No Apple-approved compliance code has been established')
 def test_hold_keeps_identity_and_privacy_prompts(self):
  info=plistlib.loads((ROOT/'app/ios/Runner/Info.plist').read_bytes())
  self.assertEqual(info['CFBundleIdentifier'],'$(PRODUCT_BUNDLE_IDENTIFIER)')
  self.assertEqual(info['CFBundleDisplayName'],'Sanjaal')
  for key in ['NSCameraUsageDescription','NSMicrophoneUsageDescription','NSPhotoLibraryUsageDescription']:
   self.assertIsInstance(info[key],str);self.assertTrue(info[key].strip())
if __name__=='__main__':unittest.main()
