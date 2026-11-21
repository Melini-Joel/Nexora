# Uso: python3 tools/gen_audio.py audio   (requiere numpy y scipy)
# Genera todos los sonidos y la música de NEXORA por síntesis (sin samples externos).
import numpy as np, wave, os, sys
SR = 22050
OUT = sys.argv[1]
rng = np.random.default_rng(7)

def t(d): return np.arange(int(SR * d)) / SR
def env_ad(n, a, d):  # ataque lineal + caída exponencial
    x = np.arange(n) / SR
    e = np.minimum(x / max(a, 1e-4), 1.0) * np.exp(-np.maximum(x - a, 0) / d)
    return e
def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR); y = np.zeros_like(x); acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc; y[i] = acc
    return y
def lp_fast(x, cutoff):  # filtro de un polo vectorizado aproximado (por bloques)
    from scipy.signal import lfilter
    a = np.exp(-2 * np.pi * cutoff / SR)
    return lfilter([1 - a], [1, -a], x)
def hp(x, cutoff):
    return x - lp_fast(x, cutoff)
def bp(x, lo, hi): return hp(lp_fast(x, hi), lo)
def noise(d): return rng.uniform(-1, 1, int(SR * d))
def norm(x, peak=0.9):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak
def fade(x, fin=0.005, fout=0.02):
    n = len(x); a = int(SR * fin); b = int(SR * fout)
    if a: x[:a] *= np.linspace(0, 1, a)
    if b: x[-b:] *= np.linspace(1, 0, b)
    return x
def save(name, x, peak=0.9):
    x = norm(np.asarray(x, dtype=float), peak)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())
def echo(x, delay=0.23, fb=0.35, taps=4):
    y = x.copy(); d = int(SR * delay)
    for k in range(1, taps + 1):
        if d * k < len(x): y[d * k:] += x[:-d * k] * (fb ** k)
    return y
def loop_echo(x, delay=0.31, fb=0.4, taps=5):  # eco circular para loops sin corte
    y = x.copy(); d = int(SR * delay)
    for k in range(1, taps + 1): y += np.roll(x, d * k) * (fb ** k)
    return y
def note(f): return 440.0 * 2 ** ((f - 69) / 12)

# --- Efectos -------------------------------------------------------------------------------
for i in range(3):  # pasos sobre pasto/tierra
    n = noise(0.14); x = lp_fast(n, 900 + 250 * i) * env_ad(len(n), 0.004, 0.035)
    x += np.sin(2 * np.pi * (70 + 10 * i) * t(0.14)) * env_ad(len(n), 0.002, 0.03) * 0.6
    save("step_%d" % (i + 1), fade(x), 0.6)
