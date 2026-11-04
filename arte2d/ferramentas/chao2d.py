# chao2d.py: texturas 2D do chão em pixel art (estilo realista e escuro dos sprites), já na vista de 35°:
# 1 tile = 35 × 20 px. Cada textura emenda sem costura (140 × 80 = 4 × 4 tiles); água em 8 quadros; piso por tile.
# Roda no Python do Blender (numpy): blender -b --python chao2d.py -- <pasta_saida>
import bpy, sys, os, math
import numpy as np
SAIDA = sys.argv[sys.argv.index('--') + 1]
os.makedirs(SAIDA, exist_ok=True)
W, H = 140, 80
BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0


def salvar(arr, caminho):
    h, w = arr.shape[:2]
    if arr.shape[2] == 3:
        arr = np.concatenate([arr, np.ones((h, w, 1))], axis=2)
    im = bpy.data.images.new('t', w, h, alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(np.clip(arr, 0, 1)[::-1]).astype(np.float32).ravel())
    im.filepath_raw = caminho; im.file_format = 'PNG'; im.save(); bpy.data.images.remove(im)


def ruido(w, h, cx, cy, sem, oit=4):
    """ruído de valor que emenda (períodos inteiros), 0..1."""
    rng = np.random.default_rng(sem); tot = np.zeros((h, w)); amp = 1.0; soma = 0
    for o in range(oit):
        gx, gy = cx * 2 ** o, cy * 2 ** o
        g = rng.random((gy, gx))
        xs = np.arange(w) * gx / w; ys = np.arange(h) * gy / h
        x0 = np.floor(xs).astype(int); y0 = np.floor(ys).astype(int)
        fx = xs - x0; fy = ys - y0
        fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
        x1 = (x0 + 1) % gx; y1 = (y0 + 1) % gy
        a = g[np.ix_(y0, x0)]; b = g[np.ix_(y0, x1)]; c = g[np.ix_(y1, x0)]; d = g[np.ix_(y1, x1)]
        v = (a * (1 - fx) + b * fx) * (1 - fy)[:, None] + (c * (1 - fx) + d * fx) * fy[:, None]
        tot += v * amp; soma += amp; amp *= 0.5
    return tot / soma


def paleta(base, n=5, faixa=(0.55, 1.12)):
    """tons do escuro ao claro a partir da cor média; escurece e tira um pouco de saturação (estilo dos sprites)."""
    base = np.array(base, dtype=float)
    cinza = base.mean(); base = cinza + (base - cinza) * 0.82
    return [np.clip(base * (faixa[0] + (faixa[1] - faixa[0]) * k / (n - 1)) * 0.86, 0, 1) for k in range(n)]


def quantizar(v, tons):
    """valor 0..1 → índice de tom com pontilhado ordenado nas passagens."""
    n = len(tons); h, w = v.shape
    lim = BAYER[np.arange(h)[:, None] % 4, np.arange(w)[None, :] % 4]
    idx = np.clip(np.floor(v * n + (lim - 0.5) * 0.9), 0, n - 1).astype(int)
    return np.array(tons)[idx]


def contraste(v, k=1.6):
    return np.clip((v - 0.5) * k + 0.5, 0, 1)


def pinta(img, ys, xs, cor):
    img[ys % H, xs % W] = cor


rng = np.random.default_rng(7)


def campina():
    t = paleta((0.25, 0.36, 0.17)); v = contraste(ruido(W, H, 4, 2, 1)); img = quantizar(v, t)
    for _ in range(170):                                      # tufos: ponta clara e pé escuro, abertos em V
        x, y = rng.integers(0, W), rng.integers(0, H); k = int(rng.integers(3, 5))
        pinta(img, np.array([y, y]), np.array([x - 1, x + 1]), t[k]); pinta(img, np.array([y + 1]), np.array([x]), t[k - 1])
        pinta(img, np.array([y + 2]), np.array([x]), t[max(0, k - 3)])
    for _ in range(10):
        x, y = rng.integers(0, W), rng.integers(0, H); pinta(img, np.array([y]), np.array([x]), (0.78, 0.72, 0.42))
    return img


def fungica():
    t = paleta((0.21, 0.15, 0.22)); img = quantizar(contraste(ruido(W, H, 4, 2, 2)), t)
    for _ in range(26):                                       # veios de micélio (passeio aleatório)
        x, y = rng.integers(0, W), rng.integers(0, H); d = rng.random() * 6.28
        for s in range(rng.integers(8, 22)):
            d += rng.normal(0, 0.5); x += math.cos(d); y += math.sin(d) * 0.6
            pinta(img, np.array([int(y)]), np.array([int(x)]), t[4] * np.array([1.05, 0.95, 1.15]))
    for _ in range(14):
        x, y = rng.integers(0, W), rng.integers(0, H); pinta(img, np.array([y]), np.array([x]), (0.62, 0.42, 0.78))
    return img


def deserto():
    t = paleta((0.62, 0.52, 0.36)); n = ruido(W, H, 4, 2, 3)
    on = 0.5 + 0.5 * np.sin((np.arange(H)[:, None] * 2 * math.pi / 10) + n * 5)   # ondulações deitadas
    img = quantizar(contraste(0.6 * n + 0.4 * on, 1.3), t)
    for _ in range(70):                                       # sílex: 2 × 1 escuro com brilho
        x, y = rng.integers(0, W), rng.integers(0, H)
        pinta(img, np.array([y, y]), np.array([x, x + 1]), (0.22, 0.22, 0.24)); pinta(img, np.array([y - 1]), np.array([x]), (0.55, 0.55, 0.58))
    return img


