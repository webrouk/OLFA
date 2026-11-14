"""Generates OLFA's own notification sounds (no third-party audio, no licence
questions). Soft bell-like tones: a sine fundamental with gentle inharmonic
partials, fast attack, exponential decay, short reverb tail.

  message.wav       – two notes (E6 → B5), 0.45 s — new chat message
  notification.wav  – rising three-note chime (G5 · C6 · E6), 0.9 s — likes, matches, compliments
  match.wav         – warm four-note arpeggio, 1.3 s — it's a match / compliment

Run: python3 tools/make_sounds.py  (writes mobile/assets/sounds/ + platform copies)
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import fftconvolve

SR = 48000
OUT = os.path.join(os.path.dirname(__file__), '..', 'mobile', 'assets', 'sounds')

def note(freq, dur, amp=0.6, decay=6.0):
    t = np.arange(int(SR * dur)) / SR
    # bell-ish: fundamental + soft partials (slightly inharmonic for warmth)
    w = (np.sin(2 * np.pi * freq * t)
         + 0.35 * np.sin(2 * np.pi * freq * 2.01 * t) * np.exp(-t * decay * 1.6)
         + 0.12 * np.sin(2 * np.pi * freq * 3.02 * t) * np.exp(-t * decay * 2.4))
    attack = np.minimum(1, t / 0.006)
    env = attack * np.exp(-t * decay)
    return amp * w * env

def place(total, parts):
    buf = np.zeros(int(SR * total))
    for start, sig in parts:
        i = int(SR * start)
        buf[i:i + len(sig)] += sig[: len(buf) - i]
    return buf

def reverb(x, tail=0.35, mix=0.18):
    n = int(SR * tail)
    rng = np.random.default_rng(7)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * tail / 5))
    wet = fftconvolve(x, ir)[: len(x)]
    wet /= np.max(np.abs(wet)) + 1e-9
    return (1 - mix) * x + mix * wet * np.max(np.abs(x))

def finish(x, name):
    x = reverb(x)
    fade = int(SR * 0.04)
    x[-fade:] *= np.linspace(1, 0, fade)
    x = x / np.max(np.abs(x)) * 0.79  # ≈ -2 dBFS peak, no clipping
    pcm = (x * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    wavfile.write(os.path.join(OUT, name), SR, pcm)
    print(name, f'{len(x) / SR:.2f}s')

E6, B5, G5, C6, A5, E5 = 1318.51, 987.77, 783.99, 1046.50, 880.00, 659.25
finish(place(0.45, [(0.0, note(E6, 0.25, 0.55, 14)), (0.11, note(B5, 0.34, 0.6, 10))]), 'message.wav')
finish(place(0.9, [(0.0, note(G5, 0.5, 0.5, 8)), (0.14, note(C6, 0.5, 0.5, 8)), (0.28, note(E6, 0.6, 0.55, 6))]), 'notification.wav')
finish(place(1.3, [(0.0, note(E5, 0.8, 0.45, 5)), (0.13, note(A5, 0.8, 0.45, 5)), (0.26, note(C6, 0.8, 0.5, 5)), (0.42, note(E6, 0.9, 0.55, 4))]), 'match.wav')
