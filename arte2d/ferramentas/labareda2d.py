#!/usr/bin/env python3
# labareda2d.py: labareda 2D em pixel art (sem 3D), um tamanho por altura usada nos modelos (luz.chamas.tamanho_px).
# Laço de 12 quadros: línguas que sobem e tremem, núcleo claro embaixo; "cresce" = versão que dá um estirão no meio do laço.
# Saída: efeitos/labareda_<h>px[_cresce].png (folha 12 quadros) + .json (âncora = centro da base).
import json, glob, math, os, subprocess, tempfile, random
D = '/mnt/d/Projetos/Jogos/PlanetaFactory_2D'
N = 12
CORES = ['#9c2a14', '#d9541c', '#f39a2c', '#ffd65a', '#fff3b0']      # da borda para o núcleo
alturas = set()
for j in glob.glob(D + '/sprites/*/*/*.json'):
    m = json.load(open(j))
    for c in m.get('luz', {}).get('chamas', []):
        alturas.add((max(6, int(round(c['tamanho_px'] / 2.0)) * 2), c['cresce']))


def lingua(cx, base, larg, alt, curva):
    """contorno de uma língua de fogo (gota apontando para cima, com a ponta torta)."""
    pts = []
    for i in range(13):
        t = i / 12.0
        y = base - alt * t
        w = larg * math.sin(math.pi * (0.15 + 0.85 * (1 - t))) * (1 - t) ** 0.35
        x = cx + curva * t * t * larg
        pts.append((x - w, y)); pts.insert(0, (x + w, y))
    return pts


for h, cresce in sorted(alturas):
    W = max(8, int(h * 0.9) + 4) // 2 * 2; H = int(h * (1.6 if cresce else 1.25)) + 4
    tmp = tempfile.mkdtemp(); quadros = []
    rnd = random.Random(h * 7 + cresce)
    fases = [rnd.random() * 6.28 for _ in range(5)]
    for q in range(N):
        u = q / N
        est = 1.0 + (0.5 * max(0.0, math.sin(2 * math.pi * u)) ** 2 if cresce else 0.0)       # estirão
        cmd = ['magick', '-size', '%dx%d' % (W, H), 'xc:none', '+antialias']
        base = H - 2; cx = W / 2
        for k, cor in enumerate(CORES):
            esc = 1.0 - k * 0.19
            for li in range(3):
                ph = fases[li] + 2 * math.pi * u * (2 + li)
                alt = h * esc * est * (0.75 + 0.25 * math.sin(ph)) * (1.0 if li == 1 else 0.7)
                larg = W * 0.36 * esc * (1.0 if li == 1 else 0.6)
                off = (li - 1) * W * 0.18 * esc
                curva = 0.5 * math.sin(ph * 1.3)
                p = lingua(cx + off, base - k * 0.6, larg, alt, curva)
                cmd += ['-fill', cor, '-draw', 'polygon ' + ' '.join('%.1f,%.1f' % xy for xy in p)]
        f = os.path.join(tmp, 'q%02d.png' % q); cmd += [f]
        subprocess.run(cmd, check=True); quadros.append(f)
    nome = 'labareda_%dpx%s' % (h, '_cresce' if cresce else '')
    subprocess.run(['magick'] + quadros + ['+append', os.path.join(D, 'efeitos', nome + '.png')], check=True)
    json.dump({'nome': nome, 'quadro': [W, H], 'quadros': N, 'fps': 12, 'ancora': [W / 2, H - 2], 'aditivo': False,
               'nota': 'desenhar por cima do sprite na posição luz.chamas.pos_px; a luz (luz.pos_px) faz o clarão'},
              open(os.path.join(D, 'efeitos', nome + '.json'), 'w'), indent=1, ensure_ascii=False)
    subprocess.run(['rm', '-r', '--', tmp])
    print('LABAREDA', nome, W, H)
