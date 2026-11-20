"""Fail closed on black native frames in the synthetic color-pattern fixture."""
import json
from PIL import Image

def verify_frame(path, payload):
    spec = json.loads(payload)
    if 'videoRect' not in spec:
        return
    image = Image.open(path).convert('RGB')
    x, y, w, h = spec['videoRect']
    vw, vh = spec['viewport']
    box = (round(x / vw * image.width), round(y / vh * image.height),
           round((x+w) / vw * image.width), round((y+h) / vh * image.height))
    crop = image.crop(box)
    assert crop.width > 0 and crop.height > 0, 'invalid native-video capture area'
    colorful = sum(max(pixel) > 120 and max(pixel)-min(pixel) > 100 for pixel in crop.getdata())
    ratio = colorful / (crop.width * crop.height)
    assert ratio > .06, f'Native color-pattern video missing: colorful fraction {ratio:.5f}'
    print(f'PIXEL_GATE {path} colorful_fraction={ratio:.5f} crop={box}', flush=True)
