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

def sfx_crit():  # #233: クリティカル。sfx_enemy_hitを土台に、より高音で派手に
    # 土台は sfx_enemy_hit と同じ構成を約1.5倍の高さへ移した「軽くて鋭い」インパクト。
    # そこへ金属的な余韻(非整数倍音)と短いきらめきを重ねる。
    # 注意: 連続グリッサンドを長く伸ばすとスライドホイッスル(コミカル)になるので、
    #       上昇は 25ms 以内に収め、以降は固定ピッチの余韻で聴かせる。
    n = int(0.34 * SR)
    t = np.arange(n) / SR
    s = tone(330, n) * env(n, 0.001, 0.05, r=0.07) * 0.55
    s += tone(645, n) * env(n, 0.001, 0.03, r=0.05) * 0.35
    s += noise(n) * env(n, 0.0005, 0.02, r=0.04) * 0.40
    # 立ち上がり25msだけ 1500→2400Hz へ跳ね上げるアタック(高音の"チン"の芯)
    g = int(0.025 * SR)
    gf = 1500 + 900 * np.linspace(0.0, 1.0, g)
    s[:g] += np.sin(2 * np.pi * np.cumsum(gf) / SR) * np.linspace(1.0, 0.55, g) * 0.5
    # 金属的な余韻: 非整数倍音を重ねて鐘のような響きに(整数倍だと単なる高い音になる)
    for f, amp in ((2400.0, 0.30), (3570.0, 0.20), (4830.0, 0.13), (6210.0, 0.08)):
        s += np.sin(2 * np.pi * f * t) * np.exp(-t * (9.0 + f / 900.0)) * amp
    # きらめき(高域ノイズの短い残り香)
    s += (noise(n) - lowpass(noise(n), 0.35)) * np.exp(-t * 16.0) * 0.16
    return np.tanh(s * 1.9) * 0.85

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

def sfx_horn():  # #278(提案7-4): 入港・出港の汽笛。低い基音+倍音でゆっくり立ち上げて伸ばす
    n = int(1.6 * SR)
    s = np.zeros(n)
    base = 116.0
    for k, amp in [(1.0, 0.55), (1.5, 0.22), (2.0, 0.18), (3.0, 0.08)]:
        s += tone(base * k, n, "sine") * amp
    # わずかにうねらせて汽笛らしい厚みを出す
    t = np.arange(n) / SR
    s *= 1.0 + 0.06 * np.sin(2 * np.pi * 5.5 * t)
    s *= env(n, 0.18, 0.25, sl=0.8, r=0.6)
    s += lowpass(noise(n), 0.02) * env(n, 0.2, 0.3, sl=0.25, r=0.6) * 0.10   # 蒸気のかすれ
    return s * 0.8

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

def bgm_boss():
    # #79: 主遭遇時の緊迫BGM(8秒ループ・短調・刻むベース+不穏なアルペジオ)
    dur = 8.0; n = int(dur * SR); s = np.zeros(n)
    # 刻む低音(8分刻み Dm)
    step = int(0.25 * SR)
    bass = ["D2", "D2", "F2", "D2", "A2", "D2", "F2", "G2"] * 4
    for k in range(int(dur / 0.25)):
        st = k * step
        if st + step <= n:
            seg = tone(NOTES[bass[k % len(bass)]], step, "saw") * env(step, 0.005, 0.08, sl=0.3, r=0.06) * 0.28
            s[st:st+step] += seg
    # 不穏なパッド(減和音っぽく)
    chords = [["D3","F3","G3"], ["D3","F3","A3"]]
    seg2 = n // 2
    for i, ch in enumerate(chords):
        c = synth_chord([NOTES[x] for x in ch], seg2, "tri", 0.13)
        c *= env(seg2, 0.2, 0.8, sl=0.85, r=0.4)
        s[i*seg2:(i+1)*seg2] += c
    # 高音の警笛的アルペジオ
    arp = ["D5", "A4", "F4", "A4"]
    step3 = int(0.5 * SR)
    for k in range(int(dur / 0.5)):
        st = k * step3
        if st + step3 <= n:
            s[st:st+step3] += note(NOTES[arp[k % len(arp)]], 0.5, "square", 0.05, 0.01, 0.1)[:step3]
    # ドラム的ノイズ(1拍目)
    for k in range(int(dur)):
        st = int(k * SR)
        dn = int(0.12 * SR)
        if st + dn <= n:
            s[st:st+dn] += lowpass(noise(dn), 0.2) * env(dn, 0.001, 0.05, r=0.05) * 0.5
    return np.tanh(s * 1.4) * 0.75

def bgm_ending():
    # #80: エンディング用の厳かなBGM(24秒・遅いコラール+鐘)
    dur = 24.0; n = int(dur * SR); s = np.zeros(n)
    chords = [["C3","G3","C4","E4"], ["A2","E3","A3","C4"], ["F2","C3","F3","A3"], ["G2","D3","G3","B3"],
              ["C3","G3","C4","E4"], ["F2","C3","F3","A3"]]
    seg = n // len(chords)
    for i, ch in enumerate(chords):
        c = synth_chord([NOTES[x] for x in ch], seg, "sine", 0.22)
        c += synth_chord([NOTES[x] * 2 for x in ch], seg, "tri", 0.05)
        c *= env(seg, 0.8, 1.5, sl=0.9, r=1.2)
        s[i*seg:(i+1)*seg] += c
    # 鐘の音(倍音を重ねる)
    bells = [(0.0, "C5"), (4.0, "G4"), (8.0, "E5"), (12.0, "C5"), (16.0, "G4"), (20.0, "C5")]
    for t0, nn in bells:
        st = int(t0 * SR)
        bn = int(3.0 * SR)
        if st + bn <= n:
            f = NOTES[nn]
            bell = np.zeros(bn)
            for h, amp in [(1.0, 0.20), (2.76, 0.08), (5.4, 0.03)]:
                bell += tone(f * h, bn) * np.exp(-np.arange(bn) / SR * (1.2 * h)) * amp
            s[st:st+bn] += bell
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
    save("sfx_crit.wav", sfx_crit())   # #233
    save("sfx_lock.wav", sfx_lock())
    save("sfx_wreck.wav", sfx_wreck())
    save("sfx_sell.wav", sfx_sell())
    save("sfx_horn.wav", sfx_horn())   # #278(提案7-4)
    save("bgm_sea.wav", bgm_sea(), loop=True)
    save("bgm_port.wav", bgm_port(), loop=True)
    save("bgm_boss.wav", bgm_boss(), loop=True)
    save("bgm_ending.wav", bgm_ending(), loop=True)
    print("done")
