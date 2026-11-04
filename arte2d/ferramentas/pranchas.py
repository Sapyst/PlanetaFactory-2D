#!/usr/bin/env python3
# pranchas.py: para cada categoria em sprites/, uma prancha (.png, 1º quadro da 1ª linha, com sombra e nome) e um
# vídeo (.mp4) com todos animados juntos (laço de 48 quadros; quem tem menos repete). Saída em previas/.
import json, os, subprocess, tempfile, glob, sys
D = '/mnt/d/Projetos/Jogos/PlanetaFactory_2D'
FUNDO = '#57534b'; FONTE = '/usr/share/fonts/TTF/DejaVuSans.ttf'
filtro = sys.argv[1] if len(sys.argv) > 1 else ''
for cat in sorted(os.listdir(os.path.join(D, 'sprites'))):
    if filtro not in cat:
        continue
    pastas = sorted(glob.glob(os.path.join(D, 'sprites', cat, '*', '*.json')))
    if not pastas:
        continue
    tmp = tempfile.mkdtemp()
    itens = []
    for j in pastas:
        m = json.load(open(j)); pasta = os.path.dirname(j); nome = m['nome']
        suf = '' if m['variantes'][0] == 'base' else '_' + m['variantes'][0]
        itens.append((nome, m, os.path.join(pasta, nome + suf + '.png'), os.path.join(pasta, nome + suf + '_sombra.png')))
    WM = max(m['quadro'][0] for _, m, _, _ in itens); HM = max(m['quadro'][1] for _, m, _, _ in itens)
    esc = 3 if max(WM, HM) < 80 else 2
    QMAX = max(m['quadros'] for _, m, _, _ in itens)
    for q in range(QMAX):
        cels = []
        for k, (nome, m, cor, som) in enumerate(itens):
            W, H = m['quadro']; qq = q % m['quadros']
            geo = '%dx%d+%d+%d' % (W, H, qq * W, 0)
            f = os.path.join(tmp, 'c%03d.png' % k)
            subprocess.run(['magick', '-size', '%dx%d' % (W, H), 'xc:' + FUNDO, '(', som, '-crop', geo, '+repage', ')', '-composite',
                            '(', cor, '-crop', geo, '+repage', ')', '-composite', '-scale', '%d%%' % (esc * 100),
                            '-background', FUNDO, '-gravity', 'center', '-extent', '%dx%d' % (WM * esc, HM * esc),
                            '-gravity', 'south', '-background', '#2b2a27', '-splice', '0x18', '-font', FONTE, '-pointsize', '12',
                            '-fill', '#e6e0d6', '-annotate', '+0+2', nome, f], check=True)
            cels.append(f)
        col = max(1, min(8, int(1800 // (WM * esc + 6))))
        saida = os.path.join(tmp, 'f%03d.png' % q)
        subprocess.run(['magick', 'montage'] + cels + ['-tile', '%dx' % col, '-geometry', '+3+3', '-background', '#1b1d22', saida], check=True)
    subprocess.run(['cp', os.path.join(tmp, 'f000.png'), os.path.join(D, 'previas', cat + '.png')], check=True)
    if QMAX > 1:
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-stream_loop', '2', '-framerate', '12', '-i', os.path.join(tmp, 'f%03d.png'),
                        '-vf', 'fps=24,pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p', '-c:v', 'libx264', '-crf', '18',
                        '-movflags', '+faststart', os.path.join(D, 'previas', cat + '.mp4')], check=True)
    subprocess.run(['rm', '-r', '--', tmp])
    print('PRANCHA', cat, len(itens), 'modelos', QMAX, 'quadros')
