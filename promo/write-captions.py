#!/usr/bin/env python3
"""Export the editable storyboard as an optional SRT; video text is already burned in."""
from pathlib import Path
import json
root = Path(__file__).resolve().parent
film = json.loads((root / 'storyboard.json').read_text())
def timestamp(seconds):
    ms = round(seconds * 1000)
    h,ms = divmod(ms,3600000)
    m,ms = divmod(ms,60000)
    s,ms = divmod(ms,1000)
    return f'{h:02}:{m:02}:{s:02},{ms:03}'
text = '\n\n'.join(f"{i+1}\n{timestamp(s['start'])} --> {timestamp(s['end'])}\n{s['title']}\n{s['subtitle']}" for i,s in enumerate(film['scenes']))
(root / 'dist/Xvico-promo-zh.srt').write_text(text+'\n',encoding='utf-8')
