from pathlib import Path
from PIL import Image
p=Path(__file__).resolve().parent
(p/'.build/keyframes').mkdir(parents=True,exist_ok=True)
a=p.parent/'.build/app-plates'
Image.open(a/'app-mapping-main.png').crop((0,46,172,411)).save(p/'.build/sidebar.png')
Image.open(a/'app-device.png').crop((332,413,1019,516)).save(p/'.build/channels.png')
Image.open(a/'app-voice.png').crop((333,468,1016,534)).save(p/'.build/voice-approval.png')
Image.open(a/'app-device.png').crop((334,417,670,511)).save(p/'.build/channel-buttons.png')
Image.open(a/'app-device.png').crop((682,417,1017,511)).save(p/'.build/channel-touch.png')
