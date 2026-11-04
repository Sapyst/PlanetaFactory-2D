#!/usr/bin/env python3
# explosao2d.py: explosão 2D em pixel art (sem 3D): bola de fogo que cresce e vira fumaça escura subindo. 12 quadros.
# Saída: efeitos/explosao.png (folha) + .json (âncora no centro do chão). Também: clarao.png (boca do cano, 3 quadros).
import json, math, os, random, subprocess, tempfile
D = '/mnt/d/Projetos/Jogos/PlanetaFactory_2D'
W, H, N = 56, 56, 12
tmp = tempfile.mkdtemp(); rnd = random.Random(5)
bolhas = [(rnd.uniform(-1, 1), rnd.uniform(-0.6, 0.4), rnd.uniform(0.55, 1.0)) for _ in range(9)]
qs = []
for q in range(N):
    u = q / (N - 1)
    cx, cy = W / 2, H * 0.62
    cmd = ['magick', '-size', '%dx%d' % (W, H), 'xc:none', '+antialias']
    fogo = max(0.0, 1 - u * 1.6)                     # o fogo dura o começo
    R = 6 + 16 * (1 - (1 - u) ** 2)
    # fumaça: bolhas escuras que sobem e crescem
    for (bx, by, k) in bolhas:
        r = R * 0.55 * k * (0.6 + 0.6 * u)
        x = cx + bx * R * 0.7; y = cy + by * R * 0.6 - 10 * u * k
        cor = '#2a2422' if u > 0.35 else '#3b2f2a'
        some = max(0.0, (u - 0.55) / 0.45)            # no fim a fumaça se desfaz: bolhas menores e falhando
        r *= 1.0 - 0.75 * some
        if rnd.random() < some * 0.9 or r < 1.2:
            continue
        if u < 0.98:
            cmd += ['-fill', cor, '-draw', 'circle %.1f,%.1f %.1f,%.1f' % (x, y, x + r, y)]
            cmd += ['-fill', '#4a403b', '-draw', 'circle %.1f,%.1f %.1f,%.1f' % (x - r * 0.25, y - r * 0.3, x - r * 0.25 + r * 0.45, y - r * 0.3)]
    if fogo > 0:
        for cor, f in (('#b8321a', 1.0), ('#f0801f', 0.78), ('#ffcf4a', 0.55), ('#fff6c8', 0.3)):
            r = R * f * (0.5 + 0.5 * fogo)
            cmd += ['-fill', cor, '-draw', 'circle %.1f,%.1f %.1f,%.1f' % (cx, cy - 2, cx + r, cy - 2)]
    f = os.path.join(tmp, 'q%02d.png' % q); cmd += ['-channel', 'A', '-threshold', '50%', '+channel', f]
    subprocess.run(cmd, check=True); qs.append(f)
subprocess.run(['magick'] + qs + ['+append', D + '/efeitos/explosao.png'], check=True)
json.dump({'nome': 'explosao', 'quadro': [W, H], 'quadros': N, 'fps': 18, 'ancora': [W / 2, H * 0.62]}, open(D + '/efeitos/explosao.json', 'w'))
# clarão da boca: estrela de 4 pontas, 3 quadros diminuindo
qs = []
for q in range(3):
    s = 9 - q * 3; c = 9
    cmd = ['magick', '-size', '19x19', 'xc:none', '+antialias',
           '-fill', '#ffd65a', '-draw', 'polygon %d,%d %d,%d %d,%d %d,%d' % (c, c - s, c + 2, c, c, c + s, c - 2, c),
           '-draw', 'polygon %d,%d %d,%d %d,%d %d,%d' % (c - s, c, c, c - 2, c + s, c, c, c + 2),
           '-fill', '#fff6c8', '-draw', 'circle %d,%d %d,%d' % (c, c, c + max(1, 3 - q), c)]
    f = os.path.join(tmp, 'c%d.png' % q); cmd += [f]; subprocess.run(cmd, check=True); qs.append(f)
subprocess.run(['magick'] + qs + ['+append', D + '/efeitos/clarao.png'], check=True)
json.dump({'nome': 'clarao', 'quadro': [19, 19], 'quadros': 3, 'fps': 30, 'ancora': [9, 9]}, open(D + '/efeitos/clarao.json', 'w'))
subprocess.run(['rm', '-r', '--', tmp]); print('EXPLOSAO ok')
