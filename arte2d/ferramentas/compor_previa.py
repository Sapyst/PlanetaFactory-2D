# compor_previa.py: monta uma cena 2D estática com o chão novo e os sprites, a partir de um pedaço real do mundo.
# blender -b --python compor_previa.py -- <mundo.json> <saida.png>
import bpy, sys, os, json, math
import numpy as np
A = sys.argv[sys.argv.index('--') + 1:]
D = '/mnt/d/Projetos/Jogos/PlanetaFactory_2D'
M = json.load(open(A[0])); SAIDA = A[1]
IND = json.load(open(D + '/indice.json'))
TW, TH = 35, 20
x0, y0, w, h = M['x0'], M['y0'], M['w'], M['h']
ytop = y0 + h                                     # norte em cima
WP, HP = w * TW, h * TH


def ler(c):
    im = bpy.data.images.load(c); W_, H_ = im.size
    a = np.empty(W_ * H_ * 4, dtype=np.float32); im.pixels.foreach_get(a); bpy.data.images.remove(im)
    return a.reshape(H_, W_, 4)[::-1].copy()


def salvar(arr, c):
    hh, ww = arr.shape[:2]; im = bpy.data.images.new('s', ww, hh, alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).astype(np.float32).ravel())
    im.filepath_raw = c; im.file_format = 'PNG'; im.save(); bpy.data.images.remove(im)


TEX = {n: ler(f'{D}/chao/{n}.png')[..., :3] for n in ('campina', 'floresta_fungica', 'deserto_silex', 'planalto_rochoso',
       'campo_cristal', 'pantano', 'cinzal', 'praia', 'jazida')}
TEX['agua_rasa'] = ler(D + '/chao/agua_rasa.png')[:, :140, :3]; TEX['agua_funda'] = ler(D + '/chao/agua_funda.png')[:, :140, :3]
PISO = ler(D + '/chao/piso_fabrica.png')[..., :3]

# camada por tile
ter = np.array(M['terreno']).reshape(h, w); bio = np.array(M['bioma']).reshape(h, w)
agua = ter >= 2
terra = ~agua & (ter != 1)
# água rasa: até 2 tiles da terra/praia
from_terra = ~agua
rasa = np.zeros_like(agua)
for dy in range(-2, 3):
    for dx in range(-2, 3):
        rasa |= np.roll(np.roll(from_terra, dy, 0), dx, 1)
camada = np.empty((h, w), dtype=object)
for j in range(h):
    for i in range(w):
        t = ter[j, i]
        camada[j, i] = bio[j, i] if t == 0 else 'praia' if t == 1 else ('agua_rasa' if rasa[j, i] else 'agua_funda')
# fábrica de exemplo: piso 9 × 6 em campina, longe da água; jazida de ferro ao lado
fab = None
for j in range(4, h - 10):
    for i in range(4, w - 14):
        bloco = camada[j:j + 8, i:i + 14]
        if all(c == 'campina' for c in bloco.ravel()):
            fab = (i + 1, j + 1); break
    if fab:
        break
FX, FY = fab                                        # índices (coluna, linha a partir do sul)
piso = np.zeros((h, w), bool); piso[FY:FY + 6, FX:FX + 9] = True
jaz = [(FX + 10 + a, FY + 1 + b) for a in range(2) for b in range(3)]
for (i, j) in jaz:
    camada[j, i] = 'jazida'

