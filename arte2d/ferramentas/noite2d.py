# noite2d.py: prévia "dia | noite" dos sprites com a luz do jogo (campo "luz" do .json), labaredas e arcos.
# Roda no Python do Blender (numpy): blender -b --python noite2d.py -- <saida.mp4> <nome> [<nome>...]
import bpy, sys, os, json, math, glob, subprocess, tempfile, random
import numpy as np
A = sys.argv[sys.argv.index('--') + 1:]
SAIDA, NOMES = A[0], A[1:]
D = '/mnt/d/Projetos/Jogos/PlanetaFactory_2D'
IND = json.load(open(D + '/indice.json'))
Q = 48; ESC = 3; TOPO = 40
CHAO_DIA = np.array([0.34, 0.32, 0.29]); CHAO = np.array([0.30, 0.29, 0.27])
AMB = np.array([0.20, 0.23, 0.36])                       # luz da noite (lua fria e fraca)
COR_POSTE = np.array([1.0, 0.8, 0.42])


def ler(c):
    im = bpy.data.images.load(c); w, h = im.size
    a = np.empty(w * h * 4, dtype=np.float32); im.pixels.foreach_get(a); bpy.data.images.remove(im)
    return a.reshape(h, w, 4)[::-1].copy()


def salvar(arr, c):
    h, w = arr.shape[:2]; im = bpy.data.images.new('s', w, h, alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).astype(np.float32).ravel())
    im.filepath_raw = c; im.file_format = 'PNG'; im.save(); bpy.data.images.remove(im)


def colar(dst, src, x, y):
    """src RGBA por cima de dst RGB, canto (x, y)."""
    h, w = src.shape[:2]; H, W = dst.shape[:2]
    x0, y0 = max(0, x), max(0, y); x1, y1 = min(W, x + w), min(H, y + h)
    if x0 >= x1 or y0 >= y1:
        return
    s = src[y0 - y:y1 - y, x0 - x:x1 - x]; a = s[..., 3:4]
    dst[y0:y1, x0:x1] = dst[y0:y1, x0:x1] * (1 - a) + s[..., :3] * a


def intensidade(tipo, u, rnd):
    if tipo == 'fogo':
        return 1.0 + 0.25 * math.sin(2 * math.pi * 7 * u) + 0.15 * math.sin(2 * math.pi * 13 * u + 1.3)
    if tipo == 'cristal':
        return 0.8 + 0.35 * math.sin(2 * math.pi * 2 * u)
    if tipo == 'choque':
        return 1.4 if (int(u * Q) % 12) in (0, 1, 7) else 0.12
    return 1.0


def labareda(tam_px, cresce):
    h = max(6, int(round(tam_px / 2.0)) * 2)
    nome = 'labareda_%dpx%s' % (h, '_cresce' if cresce else '')
    meta = json.load(open(D + '/efeitos/' + nome + '.json')); folha = ler(D + '/efeitos/' + nome + '.png')
    return meta, folha


