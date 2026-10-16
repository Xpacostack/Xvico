#!/usr/bin/env python3
"""Prepare current real UI captures for code-rendered promotional compositions.

Original screenshots stay intact. Derived plates remove only the baked-in remote
and shadow, the OS sharing indicator and parked pointer. Product UI is retained.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
OUT = ROOT / '.build/app-plates'
OUT.mkdir(parents=True, exist_ok=True)
SIZE = (1180, 810)


def interpolate(data, box, feather=12):
    x0, y0, x1, y1 = box
    original = data[y0:y1, x0:x1].copy()
    if x1 >= data.shape[1] - 1:
        replacement = np.repeat(np.median(data[y0:y1, x0-8:x0], axis=1)[:, None, :], x1-x0, axis=1)
    else:
        q = np.linspace(0, 1, x1-x0)[None, :, None]
        left = np.median(data[y0:y1, x0-8:x0], axis=1)[:, None, :]
        right = np.median(data[y0:y1, x1:x1+8], axis=1)[:, None, :]
        replacement = left*(1-q) + right*q
    if feather:
        yy, xx = np.mgrid[0:y1-y0, 0:x1-x0]
        blend = np.clip(np.minimum.reduce([xx/feather, (x1-x0-1-xx)/feather,
            yy/feather, (y1-y0-1-yy)/feather, np.ones_like(xx)]), 0, 1)[..., None]
        replacement = original*(1-blend) + replacement*blend
    data[y0:y1, x0:x1] = replacement


def prepare(name, model=None):
    raw = Image.open(ROOT/'assets'/name).convert('RGB')
    assert raw.size == SIZE, (name, raw.size)
    data = np.asarray(raw).astype(float).copy()
    # Exclude OS capture chrome and the deliberately parked capture pointer.
    interpolate(data, (8, 0, 82, 27), feather=0)
    interpolate(data, (1137, 764, 1180, 810), feather=0)
    if model:
        interpolate(data, model, feather=16)
    image = Image.fromarray(np.clip(data, 0, 255).astype('uint8'))
    image.save(OUT/name)
    return image


prepare('app-mapping-main.png', (550, 65, 815, 710))
siri = prepare('app-siri-mapping.png', (680, 45, 1035, 735))
volume = prepare('app-volume-mapping.png', (700, 45, 1035, 735))
volume.crop((281, 185, 628, 626)).save(OUT/'volume-focus.png')
scenes = prepare('app-scenes.png')
voice = prepare('app-voice.png')
prepare('app-device.png')
siri.crop((281, 45, 628, 429)).save(OUT/'siri-focus.png')
scenes.crop((837, 452, 1136, 581)).save(OUT/'codex-preset-focus.png')
voice.crop((331, 204, 1019, 452)).save(OUT/'voice-input-focus.png')
(OUT/'preparation.json').write_text(json.dumps({
    'source': 'Current local Xvico window captures, 2026-10-16', 'dimensions': list(SIZE),
    'purpose': 'One continuous 3D model over actual current UI; source originals retained.',
    'removedInDerivedPlates': ['baked-in model and its shadow', 'OS sharing indicator', 'parked capture cursor'],
    'uiControlsFabricated': False, 'microphoneStarted': False, 'settingsChanged': False,
    'crops': {'siri-focus': [281,45,628,429], 'volume-focus': [281,185,628,626], 'codex-preset-focus': [837,452,1136,581],
              'voice-input-focus': [331,204,1019,452]}
}, ensure_ascii=False, indent=2)+'\n')
print('Prepared 2026-10-16 current UI plates and crops.')
