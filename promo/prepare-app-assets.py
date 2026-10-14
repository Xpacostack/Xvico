#!/usr/bin/env python3
"""Prepare captured Xvico UI plates for one continuous animated model layer.

Only the existing model and its shadow are replaced by interpolated background.
The real navigation, controls, labels and current settings remain from the capture.
Raw captures are retained so the composition can be audited or rebuilt.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'.build/app-plates'
OUT.mkdir(parents=True,exist_ok=True)

def clean_plate(name,box):
    raw=Image.open(ROOT/'assets'/name).convert('RGB')
    assert raw.size==(2360,1620), f'Unexpected screenshot size: {name}: {raw.size}'
    data=np.asarray(raw).astype(np.float64)
    x0,y0,x1,y1=box
    patch=data[y0:y1,x0:x1].copy()
    q=np.linspace(0,1,x1-x0)[None,:,None]
    left=np.median(data[y0:y1,x0-8:x0],axis=1)[:,None,:]
    right=np.median(data[y0:y1,x1:x1+8],axis=1)[:,None,:]
    replacement=left*(1-q)+right*q
    yy,xx=np.mgrid[0:y1-y0,0:x1-x0]
    feather=np.minimum.reduce([xx/35,(x1-x0-1-xx)/35,yy/35,(y1-y0-1-yy)/35,np.ones_like(xx)])
    feather=np.clip(feather,0,1)[...,None]
    data[y0:y1,x0:x1]=patch*(1-feather)+replacement*feather
    Image.fromarray(np.clip(data,0,255).astype('uint8')).save(OUT/name)

clean_plate('app-mapping-main.png',(1155,190,1635,1440))
clean_plate('app-siri-mapping.png',(1410,165,2010,1440))
Image.open(ROOT/'assets/app-siri-mapping.png').crop((563,169,1254,875)).save(OUT/'siri-focus.png')
Image.open(ROOT/'assets/app-scenes.png').crop((1684,728,2318,895)).save(OUT/'codex-preset-focus.png')
Image.open(ROOT/'assets/app-voice.png').crop((631,150,2071,490)).save(OUT/'voice-input-focus.png')
report={'source':'Direct window captures from local dist/Xvico.app, 2026-10-14','dimensions':[2360,1620],'cleanPlatePurpose':'Remove the baked-in remote and shadow so one animated USDZ layer can occupy the same place, then move out of the window. No navigation, control, text or setting is fabricated.','derivedAssets':['app-mapping-main.png','app-siri-mapping.png','siri-focus.png','codex-preset-focus.png','voice-input-focus.png'],'microphoneStarted':False,'settingsChanged':False}
(OUT/'preparation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('Prepared actual Xvico UI plates and focused crops.')