def planalto():
    t = paleta((0.40, 0.39, 0.37)); img = quantizar(contraste(ruido(W, H, 3, 2, 4), 1.8), t)
    for _ in range(9):                                        # rachaduras longas, quase retas, com galhos curtos
        x, y = float(rng.integers(0, W)), float(rng.integers(0, H)); d = rng.random() * 6.28
        for s in range(int(rng.integers(18, 40))):
            d += rng.normal(0, 0.18); x += math.cos(d); y += math.sin(d) * 0.57
            pinta(img, np.array([int(y)]), np.array([int(x)]), t[0] * 0.75)
            if rng.random() < 0.06:
                bx, by, bd = x, y, d + rng.choice([-1.1, 1.1])
                for _ in range(int(rng.integers(3, 7))):
                    bx += math.cos(bd); by += math.sin(bd) * 0.57
                    pinta(img, np.array([int(by)]), np.array([int(bx)]), t[1])
    return img


def cristal():
    t = paleta((0.52, 0.52, 0.60)); img = quantizar(contraste(ruido(W, H, 4, 2, 5), 1.4), t)
    for _ in range(16):                                       # brilhos de cristal (losango de 3 px + ponto)
        x, y = rng.integers(0, W), rng.integers(0, H); c = np.array((0.82, 0.78, 0.98))
        pinta(img, np.array([y - 1, y, y, y + 1]), np.array([x, x - 1, x + 1, x]), c * 0.8); pinta(img, np.array([y]), np.array([x]), c)
    return img


def pantano():
    t = paleta((0.25, 0.25, 0.13)); n = ruido(W, H, 4, 2, 6); img = quantizar(contraste(n, 1.3), t)
    poca = ruido(W, H, 3, 2, 16) > 0.62                        # poças escuras com reflexo na borda de cima
    img[poca] = np.array((0.08, 0.10, 0.08))
    borda = poca & ~np.roll(poca, 1, axis=0)
    img[borda] = np.array((0.20, 0.24, 0.20))
    for _ in range(60):
        x, y = rng.integers(0, W), rng.integers(0, H)
        if not poca[y % H, x % W]:
            pinta(img, np.array([y, y - 1, y - 2]), np.array([x, x, x]), t[3])
    return img


def cinzal():
    t = paleta((0.33, 0.31, 0.30)); img = quantizar(contraste(ruido(W, H, 4, 2, 7), 1.5), t)
    for _ in range(40):                                       # brasas e ferrugem
        x, y = rng.integers(0, W), rng.integers(0, H)
        pinta(img, np.array([y]), np.array([x]), (0.55, 0.20, 0.08) if rng.random() < 0.6 else (0.85, 0.42, 0.12))
    return img


def praia():
    t = paleta((0.70, 0.62, 0.46), faixa=(0.75, 1.1)); img = quantizar(contraste(ruido(W, H, 4, 2, 8), 1.2), t)
    for _ in range(25):
        x, y = rng.integers(0, W), rng.integers(0, H); pinta(img, np.array([y]), np.array([x]), (0.85, 0.82, 0.74))
    return img


def jazida():
    t = paleta((0.27, 0.25, 0.28)); return quantizar(contraste(ruido(W, H, 4, 2, 9), 1.5), t)


def agua(funda, q, N=8):
    base = (0.07, 0.14, 0.22) if funda else (0.12, 0.28, 0.30)
    t = paleta(base, faixa=(0.7, 1.15))
    u = q / N
    # ondas: ruído andando em x (período inteiro → o laço fecha), linhas claras curtas
    n1 = ruido(W, H, 4, 2, 10 + funda); n2 = ruido(W, H, 8, 4, 20 + funda)
    desl = int(round(u * W / 2)) * 2
    n = 0.6 * np.roll(n1, desl // 2, axis=1) + 0.4 * np.roll(n2, -desl, axis=1)
    img = quantizar(contraste(n, 1.2), t)
    crista = (np.roll(n2, -desl, axis=1) > 0.70) & (np.roll(np.roll(n2, -desl, axis=1), 1, axis=0) <= 0.70)
    img[crista] = np.clip(np.array(t[4]) * 1.35 + 0.05, 0, 1)
    return img


def piso():
    """um tile (35 × 20): duas fiadas de blocos de pedra vistas a 35°, rejunte escuro, quina de cima clara."""
    tw, th = 35, 20; img = np.zeros((th, tw, 3)) + 0.10
    r = np.random.default_rng(11)
    for fi, y0 in enumerate((0, 10)):
        cortes = [0, 17, 35] if fi == 0 else [0, 9, 26, 35]
        for a, b in zip(cortes, cortes[1:]):
            tom = 0.33 + r.random() * 0.08
            bloco = np.zeros((9, b - a - 1, 3)) + np.array((tom, tom * 0.98, tom * 0.93))
            bloco[0] *= 1.12; bloco[-1] *= 0.86; bloco[:, 0] *= 1.05
            suj = r.random(bloco.shape[:2]) < 0.10; bloco[suj] *= 0.8
            img[y0:y0 + 9, a:b - 1] = bloco
    return img


for nome, f in (('campina', campina), ('floresta_fungica', fungica), ('deserto_silex', deserto), ('planalto_rochoso', planalto),
                ('campo_cristal', cristal), ('pantano', pantano), ('cinzal', cinzal), ('praia', praia), ('jazida', jazida)):
    salvar(f(), os.path.join(SAIDA, nome + '.png'))
for funda in (0, 1):
    salvar(np.concatenate([agua(funda, q) for q in range(8)], axis=1), os.path.join(SAIDA, ('agua_funda' if funda else 'agua_rasa') + '.png'))
salvar(piso(), os.path.join(SAIDA, 'piso_fabrica.png'))
print('CHAO ok')
