#!/usr/bin/env python3
# luzes2d.py: leva a luz das estruturas do jogo 3D (jogo/dados/luzes.json) para os sprites 2D.
# Cada ponto (espaço do modelo do Godot: x, y para cima, z) vira pixel em cada linha (rotação/direção) da folha,
# pela mesma câmera dos sprites (ortográfica, 35°, 2,875 cm/px, âncora = centro do tile no chão).
import json, math, glob, os
D = '/mnt/d/Projetos/Jogos/PlanetaFactory_2D'
L = json.load(open('/mnt/d/Projetos/Jogos/PlanetaFactory/jogo/dados/luzes.json'))
EL = math.radians(35)


def px(m, p, linha):
    """p no espaço do Godot → (x, y) em pixels do quadro, para a linha (rotação ou direção) dada."""
    bx, by, bz = p[0], -p[2], p[1]                          # Godot/glTF → Blender (z para cima)
    ang = math.radians(m['angulos_graus'][linha])
    rx = bx * math.cos(ang) - by * math.sin(ang); ry = bx * math.sin(ang) + by * math.cos(ang)
    PX = m['metros_por_pixel']
    return [round(m['ancora'][0] + rx / PX, 1), round(m['ancora'][1] - (ry * math.sin(EL) + bz * math.cos(EL)) / PX, 1)]


n = 0
for j in glob.glob(D + '/sprites/*/*/*.json'):
    m = json.load(open(j)); nome = m['nome']
    fonte = L['maquinas'].get(nome); poste = L['postes'].get(nome)
    if not fonte and not poste:
        m.pop('luz', None); json.dump(m, open(j, 'w'), indent=1, ensure_ascii=False); continue
    linhas = range(m['linhas'])
    PX = m['metros_por_pixel']
    if fonte:
        tipo = fonte['tipo']
        luz = {'tipo': tipo, 'cor': L['cores'][tipo], 'forca': fonte.get('forca', 1.0),
               'raio_px': round(fonte['raio'] / PX, 1), 'pos_px': [px(m, fonte['pos'], li) for li in linhas],
               'chao_px': [px(m, [fonte['pos'][0], 0.0, fonte['pos'][2]], li) for li in linhas],
               'so_ativa': True, 'so_noite': True}
        if fonte.get('chamas'):
            luz['chamas'] = [{'pos_px': [px(m, c[:3], li) for li in linhas], 'tamanho_m': c[3],
                              'tamanho_px': round(c[3] / PX, 1), 'cresce': bool(c[4])} for c in fonte['chamas']]
        if fonte.get('arcos'):
            luz['arcos'] = [[[px(m, a, li) for li in linhas], [px(m, b, li) for li in linhas]] for a, b in fonte['arcos']]
    else:
        luz = {'tipo': 'poste', 'cor': 'cor da rede de energia', 'forca': poste['forca'], 'raio_px': round(poste['raio'] / PX, 1),
               'pos_px': [px(m, poste['pos'], li) for li in linhas], 'chao_px': [px(m, [poste['pos'][0], 0.0, poste['pos'][2]], li) for li in linhas],
               'so_ativa': True, 'so_noite': True}
    m['luz'] = luz
    json.dump(m, open(j, 'w'), indent=1, ensure_ascii=False); n += 1
ind = json.load(open(D + '/indice.json'))
for j in glob.glob(D + '/sprites/*/*/*.json'):
    m = json.load(open(j))
    if m['nome'] in ind:
        ind[m['nome']]['luz'] = m.get('luz', {}).get('tipo')
json.dump(ind, open(D + '/indice.json', 'w'), indent=1, ensure_ascii=False)
print('LUZES', n, 'modelos com luz;', len(L['maquinas']), 'máquinas e', len(L['postes']), 'postes no jogo')
