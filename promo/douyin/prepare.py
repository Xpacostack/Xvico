from pathlib import Path
from PIL import Image
p=Path(__file__).resolve().parent
(p/'.build/keyframes').mkdir(parents=True,exist_ok=True)
im=Image.open(p.parent/'.build/app-plates/app-mapping-main.png')
im.crop((0,46,172,411)).save(p/'.build/sidebar.png')
