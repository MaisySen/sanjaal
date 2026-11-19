from pathlib import Path
p=Path('pubspec.yaml')
s=p.read_text().replace('  assets:\n','  assets:\n    - test/fixtures/ridge.png\n    - test/fixtures/ios_synthetic_video.mp4\n')
p.write_text(s)
