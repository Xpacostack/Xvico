#!/usr/bin/env python3
"""Compose an original electronic score and SFX locally. No samples or network."""
from pathlib import Path
import json, wave
import numpy as np

ROOT = Path(__file__).resolve().parent
cfg = json.loads((ROOT / 'storyboard.json').read_text())
SR = 48000
DURATION = cfg['duration']
BPM = cfg['music']['bpm']
BEAT = 60 / BPM
N = round(DURATION * SR)
rng = np.random.default_rng(62418)
bgm = np.zeros((N, 2), np.float64)
sfx = np.zeros_like(bgm)

def freq(midi):
    return 440 * 2 ** ((midi - 69) / 12)

def add(dest, start, signal, gain=1, pan=0):
    offset = round(start * SR)
    if offset >= N: return
    signal = np.asarray(signal)[:N-offset] * gain
    left = np.cos((pan+1)*np.pi/4)
    right = np.sin((pan+1)*np.pi/4)
    dest[offset:offset+len(signal), 0] += signal * left
    dest[offset:offset+len(signal), 1] += signal * right

def envelope(t, dur, attack=.015, release=.1):
    return np.minimum(1,t/attack) * np.minimum(1,np.maximum(0,(dur-t)/release))

def tone(note, dur, kind):
    t = np.arange(round(dur*SR)) / SR
    f = freq(note)
    if kind == 'pad':
        sig = .55*np.sin(2*np.pi*f*t) + .25*np.sin(2*np.pi*f*1.002*t) + .1*np.sin(2*np.pi*f*2*t)
        return sig * envelope(t,dur,.42,.9)
    if kind == 'bass':
        return (np.sin(2*np.pi*f*t)+.15*np.sin(2*np.pi*f*2*t))*np.exp(-t*4)*envelope(t,dur,.008,.08)
    return (np.sin(2*np.pi*f*t)+.20*np.sin(2*np.pi*f*2*t))*np.exp(-t*7)*envelope(t,dur,.004,.12)

# D minor, B-flat major, F major, C major; original fixed arpeggio pattern.
chords = [(50,57,62,65),(46,53,58,62),(41,53,57,60),(48,55,60,64)]
for bar in range(int(DURATION/(BEAT*8))+1):
    start = bar*BEAT*8
    chord = chords[bar%4]
    for j,note in enumerate(chord[1:]):
        add(bgm,start,tone(note+12,BEAT*8+.7,'pad'),.045,(-.35,0,.35)[j])
    for beat in range(8):
        when=start+beat*BEAT
        add(bgm,when,tone(chord[0]-12,BEAT*.85,'bass'),.18)
    pattern = [0,2,1,3,2,1,3,1,0,1,2,3,1,2,3,2]
    for step,index in enumerate(pattern):
        when=start+step*BEAT/2
        pluck=tone(chord[index]+24,.6,'pluck')
        add(bgm,when,pluck,.075,-.35 if step%2 else .35)
        add(bgm,when+BEAT*.75,pluck,.024,.5 if step%2 else -.5)

for beat in range(int(DURATION/BEAT)):
    when=beat*BEAT
    # Rounded kick; no clipped square-wave transients.
    t=np.arange(round(.25*SR))/SR
    kick=np.sin(2*np.pi*(44*t + 2.8*(1-np.exp(-t*28))))*np.exp(-t*18)
    add(bgm,when,kick,.24 if beat%2==0 else .15)
    # Short high-passed noise with a low overall level.
    ht=np.arange(round(.065*SR))/SR
    noise=rng.normal(0,1,len(ht));noise=np.r_[0,np.diff(noise)]
    add(bgm,when+BEAT/2,noise*np.exp(-ht*80),.012,(-.2 if beat%2 else .2))
    if beat%4==2:
        st=np.arange(round(.12*SR))/SR
        noise=rng.normal(0,1,len(st))
        add(bgm,when,noise*np.exp(-st*40),.024)

for transition in cfg['transitionTimes']:
    t=np.arange(round(.65*SR))/SR
    sweep=np.sin(2*np.pi*(320*t+920*t*t))*np.sin(np.pi*np.minimum(t/.65,1))**2*np.exp(-t*4)
    add(sfx,max(0,transition-.2),sweep,.055,-.12)
    for k,n in enumerate([74,81]):
        add(sfx,transition+.05+k*.065,tone(n,.35,'pluck'),.055,.15)
for start in cfg['sfxClicks']:
    t=np.arange(round(.05*SR))/SR
    click=np.sin(2*np.pi*1350*t)*np.exp(-t*130)*envelope(t,.05,.001,.015)
    add(sfx,start,click,.045)
# A soft resolving signature for the final brand reveal.
for k,n in enumerate([62,69,74,77]):
    add(sfx,cfg['scenes'][-1]['start']+.2+k*.12,tone(n,1.4,'pluck'),.09,(k-1.5)/4)

all_t=np.arange(N)/SR
fade=np.minimum(1,all_t/.8)*np.minimum(1,np.maximum(0,(DURATION-all_t)/1.4))
bgm*=fade[:,None];sfx*=fade[:,None]
mix=bgm+sfx
normalization=min(.72/np.max(np.abs(mix)),.12/np.sqrt(np.mean(mix**2)))
bgm*=normalization;sfx*=normalization;mix=bgm+sfx
out=ROOT/'.build';out.mkdir(exist_ok=True)
def write(name,data):
    pcm=(np.clip(data,-1,1)*32767).astype('<i2')
    with wave.open(str(out/name),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(SR);w.writeframes(pcm.tobytes())
for name,data in [('bgm.wav',bgm),('sfx.wav',sfx),('soundtrack.wav',mix)]:write(name,data)
report={'sampleRate':SR,'channels':2,'duration':DURATION,'bpm':BPM,'peakDbFS':float(20*np.log10(np.max(np.abs(mix)))),'rmsDbFS':float(20*np.log10(np.sqrt(np.mean(mix**2)))),'clippedSamples':int(np.count_nonzero(np.abs(mix)>=1)),'provenance':'Original procedural composition; sine synthesis and seeded noise; no external recording or music sample.'}
(out/'audio-report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
