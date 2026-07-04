#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Fisherman's Horizon の効果音・BGMを numpy で合成生成する(著作権フリー・API不要)。
出力: assets/audio/*.wav (22050Hz mono 16bit)。Godot側で読み込んで再生。"""
import os, wave, struct
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "audio")
os.makedirs(OUT, exist_ok=True)


def save(name, sig, loop=False):
    sig = np.clip(sig, -1.0, 1.0)
    # フェード(クリック防止)。ループ音は末尾と先頭を合わせる
    n = len(sig)
    f = min(200, n // 20)
    if f > 0:
        sig[:f] *= np.linspace(0, 1, f)
        sig[-f:] *= np.linspace(1, 0, f)
    data = (sig * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, "%.1fs" % (n / SR))


def env(n, a=0.01, d=0.1, s=0.0, sl=0.6, r=0.1):
    """簡易ADSRエンベロープ(長さnサンプル)。"""
    t = np.arange(n) / SR
    e = np.ones(n)
    ai = int(a * SR); di = int(d * SR); ri = int(r * SR)
    if ai > 0: e[:ai] = np.linspace(0, 1, ai)
    if di > 0: e[ai:ai+di] = np.linspace(1, sl, di)
    e[ai+di:n-ri] = sl
    if ri > 0: e[n-ri:] = np.linspace(sl, 0, ri)
    return e


def tone(freq, n, kind="sine", detune=0.0):
    t = np.arange(n) / SR
    ph = 2 * np.pi * freq * t
    if kind == "sine":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "saw":
        return 2 * (t * freq - np.floor(0.5 + t * freq))
    if kind == "square":
        return np.sign(np.sin(ph))
    return np.sin(ph)


def noise(n):
    return np.random.uniform(-1, 1, n)


def lowpass(sig, a=0.15):
    out = np.zeros_like(sig)
    p = 0.0
    for i in range(len(sig)):
        p += a * (sig[i] - p)
        out[i] = p
    return out

# ---------------- 効果音 ----------------

def sfx_gun():
    # 迫力UP(#47): 低音の砲身の重み + 鋭いクラック + 軽い歪み
    n = int(0.11 * SR)
    s = noise(n) * env(n, 0.001, 0.02, r=0.05) * 0.7
    s += tone(90, n) * env(n, 0.001, 0.05, r=0.05) * 0.8
    s += tone(650, n) * env(n, 0.001, 0.02, r=0.02) * 0.25
    return np.tanh(s * 2.2) * 0.8

def sfx_cannon():
    # 迫力UP(#47): サブベースの轟き + 長い残響 + 歪み
    n = int(1.0 * SR)
    t = np.arange(n) / SR
    sweep = np.sin(2 * np.pi * (150 - 110 * np.minimum(t / 0.8, 1.0)) * t)
    s = sweep * env(n, 0.002, 0.25, sl=0.35, r=0.6) * 1.0
    s += np.sin(2 * np.pi * (55 - 25 * np.minimum(t / 0.9, 1.0)) * t) * env(n, 0.002, 0.3, sl=0.4, r=0.65) * 0.9
    s += lowpass(noise(n), 0.10) * env(n, 0.001, 0.15, sl=0.25, r=0.6) * 0.8
    return np.tanh(s * 2.0) * 0.9

def sfx_harpoon():
    n = int(0.25 * SR)
    s = tone(320, n) * env(n, 0.001, 0.08, r=0.15) * 0.4
    s += lowpass(noise(n), 0.3) * env(n, 0.001, 0.05, r=0.15) * 0.25
    return s

def sfx_torpedo():
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    s = lowpass(noise(n), 0.06) * (0.3 + 0.5 * t / 0.5) * env(n, 0.02, 0.1, sl=0.7, r=0.2)
    s += tone(140, n) * env(n, 0.02, 0.2, sl=0.5, r=0.2) * 0.3
    return s

def sfx_hit():  # 被弾(自船) 迫力UP(#47): 重い衝撃+軋み
    n = int(0.42 * SR)
    s = tone(70, n) * env(n, 0.001, 0.16, r=0.2) * 1.0
    s += tone(140, n) * env(n, 0.001, 0.10, r=0.1) * 0.5
    s += lowpass(noise(n), 0.25) * env(n, 0.001, 0.08, r=0.15) * 0.7
    return np.tanh(s * 2.0) * 0.85

def sfx_enemy_hit():  # 与ダメ 迫力UP(#47): 肉厚なインパクト
    n = int(0.16 * SR)
    s = tone(220, n) * env(n, 0.001, 0.05, r=0.07) * 0.6
    s += tone(430, n) * env(n, 0.001, 0.03, r=0.05) * 0.35
    s += noise(n) * env(n, 0.001, 0.025, r=0.05) * 0.45
    return np.tanh(s * 1.8) * 0.7

def sfx_lock():  # ロックオン確定
    n = int(0.18 * SR)
    half = n // 2
    s = np.zeros(n)
    s[:half] += tone(880, half) * env(half, 0.005, 0.03, sl=0.5, r=0.05) * 0.4
    s[half:] += tone(1320, n - half) * env(n - half, 0.005, 0.03, sl=0.5, r=0.06) * 0.45
    return s

def sfx_wreck():  # 大破
    n = int(1.0 * SR)
    s = lowpass(noise(n), 0.05) * env(n, 0.002, 0.4, sl=0.5, r=0.5) * 0.8
    s += tone(70, n) * env(n, 0.002, 0.3, sl=0.4, r=0.6) * 0.5
    return s

def sfx_sell():  # 売却/コイン
    n = int(0.3 * SR)
    s = np.zeros(n)
    for i, f in enumerate([1046, 1318, 1568]):
        st = int(i * 0.06 * SR)
        seg = tone(f, n - st) * env(n - st, 0.002, 0.05, sl=0.3, r=0.1) * 0.3
        s[st:] += seg
    return s

# ---------------- BGM(ループ) ----------------

def synth_chord(freqs, n, kind="tri", amp=0.2):
    s = np.zeros(n)
    for f in freqs:
        s += tone(f, n, kind) * amp / len(freqs)
    return s

def note(freq, dur, kind="tri", amp=0.25, a=0.02, r=0.2):
    n = int(dur * SR)
    return tone(freq, n, kind) * env(n, a, dur * 0.3, sl=0.7, r=r) * amp

NOTES = {"C3":130.81,"D3":146.83,"E3":164.81,"F3":174.61,"G3":196.00,"A3":220.00,"B3":246.94,
         "C4":261.63,"D4":293.66,"E4":329.63,"F4":349.23,"G4":392.00,"A4":440.00,"B4":493.88,
         "C5":523.25,"D5":587.33,"E5":659.25,"G5":783.99,"A2":110.0,"D2":73.42,"F2":87.31,"G2":98.0,"C2":65.41}

def bgm_sea():
    # 16秒・少し冒険的だが穏やか(Dマイナー系のアルペジオ+パッド)
    dur = 16.0; n = int(dur * SR); s = np.zeros(n)
    # パッドコード進行 Dm - Bb - F - C (各4秒)
    chords = [["D3","F3","A3"],["A2","D3","F3"],["F2","A3","C4"],["G2","B3","D4"]]
    seg = n // 4
    for i, ch in enumerate(chords):
        c = synth_chord([NOTES[x] for x in ch], seg, "tri", 0.16)
        c *= env(seg, 0.3, 1.0, sl=0.8, r=0.5)
        s[i*seg:(i+1)*seg] += c
    # アルペジオ(上物)
    arp = ["D4","A4","F4","A4","D5","A4","F4","A4"]
    step = int(0.5 * SR)
    for k in range(int(dur / 0.5)):
        f = NOTES[arp[k % len(arp)]]
        st = k * step
        if st + step <= n:
            s[st:st+step] += note(f, 0.5, "sine", 0.12, 0.01, 0.15)[:step]
    return s * 0.8

def bgm_port():
    # 16秒・暖かく落ち着いた(Cメジャー系)
    dur = 16.0; n = int(dur * SR); s = np.zeros(n)
    chords = [["C3","E3","G3"],["A2","C4","E4"],["F2","A3","C4"],["G2","B3","D4"]]
    seg = n // 4
    for i, ch in enumerate(chords):
        c = synth_chord([NOTES[x] for x in ch], seg, "tri", 0.18)
        c *= env(seg, 0.4, 1.2, sl=0.85, r=0.6)
        s[i*seg:(i+1)*seg] += c
    mel = ["E4","G4","C5","G4","A4","G4","E4","D4"]
    step = int(1.0 * SR)
    for k in range(int(dur)):
        f = NOTES[mel[k % len(mel)]]
        st = k * step
        if st + step <= n:
            s[st:st+step] += note(f, 1.0, "sine", 0.1, 0.05, 0.4)[:step]
    return s * 0.8


if __name__ == "__main__":
    np.random.seed(7)
    save("sfx_gun.wav", sfx_gun())
    save("sfx_cannon.wav", sfx_cannon())
    save("sfx_harpoon.wav", sfx_harpoon())
    save("sfx_torpedo.wav", sfx_torpedo())
    save("sfx_hit.wav", sfx_hit())
    save("sfx_enemy_hit.wav", sfx_enemy_hit())
    save("sfx_lock.wav", sfx_lock())
    save("sfx_wreck.wav", sfx_wreck())
    save("sfx_sell.wav", sfx_sell())
    save("bgm_sea.wav", bgm_sea(), loop=True)
    save("bgm_port.wav", bgm_port(), loop=True)
    print("done")