# chão por pixel: amostra deformada por ruído (borda irregular, sem degrau)
rng = np.random.default_rng(3)
def ruido_mundo(sx, sy, k):
    g = rng.random((h + 3, w + 3))
    xs = sx / TW; ys = sy / TH
    x0_ = np.floor(xs).astype(int); y0_ = np.floor(ys).astype(int); fx = xs - x0_; fy = ys - y0_
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
    a = g[y0_, x0_]; b = g[y0_, x0_ + 1]; c = g[y0_ + 1, x0_]; d = g[y0_ + 1, x0_ + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
py, px = np.mgrid[0:HP, 0:WP]
n1 = ruido_mundo(px, py, 1) * 0.88 + ruido_mundo(px * 2.3 % WP, py * 2.3 % HP, 2) * 0.12
n2 = ruido_mundo(px, py, 3) * 0.88 + ruido_mundo(px * 2.3 % WP, py * 2.3 % HP, 4) * 0.12
BY = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0
pont = (BY[py % 4, px % 4] - 0.5) * 0.35                 # pontilhado na passagem entre camadas
wx = px / TW + (n1 - 0.5) * 1.1 + pont; wy = (HP - 1 - py) / TH + (n2 - 0.5) * 1.1 + pont
ti = np.clip(np.floor(wx).astype(int), 0, w - 1); tj = np.clip(np.floor(wy).astype(int), 0, h - 1)
img = np.zeros((HP, WP, 3))
for nome in set(camada.ravel()):
    sel = camada[tj, ti] == nome
    T = TEX[nome]
    img[sel] = T[py[sel] % T.shape[0], px[sel] % T.shape[1]]
# espuma: 1 px claro onde a água encosta na terra (em cima e dos lados), quebrado pelo pontilhado
eh_agua = np.isin(camada[tj, ti], ['agua_rasa', 'agua_funda'])
viz = np.zeros_like(eh_agua)
viz[1:] |= ~eh_agua[:-1]; viz[:, 1:] |= ~eh_agua[:, :-1]; viz[:, :-1] |= ~eh_agua[:, 1:]
espuma = eh_agua & viz & (BY[py % 4, px % 4] < 0.8)
img[espuma] = img[espuma] * 0.4 + np.array([0.62, 0.70, 0.70]) * 0.6
# piso por tile (sem deformar: a fábrica é grade)
pj, pi_ = np.nonzero(piso)
for j, i in zip(pj, pi_):
    sx, sy = i * TW, HP - (j + 1) * TH
    img[sy:sy + TH, sx:sx + TW] = PISO

# objetos: (nome, centro x em tiles a partir de x0, centro y a partir de y0, linha)
obj = []
for o in M['obstaculos']:
    i, j = o['x'] - x0, o['y'] - y0
    if piso[max(0, min(h - 1, j)), max(0, min(w - 1, i))] or (i, j) in jaz:
        continue
    ar = [int(v) for v in str(o['area']).strip('()[]').split(',')]
    obj.append((o['nome'], i + ar[0] / 2, j + ar[1] / 2, 0))
for (i, j) in jaz:
    obj.append(('jazida_ferro', i + 0.5, j + 0.5, 0))
F = lambda a, b: (FX + a, FY + b)
for nome, (i, j), li in (('fornalha', F(1, 3), 0), ('bau', F(4, 4), 0), ('poste_energia', F(7.5, 5.5), 0),
                         ('braco', F(4.5, 2.5), 0), ('broca', F(10, 2), 0), ('montadora', F(6, 1), 0)):
    obj.append((nome, i, j, li))
for k in range(5):
    obj.append(('esteira_reta', FX + 4.5, FY + 0.5 + k * 0, 1) if False else ('esteira_reta', FX + 3.5 + 0, FY + 0.5, 1))
# esteira: fila de 4 tiles indo para leste (linha 1 = girada 90°?) — deixa em linha reta norte-sul ao lado da fornalha
obj = [o for o in obj if o[0] != 'esteira_reta']
for k in range(3):
    obj.append(('esteira_reta', FX + 4.5, FY + 0.5 + k, 0))


def colar(dst, src, x, y):
    hh, ww = src.shape[:2]; H_, W_ = dst.shape[:2]
    xa, ya = max(0, x), max(0, y); xb, yb = min(W_, x + ww), min(H_, y + hh)
    if xa >= xb or ya >= yb:
        return
    s = src[ya - y:yb - y, xa - x:xb - x]; a = s[..., 3:4]
    dst[ya:yb, xa:xb] = dst[ya:yb, xa:xb] * (1 - a) + s[..., :3] * a


cache = {}
def sprite(nome, linha):
    if nome not in cache:
        e = IND[nome]; m = json.load(open(f"{D}/{e['pasta']}/{nome}.json"))
        var = '' if m['variantes'][0] == 'base' else '_' + m['variantes'][0]
        cache[nome] = (m, ler(f"{D}/{e['pasta']}/{nome}{var}.png"), ler(f"{D}/{e['pasta']}/{nome}{var}_sombra.png"))
    m, cor, som = cache[nome]; W_, H_ = m['quadro']; li = min(linha, m['linhas'] - 1)
    return m, cor[li * H_:(li + 1) * H_, 0:W_], som[li * H_:(li + 1) * H_, 0:W_]


pos = []
for nome, ci, cj, li in obj:
    if nome not in IND:
        continue
    m, c, s = sprite(nome, li)
    sx = int(round(ci * TW - m['ancora'][0])); sy = int(round(HP - cj * TH - m['ancora'][1]))
    pos.append((HP - cj * TH, c, s, sx, sy))
for _, c, s, sx, sy in pos:                       # sombras primeiro (no chão)
    colar(img, s, sx, sy)
for _, c, s, sx, sy in sorted(pos, key=lambda p: p[0]):   # depois os sprites, do fundo (norte) para a frente
    colar(img, c, sx, sy)
salvar(np.concatenate([img, np.ones((HP, WP, 1))], axis=2), SAIDA)
print('PREVIA ok', WP, HP, 'fabrica em', FX + x0, FY + y0, len(pos), 'objetos')
