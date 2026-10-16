# coding: utf-8
"""Write local delivery metadata and captions after encoded-video verification."""
from pathlib import Path
from PIL import Image
import json,hashlib
p=Path(__file__).resolve().parent;project=p.parent.parent;out=p/'dist'
cfg=json.loads((p/'storyboard.json').read_text());report=json.loads((out/'verification.json').read_text());motion=json.loads((out/'motion-verification.json').read_text())
assert report['verificationPassed'] and motion['passed']
assert any(t.get('width')==1080 and t.get('height')==1920 for t in report['media'])
def stamp(t):
 ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
srt='\n\n'.join(f'{i+1}\n{stamp(s["start"])} --> {stamp(s["end"])}\n{s["title"]}'for i,s in enumerate(cfg['scenes']))+'\n'
(out/'Xvico-update-zh.srt').write_text(srt)
(out/'发布文案.txt').write_text('Xvico 新版，更顺手了。\n\n玻璃界面与按键聚焦焕新，中心点击更稳定，拖动范围可调。重新连接后，点击、触控和外圈自动恢复；统一配置支持热重载。\n语音后台取消一小时固定截止，更新后台组件后生效，依然按需启动、主动停止。\n\n#Xvico #SiriRemote #Mac效率工具 #UI设计 #独立开发\n\n画面使用当前应用截图，功能流程以动效说明。\n')

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
basepath=project/'evidence/2026-10-16/update-iteration-video/baseline.json'
preservation={}
if basepath.exists():
 base=json.loads(basepath.read_text());preservation['approvedTechVideoUnchanged']=sha(project/'promo/douyin/dist/Xvico-update-douyin-9x16.mp4')==base['techVideoSHA256']
 preservation['previousHorizontalVideoUnchanged']=sha(project/'promo/dist/Xvico-promo-4x3-zh.mp4')==base['horizontalSHA256']
 c=Path.home()/'Library/Application Support/Xvico/config.json'
 if c.exists() and 'configurationSHA256' in base:preservation['applicationConfigurationUnchanged']=sha(c)==base['configurationSHA256']
 assert all(preservation.values())
sheet=out/'Xvico-storyboard.png'
im=Image.open(sheet).convert('RGB');im.resize((1080,1024),Image.Resampling.LANCZOS).save(sheet,optimize=True)
files=['Xvico-ui-features-9x16.mp4','Xvico-cover-9x16.png','Xvico-storyboard.png','Xvico-update-zh.srt','发布文案.txt','verification.json','motion-verification.json']
delivery={'title':cfg['title'],'size':[1080,1920],'aspect':'9:16','duration':40,'fps':30,'audio':'Original procedural 124 BPM electronic score and SFX; no voiceover','provenance':cfg['provenance'],'preservation':preservation,'files':{n:{'bytes':(out/n).stat().st_size,'sha256':sha(out/n)}for n in files},'sourceUI':{f.name:sha(f)for f in sorted((project/'promo/assets').glob('*.png'))},'additionalUI':{'sidebar-dark.png':sha(p/'assets/sidebar-dark.png')},'publication':'Local only; not uploaded to Douyin or Git'}
(out/'delivery.json').write_text(json.dumps(delivery,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'verified':True,'preservation':preservation,'videoBytes':(out/files[0]).stat().st_size},indent=2))