tmp = tempfile.mkdtemp(); paineis = {}
for nome in NOMES:
    e = IND[nome]; m = json.load(open(os.path.join(D, e['pasta'], nome + '.json')))
    W, H = m['quadro']; luz = m.get('luz', {}); var = '' if m['variantes'][0] == 'base' else '_' + m['variantes'][0]
    folha = ler(os.path.join(D, e['pasta'], nome + var + '.png')); sombra = ler(os.path.join(D, e['pasta'], nome + var + '_sombra.png'))
    labs = [(c, *labareda(c['tamanho_px'], c['cresce'])) for c in luz.get('chamas', [])]
    rnd = random.Random(3)
    yy, xx = np.mgrid[0:H + TOPO, 0:W]
    quadros = []
    for q in range(Q):
        u = q / Q; qq = q % m['quadros']
        spr = folha[0:H, qq * W:(qq + 1) * W]; som = sombra[0:H, qq * W:(qq + 1) * W]
        # dia
        dia = np.zeros((H + TOPO, W, 3)) + CHAO_DIA
        dia[TOPO:] = dia[TOPO:] * (1 - som[..., 3:4])
        colar(dia, spr, 0, TOPO)
        # noite: albedo × (ambiente + luz), luz em degraus (pixel art)
        alb = np.zeros((H + TOPO, W, 3)) + CHAO; colar(alb, spr, 0, TOPO)
        L = np.zeros((H + TOPO, W, 3)) + AMB
        if luz:
            cor = COR_POSTE if luz['tipo'] == 'poste' else np.array(luz['cor'])
            I = luz['forca'] * intensidade(luz['tipo'], u, rnd)
            corpo = np.zeros((H + TOPO, W), bool); corpo[TOPO:] = spr[..., 3] > 0.5
            # chão: elipse em volta da base (um círculo no chão visto a 35°)
            gx, gy = luz['chao_px'][0]; gy += TOPO; R = luz['raio_px'] * 0.6
            dg = np.sqrt((xx - gx) ** 2 + ((yy - gy) / math.sin(math.radians(35))) ** 2)
            fg = np.clip(1 - dg / R, 0, 1) ** 2 * I * 1.5
            # a própria peça: perto da fonte, na tela
            x, y = luz['pos_px'][0]; y += TOPO
            ds = np.sqrt((xx - x) ** 2 + (yy - y) ** 2)
            fs = np.clip(1 - ds / (R * 0.75), 0, 1) ** 1.5 * I * 1.3
            f = np.where(corpo, fs, np.where(yy >= TOPO, fg, 0.0))
            # degraus com pontilhado ordenado 4×4 (sem anéis de filtro)
            bayer = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0
            lim = bayer[yy % 4, xx % 4]
            f = np.floor(f * 4 + lim) / 4
            L = L + f[..., None] * cor
        noite = alb * L
        # brilho próprio do que emite (o sprite já traz a cor acesa: realça o que é mais claro que o ambiente)
        for c, meta, fl in labs:
            cx, cy = c['pos_px'][0]; fw, fh = meta['quadro']; k = q % meta['quadros']
            colar(noite, fl[:, k * fw:(k + 1) * fw], int(round(cx - meta['ancora'][0])), int(round(cy + TOPO - meta['ancora'][1])))
            colar(dia, fl[:, k * fw:(k + 1) * fw], int(round(cx - meta['ancora'][0])), int(round(cy + TOPO - meta['ancora'][1])))
        if luz.get('arcos') and intensidade('choque', u, rnd) > 1:
            for a, b in luz['arcos']:
                (x0, y0), (x1, y1) = a[0], b[0]
                pts = [(x0 + (x1 - x0) * t + rnd.uniform(-2, 2) * (0 < t < 1), y0 + (y1 - y0) * t + rnd.uniform(-2, 2) * (0 < t < 1) + TOPO) for t in np.linspace(0, 1, 7)]
                for (p0x, p0y), (p1x, p1y) in zip(pts, pts[1:]):
                    for t in np.linspace(0, 1, 12):
                        X = int(round(p0x + (p1x - p0x) * t)); Y = int(round(p0y + (p1y - p0y) * t))
                        if 0 <= X < W and 0 <= Y < H + TOPO:
                            noite[Y, X] = [0.85, 0.95, 1.0]
        par = np.concatenate([dia, np.zeros((H + TOPO, 2, 3)) + 0.1, np.clip(noite, 0, 1)], axis=1)
        quadros.append(par)
    paineis[nome] = quadros
# junta todos os modelos em uma coluna, cada linha "dia | noite", ampliado
larg = max(p[0].shape[1] for p in paineis.values())
for q in range(Q):
    linhas = []
    for nome in NOMES:
        p = paineis[nome][q]; h, w = p.shape[:2]
        l = np.zeros((h, larg, 3)) + 0.08; l[:, :w] = p
        linhas.append(l); linhas.append(np.zeros((3, larg, 3)) + 0.08)
    img = np.concatenate(linhas, axis=0)
    img = np.repeat(np.repeat(img, ESC, axis=0), ESC, axis=1)
    rgba = np.concatenate([img, np.ones(img.shape[:2] + (1,))], axis=2)
    salvar(rgba, os.path.join(tmp, 'f%02d.png' % q))
subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-stream_loop', '2', '-framerate', '12', '-i', os.path.join(tmp, 'f%02d.png'),
                '-vf', 'fps=24,pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p', '-c:v', 'libx264', '-crf', '18', '-movflags', '+faststart', SAIDA], check=True)
subprocess.run(['cp', os.path.join(tmp, 'f05.png'), SAIDA.replace('.mp4', '.png')])
print('NOITE ok', len(NOMES))
