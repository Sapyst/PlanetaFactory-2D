#!/usr/bin/env python3
# previa.py <pasta_do_modelo> <saida_sem_ext> [escala] : quadros com sombra sobre fundo neutro → .gif e .png (1º quadro)
# Mostra todas as linhas (rotações/direções) lado a lado e, no braço, as variantes empilhadas.
import json, os, sys, subprocess, tempfile, glob
pasta, saida = sys.argv[1], sys.argv[2]
esc = int(sys.argv[3]) if len(sys.argv) > 3 else 2
nome = os.path.basename(pasta.rstrip('/'))
m = json.load(open(os.path.join(pasta, nome + '.json')))
W, H = m['quadro']; Q = m['quadros']; L = m['linhas']
lmax = min(L, 8)                      # direções: mostra até 8 (de 2 em 2 se forem 16)
passo = max(1, L // lmax)
tmp = tempfile.mkdtemp()
FUNDO = '#57534b'
quadros = []
for q in range(Q):
    linhas_var = []
    for var in m['variantes']:
        suf = '' if var == 'base' else '_' + var
        cor = os.path.join(pasta, nome + suf + '.png'); som = os.path.join(pasta, nome + suf + '_sombra.png')
        cel = []
        for li in range(0, L, passo):
            geo = '%dx%d+%d+%d' % (W, H, q * W, li * H)
            f = os.path.join(tmp, 'c_%d_%s_%d.png' % (q, var, li))
            subprocess.run(['magick', '-size', '%dx%d' % (W, H), 'xc:' + FUNDO,
                            '(', som, '-crop', geo, '+repage', ')', '-composite',
                            '(', cor, '-crop', geo, '+repage', ')', '-composite',
                            '-bordercolor', '#2b2a27', '-border', '1', f], check=True)
            cel.append(f)
        fl = os.path.join(tmp, 'l_%d_%s.png' % (q, var))
        subprocess.run(['magick'] + cel + ['+append', fl], check=True)
        linhas_var.append(fl)
    fq = os.path.join(tmp, 'q_%03d.png' % q)
    subprocess.run(['magick'] + linhas_var + ['-append', '-scale', '%d%%' % (esc * 100), fq], check=True)
    quadros.append(fq)
subprocess.run(['cp', quadros[0], saida + '.png'], check=True)
if Q > 1:
    subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-framerate', str(m['fps']), '-i', os.path.join(tmp, 'q_%03d.png'),
                    '-vf', 'split[a][b];[a]palettegen=max_colors=200[p];[b][p]paletteuse=dither=none', '-loop', '0', saida + '.gif'], check=True)
subprocess.run(['rm', '-r', '--', tmp])
print('PREVIA', nome, Q, 'quadros', L, 'linhas')