d = 0.35; n = len(t(d))  # hachazo en madera
x = np.sin(2 * np.pi * 110 * t(d)) * env_ad(n, 0.002, 0.06) + 0.5 * np.sin(2 * np.pi * 420 * t(d)) * env_ad(n, 0.001, 0.04)
x += bp(noise(d), 300, 3000) * env_ad(n, 0.001, 0.025) * 0.9
save("chop", fade(x))
d = 0.45; n = len(t(d))  # pico en piedra
x = sum(np.sin(2 * np.pi * f * t(d)) * env_ad(n, 0.001, dd) * a for f, dd, a in [(1850, 0.09, 0.6), (2730, 0.06, 0.4), (3900, 0.04, 0.3), (640, 0.05, 0.4)])
x += hp(noise(d), 2500) * env_ad(n, 0.0005, 0.012)
save("pick", fade(x), 0.75)
d = 0.3; n = len(t(d))  # arrancar planta / bayas
x = bp(noise(d), 1500, 6000) * env_ad(n, 0.02, 0.07) * (0.6 + 0.4 * np.sin(2 * np.pi * 35 * t(d)))
save("pluck", fade(x), 0.5)
d = 0.28; n = len(t(d))  # golpe al aire
tt = t(d); sweep = bp(noise(d), 400, 2500) * np.sin(np.pi * np.clip(tt / d, 0, 1)) ** 2
save("swing", fade(sweep), 0.45)
d = 0.25; n = len(t(d))  # golpe que conecta
x = np.sin(2 * np.pi * 90 * t(d) * (1 - t(d))) * env_ad(n, 0.001, 0.05) + bp(noise(d), 800, 5000) * env_ad(n, 0.0005, 0.02)
save("hit", fade(x))
d = 0.35; n = len(t(d))  # te lastiman
x = np.sin(2 * np.pi * 70 * t(d)) * env_ad(n, 0.003, 0.09) + lp_fast(noise(d), 500) * env_ad(n, 0.001, 0.06) * 0.8
save("hurt", fade(x))
d = 0.4; n = len(t(d)); tt = t(d)  # criatura herida (gruñido)
f = 160 * (1 + 0.15 * np.sin(2 * np.pi * 18 * tt)); ph = 2 * np.pi * np.cumsum(f) / SR
x = lp_fast(np.sign(np.sin(ph)) * 0.5 + np.sin(ph * 2), 1200) * env_ad(n, 0.01, 0.12)
x += bp(noise(d), 300, 2000) * env_ad(n, 0.005, 0.08) * 0.5
save("creature_hurt", fade(x), 0.7)
d = 0.9; n = len(t(d)); tt = t(d)  # criatura muere
f = 180 * np.exp(-tt * 1.6); ph = 2 * np.pi * np.cumsum(f) / SR
x = lp_fast(np.sign(np.sin(ph)) * 0.4 + np.sin(ph), 900) * env_ad(n, 0.02, 0.35) + lp_fast(noise(d), 300) * env_ad(n, 0.3, 0.2) * 0.4
save("creature_die", fade(x, 0.005, 0.1), 0.7)
d = 1.6; n = len(t(d)); tt = t(d)  # susurro de las sombras
x = bp(noise(d), 600, 2200) * (0.5 + 0.5 * np.sin(2 * np.pi * 5 * tt)) * np.sin(np.pi * tt / d) ** 2
x += np.sin(2 * np.pi * 95 * tt + np.sin(2 * np.pi * 0.7 * tt) * 3) * np.sin(np.pi * tt / d) * 0.3
save("shade_whisper", fade(echo(x, 0.17, 0.4)), 0.5)
d = 0.14; n = len(t(d))  # recoger algo
x = np.concatenate([np.sin(2 * np.pi * 880 * t(0.06)) * env_ad(len(t(0.06)), 0.002, 0.03), np.sin(2 * np.pi * 1320 * t(0.08)) * env_ad(len(t(0.08)), 0.002, 0.05)])
save("pickup", fade(x), 0.45)
parts = []  # fabricación terminada (campanita do-mi-sol)
for k, m in enumerate([72, 76, 79]):
    dd = 0.5; nn = len(t(dd)); s = np.zeros(int(SR * 0.7))
    tone = (np.sin(2 * np.pi * note(m) * t(dd)) + 0.3 * np.sin(2 * np.pi * note(m) * 2.76 * t(dd))) * env_ad(nn, 0.003, 0.18)
    off = int(SR * 0.08 * k); s[off:off + nn] += tone; parts.append(s)
save("craft_done", fade(echo(sum(parts), 0.12, 0.3)), 0.5)
d = 0.5; x = np.zeros(int(SR * d))  # construir (dos martillazos)
for off in (0.0, 0.2):
    nn = len(t(0.18)); k = int(SR * off)
    x[k:k + nn] += (np.sin(2 * np.pi * 150 * t(0.18)) * env_ad(nn, 0.001, 0.04) + bp(noise(0.18), 500, 4000) * env_ad(nn, 0.0005, 0.015))
save("build", fade(x))
d = 0.6; n = len(t(d)); tt = t(d)  # puerta (crujido)
f = 220 + 140 * tt / d + rng.normal(0, 25, n); ph = 2 * np.pi * np.cumsum(f) / SR
x = bp(np.sign(np.sin(ph)) * (rng.random(n) > 0.35), 300, 2500) * np.sin(np.pi * tt / d) * 0.8
save("door", fade(x), 0.5)
d = 0.55; n = len(t(d)); tt = t(d)  # cofre
f = 300 + 80 * tt / d; ph = 2 * np.pi * np.cumsum(f) / SR
x = bp(np.sign(np.sin(ph)) * (rng.random(n) > 0.4), 400, 2500) * np.sin(np.pi * np.clip(tt / 0.35, 0, 1)) * 0.6
k = int(SR * 0.38); nn = len(t(0.15)); x[k:k + nn] += np.sin(2 * np.pi * 120 * t(0.15)) * env_ad(nn, 0.001, 0.04)
save("chest_open", fade(x), 0.55)
d = 0.55; x = np.zeros(int(SR * d))  # comer
for off in (0.0, 0.18, 0.36):
    nn = len(t(0.12)); k = int(SR * off); x[k:k + nn] += bp(noise(0.12), 900, 5000) * env_ad(nn, 0.004, 0.03)
save("eat", fade(x), 0.5)
save("ui_click", fade(np.sin(2 * np.pi * 1600 * t(0.04)) * env_ad(len(t(0.04)), 0.001, 0.01)), 0.35)
save("ui_hover", fade(np.sin(2 * np.pi * 2400 * t(0.03)) * env_ad(len(t(0.03)), 0.001, 0.006)), 0.15)
x = np.zeros(int(SR * 2.0))  # misión completada (fanfarria)
for k, (m, dd) in enumerate([(67, 0.15), (72, 0.15), (76, 0.15), (79, 0.9)]):
    nn = len(t(dd + 0.3)); off = int(SR * 0.14 * k)
    tone = sum(np.sin(2 * np.pi * note(m) * h * t(dd + 0.3)) / h for h in (1, 2, 3)) * env_ad(nn, 0.005, dd * 0.8 + 0.1)
    x[off:off + nn] += tone
save("quest_complete", fade(echo(x, 0.18, 0.3)), 0.55)
d = 3.0; n = len(t(d)); tt = t(d)  # cae la noche (acorde grave)
x = sum(lp_fast(np.sign(np.sin(2 * np.pi * note(m) * tt * (1 + det))), 600) for m in (38, 45, 50, 53) for det in (0, 0.003))
x *= np.minimum(tt / 1.2, 1) * np.exp(-np.maximum(tt - 1.4, 0) / 0.8)
save("night_sting", fade(echo(x, 0.29, 0.4)), 0.45)
d = 4.0; n = len(t(d)); tt = t(d)  # trueno
brown = np.cumsum(rng.normal(0, 1, n)); brown -= lp_fast(brown, 5)
x = lp_fast(brown, 180) * env_ad(n, 0.05, 1.1) * (1 + 0.6 * np.sin(2 * np.pi * 3 * tt))
x += bp(noise(d), 1000, 6000) * env_ad(n, 0.002, 0.08) * 0.4
save("thunder", fade(x, 0.002, 0.3), 0.85)

# --- Ambientes en loop -----------------------------------------------------------------------
def make_loop(x, xfade=0.5):  # empalma el final con el principio
    k = int(SR * xfade); y = x[:-k].copy(); y[:k] = y[:k] * np.linspace(0, 1, k) + x[-k:] * np.linspace(1, 0, k)
    return y
d = 8.0; tt = t(d + 0.5)
save("amb_wind", make_loop(bp(noise(d + 0.5), 150, 900) * (0.55 + 0.45 * np.sin(2 * np.pi * tt / (d + 0.5) * 2) ** 2)), 0.5)
save("amb_rain", make_loop(hp(noise(4.5), 1200) * 0.7 + lp_fast(noise(4.5), 400) * 0.3), 0.55)
n = len(t(4.5)); fire = lp_fast(np.cumsum(rng.normal(0, 1, n)), 300); fire -= lp_fast(fire, 3)
pops = np.zeros(n)
for _ in range(60):
    k = rng.integers(0, n - 400); pops[k:k + 300] += bp(noise(300 / SR), 1000, 6000) * env_ad(300, 0.0005, 0.004) * rng.uniform(0.3, 1)
save("amb_fire", make_loop(norm(fire) * 0.6 + pops), 0.6)
d = 8.5; tt = t(d); swell = np.sin(np.pi * tt / d * 2) ** 2
save("amb_waves", make_loop(lp_fast(noise(d), 700) * (0.25 + 0.75 * swell)), 0.5)
d = 6.5; n = len(t(d)); x = bp(noise(d), 200, 700) * 0.15  # grillos de noche
for start in np.arange(0, d - 0.4, 0.55):
    for c in range(3):
        k = int(SR * (start + c * 0.06 + rng.uniform(0, 0.02))); nn = len(t(0.035))
        if k + nn < n: x[k:k + nn] += np.sin(2 * np.pi * 4300 * t(0.035)) * env_ad(nn, 0.003, 0.01) * 0.5
save("amb_night", make_loop(x), 0.4)

# --- Música (loops de 32 s) ------------------------------------------------------------------
def pad(chord, dur, bright=900):
    tt = t(dur); x = np.zeros(len(tt))
    for m in chord:
        for det in (-0.004, 0.004):
            ph = 2 * np.pi * note(m) * (1 + det) * tt
            x += (2 * np.abs(2 * (ph / (2 * np.pi) % 1) - 1) - 1)  # triangular
    x = lp_fast(x, bright)
    e = np.minimum(tt / 1.5, 1) * np.minimum((dur - tt) / 1.5, 1)
    return x * e
def pluck(m, dur=1.2, decay=0.35):
    tt = t(dur)
    return sum(np.sin(2 * np.pi * note(m) * h * tt) / (h * h) for h in (1, 2, 3)) * env_ad(len(tt), 0.004, decay)
def song(chords, melody, bar=4.0, bright=900, mel_decay=0.4, mel_gain=0.35, bass=True):
    total = int(SR * bar * len(chords)); x = np.zeros(total)
    for i, ch in enumerate(chords):
        p = pad(ch, bar + 1.5, bright); k = int(SR * bar * i)
        seg = p[: total - k] if k + len(p) > total else p
        x[k:k + len(seg)] += seg * 0.18
        if k + len(p) > total: x[: k + len(p) - total] += p[total - k:] * 0.18
        if bass:
            b = pluck(ch[0] - 12, bar, 1.2) * 0.5; x[k:k + len(b)] += b[: total - k]
    for (beat, m) in melody:
        k = int(SR * beat * bar / 4); p = pluck(m, 1.6, mel_decay) * mel_gain
        end = min(total, k + len(p)); x[k:end] += p[: end - k]
        if k + len(p) > total: x[: k + len(p) - total] += p[total - k:]
    return loop_echo(x, 0.375, 0.35, 4)
day_chords = [[60, 64, 67], [57, 60, 64], [65, 69, 72], [55, 59, 62], [60, 64, 67], [57, 60, 64], [65, 69, 72], [67, 71, 74]]
penta = [72, 74, 76, 79, 81, 84]
mel = []
r = np.random.default_rng(3)
for beat in range(0, 32):
    if r.random() < 0.55: mel.append((beat, int(r.choice(penta))))
save("music_day", song(day_chords, mel, 4.0, 1100, 0.45, 0.3), 0.55)
night_chords = [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 49, 52]] * 2
mel = [(b, int(r.choice([62, 65, 67, 69, 70]))) for b in range(0, 32, 3) if r.random() < 0.6]
save("music_night", song(night_chords, mel, 4.0, 650, 0.9, 0.25), 0.5)
menu_chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]] * 2
mel = [(b, int(r.choice([69, 72, 74, 76, 79]))) for b in range(0, 32, 2) if r.random() < 0.7]
save("music_menu", song(menu_chords, mel, 4.0, 800, 0.7, 0.3), 0.55)
print("ok", len(os.listdir(OUT)), "archivos")
