"""Estudo isolado (fora do jogo): FAUNA GRANDE do planeta (patch fauna, fase 9; pedido de Sapyst: herbívoros em manada
que migram e fogem, e predadores nativos que caçam). Fauna nativa de um mundo alienígena, mas crível: anatomia de bicho
de verdade, proporções de animal de verdade, com UM detalhe estranho de osso cada (o tema da fauna nativa: a crista óssea
do pardelo, os espinhos do rato-pardo; osso ≈ (0,62, 0,56, 0,44)).
  Herbívoro A) GALHUDO — ungulado esguio (cervo/antílope), ~1,0 m na cernelha, ~1,5 m da anca ao peito, pescoço longo,
     cascos de 2 dedos; pelagem castanho-fulva, barriga clara, faixa escura no flanco, rabo curto de face clara.
     O estranho: em vez de galhada, duas placas ósseas chatas saindo da testa e curvando para trás, e uma fileira de
     nódulos ósseos pequenos descendo a nuca.
  Herbívoro B) CORCOVA — bovídeo pesado (bisão/boi-almiscarado), ~1,2 m na corcova, pelo escuro e áspero (lã mais clara
     na frente), chifres curtos curvos de osso e nódulos ósseos ao longo da corcova.
  Predador A) UIVADOR — canídeo de matilha, ~0,7 m na cernelha, ~1,1 m de corpo, pernas longas, rabo espesso; cinza-ocre
     com a sela das costas escura. O estranho: crista curta de placas ósseas da testa à nuca.
  Predador B) ESPREITADOR — felino solitário, ~0,6 m, corpo longo e baixo, rabo longo, pelagem com manchas. O estranho:
     esporões ósseos atrás dos pulsos.
MODELO (como o rato): UMA malha só, deformada pelo esqueleto — coluna (corpo, peito), pescoço em 2, cabeça, mandíbula
(a boca abre: palato e língua por dentro), orelhas, cauda em 2–3 e pernas de 4 ossos (coxa, canela, pé, dedo; atrás da
escápula: braço, antebraço, mão, dedo). Olha para +X; 1 unidade = 1 m; chão em z = 0.
POSES: as pernas são postas por IK (alvo no chão): no apoio o casco/pata fica parado no chão (z = 0) e desliza para trás
na velocidade do passo (o jogo anda com o bicho), no fim do apoio gira na ponta (o calcanhar sobe) e no balanço dobra e
sobe sem raspar o chão. Herbívoros: andar (passo de 4 tempos), correr (galope), pastar, alerta, morto. Predadores: andar,
correr (galope rotativo), espreitar (agachado), morder (bote), comer, deitado, morto.

Uso: blender -b --python estudo_fauna_grande.py -- foto [saida=<pasta>]        (pranchas das candidatas)
     blender -b --python estudo_fauna_grande.py -- quadros [saida=<pasta>] [so=<id,id>]   (prancha de quadros por ação)
     blender -b --python estudo_fauna_grande.py -- conferir [jogo]      (chão e interseções, quadro a quadro)
     blender -b --python estudo_fauna_grande.py -- nada [jogo]
"""
import bpy, bmesh, math, os, sys, random
from mathutils import Vector, Matrix, Quaternion, noise
from mathutils.bvhtree import BVHTree

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import base3d

PI = math.pi
random.seed(41)
_ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
JOGO_Q = 'jogo' in _ARGS
_OPC = dict(a.split('=', 1) for a in _ARGS if '=' in a)
SAIDA = _OPC.get('saida', AQUI)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = base3d.iniciar()
X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
OSSO_COR = (0.62, 0.56, 0.44)


def suave(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def mistura(a, b, t):
    t = suave(t)
    if a == b or t <= 0.0:
        return {a: 1.0}
    if t >= 1.0:
        return {b: 1.0}
    return {a: 1.0 - t, b: t}


def faixa(v, c, w):
    """1 no centro c, 0 a partir de c ± w (suave)."""
    return 1.0 - suave(abs(v - c) / w)


# ------------------------------------------------------------------ materiais
def _mix(nt, fac, a, b, modo='MIX'):
    mx = nt.nodes.new('ShaderNodeMix')
    mx.data_type = 'RGBA'
    mx.blend_type = modo
    if isinstance(fac, (int, float)):
        mx.inputs[0].default_value = fac
    else:
        nt.links.new(fac, mx.inputs[0])
    for i, s in ((6, a), (7, b)):
        if isinstance(s, tuple):
            mx.inputs[i].default_value = (*s, 1)
        else:
            nt.links.new(s, mx.inputs[i])
    return mx.outputs[2]


def pelagem_mat(nome, c):
    """Pelo: a cor sai do atributo 'zona' de cada vértice (R = barriga clara, G = marca 1, B = marca 2), com pintas
    (Voronoi) se a espécie tiver, e dois ruídos multiplicando (pontinhos de pelo e manchas largas). Fosco."""
    m = bpy.data.materials.new(nome)
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    at = nt.nodes.new('ShaderNodeAttribute')
    at.attribute_name = 'zona'
    sep = nt.nodes.new('ShaderNodeSeparateColor')
    nt.links.new(at.outputs['Color'], sep.inputs[0])
    tc = nt.nodes.new('ShaderNodeTexCoord')
    cor = _mix(nt, sep.outputs[0], c['dorso'], c['barriga'])
    cor = _mix(nt, sep.outputs[1], cor, c['marca1'])
    cor = _mix(nt, sep.outputs[2], cor, c['marca2'])
    if c.get('pinta'):
        dis = nt.nodes.new('ShaderNodeTexNoise')
        dis.inputs['Scale'].default_value = 9.0
        nt.links.new(tc.outputs['Object'], dis.inputs['Vector'])
        som = nt.nodes.new('ShaderNodeVectorMath')
        som.operation = 'MULTIPLY_ADD'
        nt.links.new(dis.outputs['Color'], som.inputs[0])
        som.inputs[1].default_value = (0.035, 0.035, 0.035)
        nt.links.new(tc.outputs['Object'], som.inputs[2])
        vo = nt.nodes.new('ShaderNodeTexVoronoi')
        vo.inputs['Scale'].default_value = c.get('pinta_escala', 22.0)
        nt.links.new(som.outputs[0], vo.inputs['Vector'])
        mr = nt.nodes.new('ShaderNodeMapRange')
        mr.inputs['From Min'].default_value = 0.26
        mr.inputs['From Max'].default_value = 0.34
        mr.inputs['To Min'].default_value = 1.0
        mr.inputs['To Max'].default_value = 0.0
        nt.links.new(vo.outputs['Distance'], mr.inputs['Value'])
        mv = nt.nodes.new('ShaderNodeMath')            # sem pinta na barriga
        mv.operation = 'MULTIPLY_ADD'
        nt.links.new(sep.outputs[0], mv.inputs[0])
        mv.inputs[1].default_value = -0.9
        mv.inputs[2].default_value = 1.0
        mm = nt.nodes.new('ShaderNodeMath')
        mm.operation = 'MULTIPLY'
        nt.links.new(mr.outputs['Result'], mm.inputs[0])
        nt.links.new(mv.outputs[0], mm.inputs[1])
        cor = _mix(nt, mm.outputs[0], cor, c['pinta'])
    for esc, lo, hi in ((c.get('fino', 140.0), 0.72, 1.0), (c.get('largo', 6.0), 0.86, 1.0)):
        nz = nt.nodes.new('ShaderNodeTexNoise')
        nz.inputs['Scale'].default_value = esc
        nz.inputs['Detail'].default_value = 6.0
        nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
        rp = nt.nodes.new('ShaderNodeValToRGB')
        rp.color_ramp.elements[0].position = 0.35
        rp.color_ramp.elements[0].color = (lo, lo, lo, 1)
        rp.color_ramp.elements[1].position = 0.65
        rp.color_ramp.elements[1].color = (hi, hi, hi, 1)
        nt.links.new(nz.outputs['Fac'], rp.inputs['Fac'])
        cor = _mix(nt, 1.0, cor, rp.outputs['Color'], 'MULTIPLY')
    nt.links.new(cor, b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = c.get('aspereza', 0.82)
    b.inputs['Sheen Weight'].default_value = 0.35
    m.diffuse_color = (*c['dorso'], 1)
    return m


def liso_mat(nome, cor, aspereza=0.5, brilho=0.0):
    m = bpy.data.materials.new(nome)
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (*cor, 1)
    b.inputs['Roughness'].default_value = aspereza
    b.inputs['Coat Weight'].default_value = brilho
    m.diffuse_color = (*cor, 1)
    return m


I_PELO, I_FOCINHO, I_OLHO, I_OSSO, I_CASCO, I_BOCA, I_DENTE = range(7)
# partes (atributo de face 'parte'): para conferir quem atravessa quem
P_TRONCO, P_PESCOCO, P_CABECA, P_MANDIBULA, P_CAUDA, P_ORELHA, P_OSSO, P_NODULO, P_OLHO, P_DENTE = range(1, 11)
PERNAS = (('e', True), ('d', True), ('e', False), ('d', False))       # (lado, dianteira?)
CHAVE = {('e', True): 'fe', ('d', True): 'fd', ('e', False): 'te', ('d', False): 'td'}
P_ALTA = {'fe': 20, 'fd': 21, 'te': 22, 'td': 23}
P_BAIXA = {'fe': 30, 'fd': 31, 'te': 32, 'td': 33}
P_ESPORAO = {'fe': 40, 'fd': 41}
NOMES_PERNA = {True: ('braco', 'antebraco', 'mao', 'dedof'), False: ('coxa', 'canela', 'pe', 'dedo')}


# ------------------------------------------------------------------ marcas da pelagem (atributo 'zona' por vértice)
def zona_galhudo(d):
    """Fulvo em cima, barriga creme, faixa escura no flanco (entre as duas cores), espelho claro na anca e embaixo do rabo,
    queixo e garganta claros, parte de dentro das pernas clara."""
    reg, x, sa = d['reg'], d['x'], d['sa']
    if reg == 'perna':
        return (0.75 * suave((d['dentro'] - 0.1) / 0.5), 0.0, 0.0)
    if reg == 'cauda':
        return (0.0, 0.0, suave((-d['sa'] + 0.1) / 0.4))
    if reg == 'orelha':
        return (0.0, 0.0, 0.85 * d.get('dentro', 0.0))
    if reg in ('c', 'b'):
        return (suave((-sa - 0.15) / 0.5), 0.0, 0.0)
    if reg == 'p':
        return (0.85 * suave((-sa - 0.35) / 0.45), 0.0, 0.0)
    corpo = suave((x + 0.52) / 0.12) * suave((0.42 - x) / 0.12)
    r = suave((-sa - 0.45) / 0.2)
    g = faixa(sa, -0.27, 0.17) * corpo
    esp = suave((-0.62 - x) / 0.07) * (1.0 - suave((abs(d['ca']) - 0.55) / 0.3)) * suave((0.75 - sa) / 0.4)
    return (r * (1 - g), g, esp)


def zona_corcova(d):
    """Pardo-escuro; a lã da frente (corcova, ombros, pescoço) mais clara e ruiva; cara e pernas mais escuras."""
    reg, x, sa = d['reg'], d['x'], d['sa']
    if reg == 'perna':
        return (0.0, 0.25 * suave((d['z'] - 0.35) / 0.2), 0.6 * suave((0.45 - d['z']) / 0.2))
    if reg in ('cauda', 'orelha'):
        return (0.0, 0.0, 0.5)
    if reg in ('c', 'b'):
        return (0.0, 0.35, 0.45 * suave((-sa + 0.2) / 0.5))
    la = suave((x + 0.15) / 0.3) * (0.55 + 0.45 * suave((sa + 0.2) / 0.5))
    return (suave((-sa - 0.5) / 0.3) * 0.5, la, 0.0)


def zona_uivador(d):
    """Cinza-ocre; sela escura do dorso (das escápulas à anca, descendo até a ponta do rabo); barriga, garganta, bochecha
    e focinho claros; ocre nas pernas por fora e atrás das orelhas."""
    reg, x, sa = d['reg'], d['x'], d['sa']
    if reg == 'perna':
        return (0.8 * suave((d['dentro'] - 0.05) / 0.5), 0.0, 0.55 * suave((0.4 - d['z']) / 0.25) * (1 - suave((d['dentro'] - 0.05) / 0.5)))
    if reg == 'cauda':
        return (0.0, 0.25 + 0.75 * suave((sa + 0.1) / 0.5) * (0.4 + 0.6 * d['t']), 0.0)
    if reg == 'orelha':
        return (0.0, 0.0, 0.8) if d.get('dentro', 0.0) < 0.5 else (0.85, 0.0, 0.0)
    if reg in ('c', 'b'):
        return (suave((-sa + 0.05) / 0.45), 0.0, 0.5 * suave((0.6 - x) / 0.05) * suave((sa - 0.2) / 0.4))
    if reg == 'p':
        return (suave((-sa - 0.2) / 0.45), 0.0, 0.0)
    sela = suave((x + 0.34) / 0.1) * suave((0.26 - x) / 0.12) * suave((sa - 0.05) / 0.3)
    return (suave((-sa - 0.35) / 0.3), sela, 0.0)


def zona_espreitador(d):
    """Fulvo-acinzentado com pintas (shader); barriga e queixo claros; anéis escuros no fim do rabo; lágrima clara no
    olho (marca 2)."""
    reg, x, sa = d['reg'], d['x'], d['sa']
    if reg == 'perna':
        return (0.8 * suave((d['dentro'] - 0.1) / 0.5), 0.0, 0.0)
    if reg == 'cauda':
        t = d['t']
        anel = suave((t - 0.62) / 0.05) * (0.5 + 0.5 * math.cos(t * 2 * PI * 7.0)) * 0.9
        return (0.6 * suave((-sa - 0.2) / 0.5) * (1 - suave((t - 0.6) / 0.1)), anel, 0.0)
    if reg == 'orelha':
        return (0.0, 0.0, 0.8) if d.get('dentro', 0.0) > 0.5 else (0.0, 0.85, 0.0)
    if reg in ('c', 'b'):
        return (suave((-sa + 0.1) / 0.45), 0.0, 0.0)
    return (suave((-sa - 0.3) / 0.3), 0.0, 0.0)


# ------------------------------------------------------------------ espécies
def _tr(*lin):
    """Tronco por silhueta: (x, z de cima, z de baixo, meia-largura) → seção (x, z do centro, meia-largura, r, r, 't')."""
    return [(x, (zt + zb) / 2, ry, (zt - zb) / 2, (zt - zb) / 2, 't') for x, zt, zb, ry in lin]


# tubo: seções (x, z do centro, meia-largura, meia-altura do lado de cima, meia-altura do lado de baixo, região) da anca
#   ao focinho, cada anel perpendicular à linha das seções. Região: 't' tronco, 'p' pescoço, 'c' cabeça, 'b' boca (anel
#   dividido em maxila e mandíbula). 'quad': expoente da superelipse (cima, baixo) por região (2 = elipse).
# ossos: (x, z) da cabeça e da ponta de cada osso da coluna. Pernas: juntas (x, y, z) da esquerda (a direita espelha):
#   dianteira e = topo da escápula, o = ombro, c = cotovelo, k = carpo, f = boleto, t = ponta do casco/garra (no chão);
#   traseira q = quadril, j = joelho, k = jarrete, f = boleto, t = ponta.
# perfil_f / perfil_t: a perna desenhada de lado, de cima para baixo: cada anel é ('p', x da frente, z da frente, x de
#   trás, z de trás, meia-largura, y do centro, fixo) — o contorno de verdade (garupa, jarrete, olécrano) — ou
#   ('o', segmento, t, meia-largura, meia-profundidade, desvio, fixo) em volta do osso (quartela). Pesos: pela distância
#   aos ossos da perna; `fixo` = quanto fica preso ao osso de cima (anéis de dentro do corpo). baixa_*: a partir deste
#   anel a perna está fora do corpo (confere se atravessa).
ESPECIES = {
    'galhudo': dict(
        nome='Galhudo', grupo='herbivoro', pe='casco', lados=12, zona=zona_galhudo,
        cores=dict(dorso=(0.30, 0.148, 0.055), barriga=(0.62, 0.55, 0.43), marca1=(0.045, 0.028, 0.018),
                   marca2=(0.72, 0.68, 0.60), fino=150.0, largo=7.0),
        focinho=(0.025, 0.021, 0.019), casco=(0.032, 0.028, 0.026), boca=(0.30, 0.09, 0.08),
        quad=dict(t=(2.3, 3.0), p=(2.1, 2.1), c=(2.0, 2.2), b=(2.0, 2.0)),
        tubo=_tr((-0.652, 0.885, 0.835, 0.03), (-0.632, 0.955, 0.725, 0.085), (-0.565, 0.99, 0.60, 0.132),
                 (-0.445, 0.995, 0.555, 0.152), (-0.30, 0.975, 0.598, 0.146), (-0.15, 0.97, 0.595, 0.146),
                 (0.0, 0.97, 0.56, 0.156), (0.15, 0.98, 0.53, 0.16), (0.30, 1.025, 0.522, 0.146),
                 (0.435, 1.005, 0.548, 0.124)) + [
              (0.545, 0.885, 0.10, 0.19, 0.145, 'p'), (0.615, 0.985, 0.078, 0.125, 0.105, 'p'),
              (0.67, 1.075, 0.065, 0.088, 0.088, 'p'), (0.715, 1.165, 0.056, 0.07, 0.072, 'p'),
              (0.752, 1.245, 0.05, 0.06, 0.064, 'p'), (0.79, 1.31, 0.05, 0.056, 0.062, 'c'),
              (0.845, 1.348, 0.056, 0.054, 0.066, 'c'), (0.91, 1.335, 0.053, 0.048, 0.061, 'c'),
              (0.98, 1.297, 0.039, 0.039, 0.044, 'b'), (1.045, 1.26, 0.029, 0.03, 0.032, 'b'),
              (1.085, 1.237, 0.021, 0.023, 0.022, 'b')],
        ossos=dict(corpo=((-0.40, 0.86), (-0.02, 0.87)), peito=((-0.02, 0.87), (0.40, 0.89)),
                   pescoco1=((0.52, 0.87), (0.645, 1.03)), pescoco2=((0.645, 1.03), (0.775, 1.285)),
                   cabeca=((0.793, 1.33), (1.088, 1.232)), mandibula=((0.838, 1.30), (1.058, 1.217))),
        juntas_larg=(0.30, 0.16, 0.12, 0.07),
        dianteira=dict(e=(0.30, 0.05, 0.97), o=(0.52, 0.092, 0.70), c=(0.41, 0.098, 0.545), k=(0.43, 0.092, 0.30),
                       f=(0.44, 0.09, 0.085), t=(0.515, 0.09, 0.0)),
        traseira=dict(q=(-0.40, 0.082, 0.80), j=(-0.26, 0.096, 0.565), k=(-0.485, 0.084, 0.36), f=(-0.455, 0.08, 0.085),
                      t=(-0.38, 0.08, 0.0)),
        perfil_f=[('p', 0.58, 0.74, 0.42, 0.74, 0.038, 0.07, 0.85), ('p', 0.55, 0.64, 0.38, 0.64, 0.042, 0.078, 0.4),
                  ('p', 0.50, 0.56, 0.35, 0.552, 0.04, 0.086, 0.1), ('p', 0.478, 0.49, 0.372, 0.49, 0.035, 0.09, 0.0),
                  ('p', 0.468, 0.41, 0.40, 0.41, 0.028, 0.09, 0.0), ('p', 0.46, 0.33, 0.414, 0.33, 0.021, 0.09, 0.0),
                  ('p', 0.458, 0.29, 0.41, 0.29, 0.0215, 0.09, 0.0), ('p', 0.455, 0.235, 0.425, 0.235, 0.0145, 0.09, 0.0),
                  ('p', 0.455, 0.15, 0.43, 0.15, 0.013, 0.09, 0.0), ('p', 0.463, 0.095, 0.424, 0.083, 0.0155, 0.09, 0.0),
                  ('o', 3, 0.5, 0.0155, 0.016, 0.0, 0.0)], baixa_f=4,
        perfil_t=[('p', -0.31, 0.84, -0.57, 0.84, 0.05, 0.07, 0.85), ('p', -0.28, 0.71, -0.59, 0.71, 0.064, 0.078, 0.45),
                  ('p', -0.235, 0.62, -0.575, 0.62, 0.07, 0.085, 0.15), ('p', -0.222, 0.565, -0.47, 0.555, 0.044, 0.077, 0.0),
                  ('p', -0.285, 0.50, -0.505, 0.49, 0.04, 0.081, 0.0), ('p', -0.35, 0.44, -0.536, 0.43, 0.035, 0.086, 0.0),
                  ('p', -0.43, 0.39, -0.533, 0.38, 0.026, 0.085, 0.0), ('p', -0.465, 0.34, -0.515, 0.34, 0.021, 0.084, 0.0),
                  ('p', -0.46, 0.24, -0.49, 0.24, 0.0145, 0.082, 0.0), ('p', -0.448, 0.14, -0.475, 0.14, 0.0135, 0.081, 0.0),
                  ('p', -0.44, 0.095, -0.477, 0.083, 0.0155, 0.08, 0.0), ('o', 3, 0.5, 0.0155, 0.016, 0.0, 0.0)], baixa_t=5,
        casco_dim=(0.062, 0.021, 0.038, 0.004),
        cauda=dict(pts=[(-0.615, 0.0, 0.935), (-0.655, 0.0, 0.912), (-0.676, 0.0, 0.862), (-0.682, 0.0, 0.80),
                        (-0.68, 0.0, 0.765)],
                   raios=[(0.028, 0.02), (0.034, 0.019), (0.032, 0.017), (0.026, 0.015), (0.012, 0.009)], ossos=2),
        orelha=dict(base=(0.826, 0.04, 1.39), eixo=(-0.42, 0.74, 0.52), abre=(0.75, 0.5, 0.1), comp=0.13,
                    larg=0.066, conc=0.012),
        olho=(0.919, 0.0425, 1.362, 0.0135),
        placas=dict(base=(0.888, 0.024, 1.386), comp=0.22, larg=(0.10, 0.045), esp=(0.011, 0.006),
                    ang=(0.05, 1.6), abre=0.12),
        nodulos=dict(de=0.22, ate=0.96, n=8, tam=(0.014, 0.009)),
        andar=dict(tipo='passo', ciclo=0.85, duty=0.63, fases=dict(te=0.0, fe=0.25, td=0.5, fd=0.75),
                   h_f=0.10, h_t=0.065, dobra_f=-1.20, dobra_t=0.45, flex_f=0.55, flex_t=0.55, alfa_f=0.45,
                   alfa_t=0.45, bob=0.010, rola=0.012, aceno=0.035, dx_f=-0.03),
        correr=dict(tipo='galope', ciclo=2.0, duty=0.32, fases=dict(te=0.0, td=0.09, fe=0.33, fd=0.42),
                    h_f=0.22, h_t=0.18, dobra_f=-1.25, dobra_t=0.6, flex_f=0.55, flex_t=0.6, alfa_f=0.55,
                    alfa_t=0.55, bob=0.045, susp=0.87, arfa=0.07, arfa_fase=0.2, flexao=0.05, flexao_fase=0.9,
                    aceno=0.12, dx_f=0.04, dx_t=0.02),
        postura=dict(andar=dict(pescoco1=0.18, cabeca=-0.12), correr=dict(pescoco1=0.42, pescoco2=0.05, cabeca=-0.25)),
    ),
    'corcova': dict(
        nome='Corcova', grupo='herbivoro', pe='casco', lados=12, zona=zona_corcova,
        cores=dict(dorso=(0.050, 0.033, 0.022), barriga=(0.036, 0.026, 0.019), marca1=(0.15, 0.085, 0.040),
                   marca2=(0.018, 0.014, 0.011), fino=70.0, largo=4.0, aspereza=0.9),
        focinho=(0.018, 0.016, 0.015), casco=(0.025, 0.022, 0.02), boca=(0.22, 0.07, 0.06),
        quad=dict(t=(2.4, 3.0), p=(2.2, 2.2), c=(2.3, 2.3), b=(2.2, 2.2)),
        desgrenhado=dict(x0=0.0, x1=1.0, amp=0.04),
        tubo=_tr((-0.80, 0.90, 0.82, 0.04), (-0.78, 0.97, 0.73, 0.11), (-0.70, 0.99, 0.60, 0.168),
                 (-0.56, 0.99, 0.53, 0.195), (-0.36, 1.0, 0.515, 0.208), (-0.14, 1.05, 0.49, 0.225),
                 (0.06, 1.14, 0.455, 0.245), (0.24, 1.25, 0.43, 0.262), (0.40, 1.23, 0.42, 0.258),
                 (0.55, 1.10, 0.445, 0.238)) + [
              (0.665, 0.84, 0.18, 0.21, 0.26, 'p'), (0.765, 0.80, 0.148, 0.17, 0.205, 'p'),
              (0.845, 0.765, 0.152, 0.155, 0.165, 'c'), (0.92, 0.705, 0.148, 0.135, 0.142, 'c'),
              (0.972, 0.618, 0.135, 0.112, 0.116, 'c'), (1.0, 0.535, 0.122, 0.09, 0.088, 'b'),
              (1.015, 0.465, 0.114, 0.074, 0.068, 'b'), (1.02, 0.42, 0.10, 0.06, 0.05, 'b')],
        ossos=dict(corpo=((-0.55, 0.85), (-0.05, 0.88)), peito=((-0.05, 0.88), (0.50, 0.92)),
                   pescoco1=((0.58, 0.86), (0.72, 0.82)), pescoco2=((0.72, 0.82), (0.82, 0.78)),
                   cabeca=((0.84, 0.79), (1.02, 0.42)), mandibula=((0.88, 0.69), (0.99, 0.43))),
        juntas_larg=(0.35, 0.18, 0.10, 0.08),
        dianteira=dict(e=(0.24, 0.085, 1.07), o=(0.53, 0.15, 0.66), c=(0.405, 0.16, 0.455), k=(0.44, 0.15, 0.25),
                       f=(0.45, 0.14, 0.08), t=(0.545, 0.14, 0.0)),
        traseira=dict(q=(-0.55, 0.11, 0.80), j=(-0.405, 0.13, 0.53), k=(-0.63, 0.112, 0.33), f=(-0.60, 0.105, 0.08),
                      t=(-0.505, 0.105, 0.0)),
        perfil_f=[('p', 0.62, 0.70, 0.40, 0.70, 0.07, 0.12, 0.85), ('p', 0.60, 0.58, 0.34, 0.58, 0.078, 0.14, 0.4),
                  ('p', 0.54, 0.47, 0.33, 0.46, 0.072, 0.152, 0.1), ('p', 0.515, 0.40, 0.355, 0.40, 0.062, 0.156, 0.0),
                  ('p', 0.49, 0.32, 0.39, 0.32, 0.046, 0.155, 0.0), ('p', 0.48, 0.25, 0.40, 0.25, 0.038, 0.152, 0.0),
                  ('p', 0.47, 0.18, 0.425, 0.18, 0.027, 0.15, 0.0), ('p', 0.476, 0.09, 0.425, 0.078, 0.029, 0.145, 0.0),
                  ('o', 3, 0.5, 0.029, 0.029, 0.0, 0.0)], baixa_f=4,
        perfil_t=[('p', -0.43, 0.84, -0.72, 0.84, 0.07, 0.10, 0.85), ('p', -0.40, 0.69, -0.76, 0.69, 0.085, 0.10, 0.45),
                  ('p', -0.37, 0.58, -0.74, 0.58, 0.095, 0.12, 0.15), ('p', -0.36, 0.53, -0.63, 0.52, 0.064, 0.11, 0.0),
                  ('p', -0.42, 0.46, -0.645, 0.45, 0.056, 0.118, 0.0), ('p', -0.51, 0.40, -0.69, 0.39, 0.048, 0.12, 0.0),
                  ('p', -0.59, 0.35, -0.68, 0.345, 0.038, 0.115, 0.0), ('p', -0.60, 0.25, -0.65, 0.25, 0.026, 0.11, 0.0),
                  ('p', -0.595, 0.15, -0.64, 0.15, 0.025, 0.108, 0.0), ('p', -0.58, 0.09, -0.637, 0.078, 0.028, 0.105, 0.0),
                  ('o', 3, 0.5, 0.028, 0.028, 0.0, 0.0)], baixa_t=5,
        casco_dim=(0.10, 0.037, 0.06, 0.006),
        cauda=dict(pts=[(-0.77, 0.0, 0.94), (-0.81, 0.0, 0.87), (-0.822, 0.0, 0.73), (-0.828, 0.0, 0.57)],
                   raios=[(0.03, 0.03), (0.022, 0.022), (0.016, 0.016), (0.014, 0.014)], ossos=2, tufo=0.04),
        orelha=dict(base=(0.88, 0.128, 0.74), eixo=(-0.2, 0.95, -0.15), abre=(0.6, 0.2, 0.75), comp=0.085,
                    larg=0.05, conc=0.008),
        olho=(0.962, 0.112, 0.655, 0.015),
        chifres=dict(base=(0.885, 0.11, 0.835), pts=((0.0, 0.07, 0.0), (0.02, 0.11, 0.04), (0.06, 0.12, 0.10),
                                                     (0.09, 0.10, 0.14)), raio=0.034),
        nodulos=dict(de=0.15, ate=0.58, n=9, tam=(0.028, 0.018), corcova=True),
        barba=True,
        andar=dict(tipo='passo', ciclo=0.85, duty=0.65, fases=dict(te=0.0, fe=0.25, td=0.5, fd=0.75),
                   h_f=0.10, h_t=0.07, dobra_f=-1.1, dobra_t=0.4, flex_f=0.5, flex_t=0.5, alfa_f=0.4,
                   alfa_t=0.4, bob=0.012, rola=0.018, aceno=0.03, dx_f=-0.03),
        correr=dict(tipo='galope', ciclo=1.7, duty=0.36, fases=dict(te=0.0, td=0.09, fe=0.33, fd=0.42),
                    h_f=0.18, h_t=0.15, dobra_f=-1.15, dobra_t=0.55, flex_f=0.5, flex_t=0.5, alfa_f=0.5,
                    alfa_t=0.5, bob=0.035, susp=0.9, arfa=0.06, arfa_fase=0.2, flexao=0.04, flexao_fase=0.9,
                    aceno=0.08, dx_f=0.03, dx_t=0.02),
        postura=dict(andar=dict(), correr=dict(pescoco1=0.05, cabeca=0.1)),
        pastar=dict(pescoco2=0.0, cara=0.62, peito=0.08, pitch=0.07, dz=0.0, faixa=(-0.4, 1.2), orelha=0.2,
                    pes={'fe': (-0.03, 0.02, 0), 'fd': (-0.09, -0.02, 0), 'te': (0.03, 0, 0), 'td': (0.0, 0, 0)}),
        alerta=dict(pescoco1=-0.15, pescoco2=-0.05, cabeca=-0.15, cauda=-0.3),
    ),
    'uivador': dict(
        nome='Uivador', coxa_volume=0.17, grupo='predador', pe='pata', lados=12, zona=zona_uivador,
        cores=dict(dorso=(0.25, 0.205, 0.135), barriga=(0.56, 0.51, 0.41), marca1=(0.045, 0.040, 0.034),
                   marca2=(0.42, 0.27, 0.11), fino=160.0, largo=8.0),
        focinho=(0.02, 0.018, 0.017), casco=(0.03, 0.027, 0.025), boca=(0.34, 0.10, 0.10),
        quad=dict(t=(2.2, 2.8), p=(2.1, 2.1), c=(2.1, 2.1), b=(2.0, 2.0)),
        tubo=_tr((-0.462, 0.62, 0.56, 0.025), (-0.443, 0.66, 0.50, 0.058), (-0.39, 0.67, 0.425, 0.088),
                 (-0.30, 0.668, 0.40, 0.096), (-0.18, 0.658, 0.452, 0.086), (-0.05, 0.66, 0.41, 0.094),
                 (0.07, 0.672, 0.355, 0.10), (0.18, 0.70, 0.335, 0.097), (0.29, 0.688, 0.355, 0.088)) + [
              (0.36, 0.56, 0.086, 0.122, 0.122, 'p'), (0.43, 0.60, 0.079, 0.10, 0.10, 'p'),
              (0.49, 0.635, 0.07, 0.08, 0.08, 'p'), (0.532, 0.665, 0.064, 0.062, 0.064, 'c'),
              (0.574, 0.68, 0.074, 0.066, 0.069, 'c'), (0.613, 0.677, 0.071, 0.062, 0.07, 'c'),
              (0.641, 0.659, 0.051, 0.041, 0.061, 'c'), (0.668, 0.649, 0.043, 0.036, 0.048, 'b'),
              (0.702, 0.642, 0.038, 0.032, 0.04, 'b'), (0.732, 0.637, 0.032, 0.029, 0.032, 'b'),
              (0.752, 0.635, 0.024, 0.022, 0.022, 'b')],
        ossos=dict(corpo=((-0.30, 0.58), (-0.02, 0.585)), peito=((-0.02, 0.585), (0.26, 0.60)),
                   pescoco1=((0.34, 0.57), (0.43, 0.61)), pescoco2=((0.43, 0.61), (0.525, 0.655)),
                   cabeca=((0.54, 0.676), (0.752, 0.635)), mandibula=((0.582, 0.642), (0.742, 0.616))),
        juntas_larg=(0.25, 0.12, 0.08, 0.05),
        dianteira=dict(e=(0.19, 0.04, 0.66), o=(0.33, 0.068, 0.47), c=(0.245, 0.07, 0.335), k=(0.268, 0.066, 0.10),
                       f=(0.292, 0.064, 0.032), t=(0.37, 0.064, 0.0)),
        traseira=dict(q=(-0.30, 0.058, 0.55), j=(-0.20, 0.072, 0.355), k=(-0.355, 0.06, 0.18), f=(-0.302, 0.058, 0.032),
                      t=(-0.228, 0.058, 0.0)),
        perfil_f=[('p', 0.38, 0.52, 0.25, 0.52, 0.03, 0.05, 0.85), ('p', 0.365, 0.43, 0.215, 0.43, 0.033, 0.058, 0.4),
                  ('p', 0.315, 0.355, 0.205, 0.345, 0.031, 0.065, 0.1), ('p', 0.296, 0.29, 0.225, 0.29, 0.027, 0.066, 0.0),
                  ('p', 0.291, 0.21, 0.245, 0.21, 0.021, 0.066, 0.0), ('p', 0.287, 0.14, 0.254, 0.14, 0.0165, 0.066, 0.0),
                  ('p', 0.287, 0.10, 0.25, 0.10, 0.0175, 0.066, 0.0), ('p', 0.302, 0.055, 0.268, 0.05, 0.0165, 0.065, 0.0),
                  ('p', 0.312, 0.025, 0.285, 0.022, 0.0165, 0.064, 0.0)], baixa_f=4,
        perfil_t=[('p', -0.23, 0.60, -0.39, 0.60, 0.03, 0.048, 0.85), ('p', -0.21, 0.48, -0.40, 0.48, 0.04, 0.056, 0.45),
                  ('p', -0.185, 0.40, -0.38, 0.40, 0.038, 0.062, 0.15), ('p', -0.18, 0.355, -0.33, 0.35, 0.03, 0.058, 0.0),
                  ('p', -0.215, 0.30, -0.35, 0.295, 0.028, 0.062, 0.0), ('p', -0.27, 0.245, -0.385, 0.24, 0.022, 0.064, 0.0),
                  ('p', -0.335, 0.20, -0.385, 0.195, 0.016, 0.062, 0.0), ('p', -0.34, 0.17, -0.38, 0.165, 0.0145, 0.06, 0.0),
                  ('p', -0.325, 0.10, -0.35, 0.10, 0.0125, 0.059, 0.0), ('p', -0.30, 0.045, -0.33, 0.04, 0.015, 0.058, 0.0),
                  ('p', -0.288, 0.022, -0.315, 0.02, 0.015, 0.058, 0.0)], baixa_t=5,
        pata_f=(0.088, 0.054, 0.032), pata_t=(0.078, 0.048, 0.03),
        cauda=dict(pts=[(-0.43, 0.0, 0.635), (-0.49, 0.0, 0.60), (-0.54, 0.0, 0.525), (-0.575, 0.0, 0.43),
                        (-0.592, 0.0, 0.34), (-0.598, 0.0, 0.27)],
                   raios=[(0.022, 0.022), (0.03, 0.029), (0.035, 0.034), (0.034, 0.033), (0.026, 0.025), (0.008, 0.008)],
                   ossos=3),
        orelha=dict(base=(0.566, 0.047, 0.736), eixo=(-0.12, 0.30, 0.95), abre=(0.9, 0.3, 0.05), comp=0.092,
                    larg=0.07, conc=0.012, perfil=((0.0, 1.0), (0.3, 0.84), (0.6, 0.56), (0.85, 0.24), (1.0, 0.0))),
        olho=(0.632, 0.043, 0.704, 0.0098),
        crista=dict(de=0.53, ate=0.632, n=5, alt=(0.014, 0.026)),
        dentes=True,
        andar=dict(tipo='passo', ciclo=0.72, duty=0.62, fases=dict(te=0.0, fe=0.25, td=0.5, fd=0.75),
                   h_f=0.065, h_t=0.05, dobra_f=-1.1, dobra_t=0.4, flex_f=0.6, flex_t=0.55, alfa_f=0.5,
                   alfa_t=0.5, bob=0.007, rola=0.012, aceno=0.025, dx_f=-0.03),
        correr=dict(tipo='galope', ciclo=1.7, duty=0.28, fases=dict(fe=0.0, fd=0.1, td=0.45, te=0.55),
                    h_f=0.11, h_t=0.12, dobra_f=-1.1, dobra_t=0.65, flex_f=0.55, flex_t=0.6, alfa_f=0.6,
                    alfa_t=0.6, bob=0.018, susp=0.86, arfa=0.06, arfa_fase=0.65, flexao=0.10, flexao_fase=0.4,
                    aceno=0.10, dx_f=-0.06, dx_t=0.0, abre_f=0.25),
        espreitar=dict(tipo='passo', ciclo=0.42, duty=0.76, fases=dict(te=0.0, fe=0.25, td=0.5, fd=0.75),
                       h_f=0.05, h_t=0.035, dobra_f=-0.9, dobra_t=0.35, flex_f=0.5, flex_t=0.5, alfa_f=0.4,
                       alfa_t=0.4, bob=0.004, rola=0.008, aceno=0.0, dz=-0.13, rlim_f=(0.45, 0.86),
                       rlim_t=(0.40, 0.80), dx_f=0.04, dx_t=-0.02, abre_f=0.9, abre_t=0.5),
        postura=dict(andar=dict(pescoco1=0.10, cabeca=0.0), correr=dict(pescoco1=0.30, cabeca=0.05),
                     espreitar=dict(pescoco1=0.55, pescoco2=0.1, cabeca=-0.08, pitch=0.02)),
        deitado=dict(pescoco1=-0.30, pescoco2=-0.08, cabeca=0.25, abre_f=0.02, abre_t=0.035, jarrete=-0.02),
        morto_orelha=(1.1, 0.25),
    ),
    'espreitador': dict(
        nome='Espreitador', coxa_volume=0.17, grupo='predador', pe='pata', lados=12, zona=zona_espreitador,
        cores=dict(dorso=(0.36, 0.25, 0.12), barriga=(0.64, 0.60, 0.52), marca1=(0.05, 0.035, 0.022),
                   marca2=(0.66, 0.62, 0.55), pinta=(0.035, 0.026, 0.018), pinta_escala=21.0, fino=170.0, largo=8.0),
        focinho=(0.09, 0.045, 0.04), casco=(0.035, 0.03, 0.028), boca=(0.34, 0.10, 0.10),
        quad=dict(t=(2.2, 2.8), p=(2.1, 2.1), c=(2.0, 2.0), b=(2.0, 2.0)),
        tubo=_tr((-0.512, 0.53, 0.48, 0.022), (-0.492, 0.568, 0.43, 0.055), (-0.432, 0.585, 0.35, 0.085),
                 (-0.33, 0.59, 0.31, 0.096), (-0.19, 0.572, 0.31, 0.092), (-0.04, 0.567, 0.318, 0.094),
                 (0.09, 0.582, 0.305, 0.096), (0.21, 0.612, 0.295, 0.092), (0.32, 0.592, 0.31, 0.082)) + [
              (0.395, 0.47, 0.072, 0.098, 0.093, 'p'), (0.45, 0.515, 0.068, 0.076, 0.074, 'p'),
              (0.495, 0.562, 0.067, 0.07, 0.07, 'c'), (0.545, 0.588, 0.074, 0.072, 0.07, 'c'),
              (0.596, 0.582, 0.067, 0.06, 0.062, 'c'), (0.635, 0.564, 0.049, 0.042, 0.044, 'b'),
              (0.663, 0.553, 0.04, 0.033, 0.033, 'b'), (0.68, 0.546, 0.031, 0.026, 0.024, 'b')],
        ossos=dict(corpo=((-0.34, 0.49), (-0.03, 0.49)), peito=((-0.03, 0.49), (0.28, 0.50)),
                   pescoco1=((0.37, 0.475), (0.445, 0.52)), pescoco2=((0.445, 0.52), (0.49, 0.565)),
                   cabeca=((0.50, 0.575), (0.68, 0.546)), mandibula=((0.535, 0.555), (0.668, 0.532))),
        juntas_larg=(0.28, 0.12, 0.07, 0.05),
        dianteira=dict(e=(0.22, 0.04, 0.57), o=(0.345, 0.07, 0.40), c=(0.262, 0.074, 0.27), k=(0.285, 0.07, 0.085),
                       f=(0.305, 0.068, 0.028), t=(0.378, 0.068, 0.0)),
        traseira=dict(q=(-0.34, 0.06, 0.45), j=(-0.22, 0.074, 0.28), k=(-0.40, 0.062, 0.15), f=(-0.348, 0.06, 0.028),
                      t=(-0.278, 0.06, 0.0)),
        perfil_f=[('p', 0.40, 0.45, 0.27, 0.45, 0.033, 0.055, 0.85), ('p', 0.38, 0.36, 0.235, 0.36, 0.04, 0.064, 0.4),
                  ('p', 0.33, 0.29, 0.22, 0.28, 0.037, 0.072, 0.1), ('p', 0.315, 0.23, 0.24, 0.23, 0.031, 0.073, 0.0),
                  ('p', 0.305, 0.16, 0.255, 0.16, 0.025, 0.072, 0.0), ('p', 0.302, 0.10, 0.262, 0.10, 0.021, 0.07, 0.0),
                  ('p', 0.303, 0.08, 0.262, 0.08, 0.021, 0.07, 0.0), ('p', 0.315, 0.045, 0.28, 0.04, 0.02, 0.069, 0.0),
                  ('p', 0.325, 0.022, 0.295, 0.02, 0.02, 0.068, 0.0)], baixa_f=4,
        perfil_t=[('p', -0.26, 0.50, -0.43, 0.50, 0.032, 0.05, 0.85), ('p', -0.225, 0.39, -0.46, 0.39, 0.045, 0.058, 0.45),
                  ('p', -0.195, 0.32, -0.45, 0.32, 0.045, 0.064, 0.15), ('p', -0.195, 0.28, -0.39, 0.275, 0.034, 0.06, 0.0),
                  ('p', -0.24, 0.23, -0.40, 0.225, 0.029, 0.064, 0.0), ('p', -0.30, 0.19, -0.43, 0.185, 0.023, 0.066, 0.0),
                  ('p', -0.375, 0.16, -0.425, 0.155, 0.018, 0.063, 0.0), ('p', -0.37, 0.10, -0.40, 0.10, 0.016, 0.062, 0.0),
                  ('p', -0.345, 0.045, -0.38, 0.04, 0.018, 0.061, 0.0), ('p', -0.33, 0.02, -0.365, 0.018, 0.018, 0.06, 0.0)],
        baixa_t=5,
        pata_f=(0.086, 0.066, 0.034), pata_t=(0.074, 0.056, 0.031),
        cauda=dict(pts=[(-0.478, 0.0, 0.548), (-0.55, 0.0, 0.505), (-0.625, 0.0, 0.415), (-0.70, 0.0, 0.305),
                        (-0.785, 0.0, 0.225), (-0.88, 0.0, 0.195), (-0.97, 0.0, 0.215), (-1.035, 0.0, 0.27)],
                   raios=[(0.027, 0.027), (0.024, 0.024), (0.021, 0.021), (0.019, 0.019), (0.018, 0.018),
                          (0.018, 0.018), (0.018, 0.018), (0.012, 0.012)], ossos=3),
        orelha=dict(base=(0.54, 0.052, 0.645), eixo=(-0.2, 0.45, 0.87), abre=(0.9, 0.3, 0.1), comp=0.055,
                    larg=0.05, conc=0.008, perfil=((0.0, 1.0), (0.35, 0.95), (0.7, 0.62), (0.92, 0.25), (1.0, 0.0))),
        olho=(0.603, 0.038, 0.611, 0.0125), nariz=(0.018, 0.012),
        esporoes=dict(comp=0.058, raio=0.0075),
        dentes=True,
        andar=dict(tipo='passo', ciclo=0.62, duty=0.65, fases=dict(te=0.0, fe=0.25, td=0.5, fd=0.75),
                   h_f=0.055, h_t=0.045, dobra_f=-1.0, dobra_t=0.4, flex_f=0.6, flex_t=0.55, alfa_f=0.5,
                   alfa_t=0.5, bob=0.005, rola=0.01, aceno=0.02, dx_f=-0.03),
        correr=dict(tipo='galope', ciclo=1.55, duty=0.27, fases=dict(fe=0.0, fd=0.1, td=0.45, te=0.55),
                    h_f=0.10, h_t=0.11, dobra_f=-1.1, dobra_t=0.65, flex_f=0.55, flex_t=0.6, alfa_f=0.6,
                    alfa_t=0.6, bob=0.016, susp=0.86, arfa=0.05, arfa_fase=0.65, flexao=0.14, flexao_fase=0.4,
                    aceno=0.08, dx_f=-0.06, dx_t=0.0, abre_f=0.25),
        espreitar=dict(tipo='passo', ciclo=0.34, duty=0.78, fases=dict(te=0.0, fe=0.25, td=0.5, fd=0.75),
                       h_f=0.045, h_t=0.03, dobra_f=-0.9, dobra_t=0.35, flex_f=0.5, flex_t=0.5, alfa_f=0.4,
                       alfa_t=0.4, bob=0.003, rola=0.006, aceno=0.0, dz=-0.15, rlim_f=(0.42, 0.85),
                       rlim_t=(0.38, 0.78), dx_f=0.05, dx_t=-0.03, abre_f=0.9, abre_t=0.5),
        postura=dict(andar=dict(pescoco1=0.12, cabeca=0.0), correr=dict(pescoco1=0.25, cabeca=0.05),
                     espreitar=dict(pescoco1=0.45, pescoco2=0.05, cabeca=-0.10, pitch=0.0)),
        deitado=dict(pescoco1=-0.42, pescoco2=-0.08, cabeca=0.32, abre_f=0.022, abre_t=0.035, jarrete=-0.02),
        morto_orelha=(1.0, 0.25),
    ),
}
MAT = {}
for _n, P_ in ESPECIES.items():
    MAT[_n] = [pelagem_mat(_n + 'Pelo', P_['cores']), liso_mat(_n + 'Focinho', P_['focinho'], 0.35, 0.3),
               liso_mat('Olho', (0.008, 0.008, 0.008), 0.08, 1.0), liso_mat(_n + 'Osso', OSSO_COR, 0.45, 0.15),
               liso_mat(_n + 'Casco', P_['casco'], 0.45, 0.2), liso_mat(_n + 'Boca', P_['boca'], 0.5),
               liso_mat(_n + 'Dente', (0.72, 0.68, 0.58), 0.35, 0.2)]


# ------------------------------------------------------------------ montagem: uma malha, pesos por regra
class Malha:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap')
        self.lparte = self.bm.faces.layers.int.new('parte')
        self.pesos = {}
        self.zona = {}
        self.parte = 0

    def v(self, co, pesos, zona=(0.0, 0.0, 0.0)):
        vv = self.bm.verts.new(co)
        self.pesos[vv] = pesos
        self.zona[vv] = zona
        return vv

    def f(self, vs, mat, parte=None):
        try:
            fa = self.bm.faces.new(vs)
        except ValueError:
            return None
        fa.material_index = mat
        fa.smooth = True
        fa[self.lparte] = self.parte if parte is None else parte
        return fa

    def ngon_ou_leque(self, vs, mat, parte=None, centro=None, pesos=None, zona=None):
        """Fecha um anel: com `centro`, leque de triângulos até ele; senão, uma face só."""
        if centro is None:
            return self.f(vs, mat, parte)
        c = self.v(centro, pesos if pesos is not None else self.pesos[vs[0]], zona if zona is not None else self.zona[vs[0]])
        for i in range(len(vs)):
            self.f((vs[i], vs[(i + 1) % len(vs)], c), mat, parte)
        return c


def _catmull(p0, p1, p2, p3, t):
    return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def subdividir(secs):
    out = []
    n = len(secs)
    for i in range(n - 1):
        p0, p1, p2, p3 = secs[max(i - 1, 0)], secs[i], secs[i + 1], secs[min(i + 2, n - 1)]
        out.append(p1)
        meio = tuple(_catmull(p0[k], p1[k], p2[k], p3[k], 0.5) for k in range(5))
        out.append((*meio, p1[5] if p1[5] == p2[5] else p2[5]))
    out.append(secs[-1])
    return out


def _superelipse(a, e):
    ca, sa = math.cos(a), math.sin(a)
    return math.copysign(abs(ca) ** (2.0 / e), ca), math.copysign(abs(sa) ** (2.0 / e), sa)


def _proj_s(pts, s_acc, p):
    """Comprimento (ao longo da linha das seções) do ponto da linha mais perto de p."""
    melhor = (1e9, 0.0)
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
        d = (a + ab * t - p).length
        if d < melhor[0]:
            melhor = (d, s_acc[i] + ab.length * t)
    return melhor[1]


def montar(nome, especie, origem=Vector((0, 0, 0)), giro=0.0):
    P = ESPECIES[especie]
    arm_d = bpy.data.armatures.new(nome + '_esqueleto')
    arm = bpy.data.objects.new(nome, arm_d)
    sc.collection.objects.link(arm)
    arm.location = origem
    arm.rotation_euler = (0, 0, giro)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')

    def osso(n, a, b, pai=None):
        e = arm_d.edit_bones.new(n)
        e.head, e.tail, e.roll = Vector(a), Vector(b), 0.0
        if pai:
            e.parent = arm_d.edit_bones[pai]

    def v3(p2, y=0.0):
        return Vector((p2[0], y, p2[1]))
    ob = P['ossos']
    osso('corpo', v3(ob['corpo'][0]), v3(ob['corpo'][1]))
    for n, pai in (('peito', 'corpo'), ('pescoco1', 'peito'), ('pescoco2', 'pescoco1'), ('cabeca', 'pescoco2'),
                   ('mandibula', 'cabeca')):
        osso(n, v3(ob[n][0]), v3(ob[n][1]), pai)
    ca = P['cauda']
    cpts = [Vector(p) for p in ca['pts']]
    clen = [0.0]
    for a, b in zip(cpts, cpts[1:]):
        clen.append(clen[-1] + (b - a).length)
    no = ca['ossos']

    def ponto_cauda(s):
        for i in range(len(cpts) - 1):
            if s <= clen[i + 1] or i == len(cpts) - 2:
                t = (s - clen[i]) / max(clen[i + 1] - clen[i], 1e-9)
                return cpts[i].lerp(cpts[i + 1], max(0.0, min(1.0, t)))
    for k in range(no):
        osso(f'cauda{k + 1}', ponto_cauda(clen[-1] * k / no), ponto_cauda(clen[-1] * (k + 1) / no),
             'corpo' if k == 0 else f'cauda{k}')
    o_ = P['orelha']
    for lado, sg in (('e', 1), ('d', -1)):
        b0 = Vector((o_['base'][0], o_['base'][1] * sg, o_['base'][2]))
        ei = Vector((o_['eixo'][0], o_['eixo'][1] * sg, o_['eixo'][2])).normalized()
        osso(f'orelha_{lado}', b0, b0 + ei * o_['comp'], 'cabeca')
        d_ = P['dianteira']
        J = {k: Vector((v[0], v[1] * sg, v[2])) for k, v in d_.items()}
        osso(f'escapula_{lado}', J['e'], J['o'], 'peito')
        osso(f'braco_{lado}', J['o'], J['c'], f'escapula_{lado}')
        osso(f'antebraco_{lado}', J['c'], J['k'], f'braco_{lado}')
        osso(f'mao_{lado}', J['k'], J['f'], f'antebraco_{lado}')
        osso(f'dedof_{lado}', J['f'], J['t'], f'mao_{lado}')
        t_ = P['traseira']
        J = {k: Vector((v[0], v[1] * sg, v[2])) for k, v in t_.items()}
        osso(f'coxa_{lado}', J['q'], J['j'], 'corpo')
        osso(f'canela_{lado}', J['j'], J['k'], f'coxa_{lado}')
        osso(f'pe_{lado}', J['k'], J['f'], f'canela_{lado}')
        osso(f'dedo_{lado}', J['f'], J['t'], f'pe_{lado}')
    bpy.ops.object.mode_set(mode='OBJECT')

    m = Malha()
    zona = P['zona']
    solas = {}
    # ---------------------------------------------------------------- tronco + pescoço + cabeça: um tubo
    secs = P['tubo'] if JOGO_Q else subdividir(P['tubo'])
    L = P['lados'] if JOGO_Q else 2 * P['lados']
    H = L // 2
    cs = [Vector((s[0], 0.0, s[1])) for s in secs]
    s_acc = [0.0]
    for a, b in zip(cs, cs[1:]):
        s_acc.append(s_acc[-1] + (b - a).length)
    juntas = []
    for (n_a, n_b), w in zip((('corpo', 'peito'), ('peito', 'pescoco1'), ('pescoco1', 'pescoco2'), ('pescoco2', 'cabeca')),
                             P['juntas_larg']):
        juntas.append((_proj_s(cs, s_acc, v3(ob[n_b][0])), n_a, n_b, w))
    s_dob = _proj_s(cs, s_acc, v3(ob['mandibula'][0]))
    i_canto = next(i for i, s in enumerate(secs) if s[5] == 'b') - 1
    s_canto = s_acc[i_canto]

    def pesos_coluna(s):
        for sj, a, b, w in juntas:
            if s < sj + w / 2:
                return mistura(a, b, (s - (sj - w / 2)) / w)
        return {'cabeca': 1.0}

    dg = P.get('desgrenhado')
    # pele do flanco e do ombro: acompanha em parte a coxa e o braço (o alto da perna fica dentro do corpo e a pele
    # por cima dele se move junto, como num bicho de verdade; sem isso o alto da coxa aparece como placa colada)
    segs_pele = []
    for sg_, lado_ in ((1, 'e'), (-1, 'd')):
        for nb, jp, a_, b_, k_, fr_ in (('coxa', P['traseira'], 'q', 'j', 0.5, 0.55), ('braco', P['dianteira'], 'o', 'c', 0.35, 0.5)):
            A_ = Vector((jp[a_][0], jp[a_][1] * sg_, jp[a_][2]))
            B_ = Vector((jp[b_][0], jp[b_][1] * sg_, jp[b_][2]))
            segs_pele.append((f'{nb}_{lado_}', sg_, A_, B_, k_, fr_ * (B_ - A_).length))
    # inclinação de cada anel: segue a linha das seções, suavizada no tronco e no pescoço (sem isso o topo do último
    # anel do tronco fica mais baixo e mais atrás que o dorso do primeiro anel do pescoço e a pele dobra na cernelha)
    angs = []
    for i in range(len(cs)):
        t_ = cs[min(i + 1, len(cs) - 1)] - cs[max(i - 1, 0)]
        angs.append(math.atan2(t_.z, t_.x))
    for _ in range(3):
        novo = list(angs)
        for i in range(1, len(cs) - 1):
            if secs[i][5] in ('t', 'p') and secs[i + 1][5] in ('t', 'p', 'c'):
                novo[i] = (angs[i - 1] + 2 * angs[i] + angs[i + 1]) / 4
        angs = novo
    aneis = []           # cada um: ('cheio', [vs]) ou ('boca', [maxila], [mandíbula])
    for i, (x, z, ry, rup, rdn, reg) in enumerate(secs):
        c = cs[i]
        t = Vector((math.cos(angs[i]), 0.0, math.sin(angs[i])))
        lado_v = Y.copy()
        cima = t.cross(lado_v)
        eu, ed = P['quad'][reg]
        pc = pesos_coluna(s_acc[i])
        if s_acc[i] > s_dob:
            fm = 1.0 if reg == 'b' else 0.75 * suave((s_acc[i] - s_dob) / max(s_canto - s_dob, 1e-6))
        else:
            fm = 0.0

        anca_x = P['traseira']['q'][0]
        ed_ = ed if reg != 't' else 2.15 + (ed - 2.15) * suave((x - anca_x - 0.08) / 0.3)   # anca: fundo redondo

        def vert(k, estreita=1.0, mand=False):
            a = 2 * PI * k / L
            cy, sz = _superelipse(a, eu if math.sin(a) >= -1e-9 and not mand else ed_)
            r = rup if (math.sin(a) > 1e-9 and not mand) else rdn
            if mand and abs(math.sin(a)) < 1e-9:
                r = rdn
            p = c + lado_v * (ry * cy * estreita) + cima * (r * sz)
            if dg and dg['x0'] < x < dg['x1'] + 0.5 and reg in ('t', 'p', 'c'):
                amp = dg['amp'] * suave((x - dg['x0']) / 0.25) * (0.6 + 0.4 * math.sin(a))
                p = p + (p - c).normalized() * amp * (0.5 + noise.noise(p * 14.0))
            else:
                p = p + Vector((noise.noise(p * 30), noise.noise(p * 30 + Vector((3, 1, 2))), 0.0)) * 0.0015
            sa = math.sin(a)
            pw = dict(pc)
            if reg == 't':
                for nb, sg_, A_, B_, k_, R_ in segs_pele:     # o volume da coxa é do próprio tronco: a pele
                    if nb.startswith('coxa'):                   # perto do fêmur sai para fora, redonda
                        fb = (1.0 - suave(_dist_seg(p, A_, B_) / (1.25 * R_))) * suave(p.y * sg_ / 0.03)
                        if fb > 0.0:
                            p = p + (p - c).normalized() * (P.get('coxa_volume', 0.12) * R_ * fb)
                for nb, sg_, A_, B_, k_, R_ in segs_pele:
                    f = k_ * (1.0 - suave(_dist_seg(p, A_, B_) / R_)) * suave(p.y * sg_ / 0.04 + 0.5) \
                        * suave((A_.z - p.z) / (0.5 * R_) + 0.3)
                    if f > 0.002:
                        pw = {k2: w * (1.0 - f) for k2, w in pw.items()}
                        pw[nb] = pw.get(nb, 0.0) + f
            if (sa < -0.2 or mand) and fm > 0.0:
                pw = {k_: w * (1.0 - fm) for k_, w in pw.items()}
                pw['mandibula'] = pw.get('mandibula', 0.0) + fm
            zd = dict(reg=reg, x=x, z=p.z, sa=sa, ca=math.cos(a), s=s_acc[i])
            return m.v(p, pw, zona(zd))
        if reg != 'b':
            aneis.append(('cheio', [vert(k) for k in range(L)], reg))
        else:
            mx_ = [vert(k) for k in range(H + 1)]
            md_ = [vert(k, 0.9, True) for k in range(H, L + 1)]
            aneis.append(('boca', mx_, md_, reg))
    PARTE_REG = {'t': P_TRONCO, 'p': P_PESCOCO, 'c': P_CABECA, 'b': P_CABECA}
    for i in range(len(aneis) - 1):
        A, B = aneis[i], aneis[i + 1]
        pt = PARTE_REG[A[-1]] if A[-1] == B[-1] else PARTE_REG[B[-1]]
        if A[0] == 'cheio' and B[0] == 'cheio':
            a, b = A[1], B[1]
            for k in range(L):
                j = (k + 1) % L
                m.f((a[k], a[j], b[j], b[k]), I_PELO, pt)
        else:
            if A[0] == 'cheio':
                au, ad = A[1][:H + 1], A[1][H:] + [A[1][0]]
            else:
                au, ad = A[1], A[2]
            bu, bd = B[1], B[2]
            for k in range(H):
                m.f((au[k], au[k + 1], bu[k + 1], bu[k]), I_PELO, pt)
                m.f((ad[k], ad[k + 1], bd[k + 1], bd[k]), I_PELO, P_MANDIBULA)
            if A[0] == 'cheio':
                m.f((au[H], au[0], bu[0], bu[H]), I_BOCA, P_CABECA)          # palato
                m.f((au[0], au[H], bd[0], bd[H]), I_BOCA, P_MANDIBULA)       # língua
            else:
                m.f((au[H], au[0], bu[0], bu[H]), I_BOCA, P_CABECA)
                m.f((ad[H], ad[0], bd[0], bd[H]), I_BOCA, P_MANDIBULA)
    # tampas: anca (leque) e focinho (maxila: nariz; mandíbula: queixo)
    a0 = aneis[0][1]
    m.ngon_ou_leque(a0[::-1], I_PELO, P_TRONCO, centro=cs[0] - (cs[1] - cs[0]).normalized() * 0.01)
    ult = aneis[-1]
    tf = (cs[-1] - cs[-2]).normalized()
    if P.get('nariz'):            # felino: focinho de pelo, só um narizinho de couro na ponta
        cn = m.ngon_ou_leque(ult[1], I_PELO, P_CABECA, centro=cs[-1] + tf * 0.006)
        cm_ = t.cross(Y)
        w_, h_ = P['nariz']
        base_n = cs[-1] + tf * 0.0075 + cm_ * secs[-1][3] * 0.35
        vs_ = [m.v(base_n + Y * w_ / 2, {'cabeca': 1.0}), m.v(base_n - Y * w_ / 2, {'cabeca': 1.0}),
               m.v(base_n - cm_ * h_, {'cabeca': 1.0})]
        m.f(vs_, I_FOCINHO, P_CABECA)
    else:
        m.ngon_ou_leque(ult[1], I_FOCINHO, P_CABECA, centro=cs[-1] + tf * 0.006)
    m.ngon_ou_leque(ult[2], I_PELO, P_MANDIBULA, centro=cs[-1] + tf * 0.002 - t.cross(Y) * secs[-1][4] * 0.4)

    def largura_tronco(x, z):
        """Meia-largura do tronco (repouso) na altura z da seção em x; 0 fora dele."""
        tr = [(sec, k) for k, sec in enumerate(secs) if sec[5] == 't']
        for (s0, k0), (s1, k1) in zip(tr, tr[1:]):
            if s0[0] <= x <= s1[0]:
                u = (x - s0[0]) / max(s1[0] - s0[0], 1e-9)
                cz, ry, ru, rd = [s0[k] * (1 - u) + s1[k] * u for k in (1, 2, 3, 4)]
                r = ru if z >= cz else rd
                sv = abs(z - cz) / max(r, 1e-6)
                if sv >= 1.0:
                    return 0.0
                eu, ed = P['quad']['t']
                n = eu if z >= cz else ed
                return ry * (1.0 - sv ** n) ** (1.0 / n)
        return 0.0

    def ponto_tubo(s, ang, dentro=0.0):
        """Ponto da superfície do tubo (repouso) no comprimento s e ângulo ang do anel, e os pesos de lá."""
        for i in range(len(secs) - 1):
            if s <= s_acc[i + 1]:
                break
        u = (s - s_acc[i]) / max(s_acc[i + 1] - s_acc[i], 1e-9)
        sec = [secs[i][k] * (1 - u) + secs[i + 1][k] * u for k in range(5)]
        c = Vector((sec[0], 0, sec[1]))
        inc = angs[i] * (1 - u) + angs[min(i + 1, len(angs) - 1)] * u      # a mesma inclinação dos anéis
        t = Vector((math.cos(inc), 0.0, math.sin(inc)))
        cima = t.cross(Y)
        eu, ed = P['quad'][secs[i][5]]
        cy, sz = _superelipse(ang, eu if math.sin(ang) >= 0 else ed)
        r = sec[3] if math.sin(ang) >= 0 else sec[4]
        n = (Y * cy * sec[2] + cima * sz * r)
        return c + n * (1.0 - dentro), n.normalized(), pesos_coluna(s), t, cima

    # ---------------------------------------------------------------- pernas
    for lado, sg in (('e', 1), ('d', -1)):
        for frente in (True, False):
            jp = P['dianteira'] if frente else P['traseira']
            ordem = ('o', 'c', 'k', 'f', 't') if frente else ('q', 'j', 'k', 'f', 't')
            Jt = [Vector((jp[k][0], jp[k][1] * sg, jp[k][2])) for k in ordem]
            nomes = [f'escapula_{lado}' if frente else 'corpo'] + [f'{n}_{lado}' for n in NOMES_PERNA[frente]]
            ch = CHAVE[(lado, frente)]
            an_spec = P['perfil_f' if frente else 'perfil_t']
            i_b = P['baixa_f' if frente else 'baixa_t']
            LP = 6 if JOGO_Q else 10
            segs = [(nomes[k + 1], Jt[k], Jt[k + 1]) for k in range(4)]
            rings = []
            for spec in an_spec:
                if spec[0] == 'p':
                    _, xf, zf, xb, zb, hw, yc, fixo = spec
                    fr, tr_ = Vector((xf, 0, zf)), Vector((xb, 0, zb))
                    # enquanto está na altura do tronco, a perna fica dentro dele (a coxa nasce de dentro do corpo)
                    ytr = largura_tronco((xf + xb) / 2, (zf + zb) / 2) - 0.007
                    if ytr > 0.0 and yc + hw > ytr:
                        hw2 = max(0.55 * hw, ytr - yc)
                        if yc + hw2 > ytr:
                            yc = max(0.012, ytr - hw2)
                        hw = hw2
                    if ytr > 0.0:                 # dentro do corpo: presa à bacia/ao peito (a coxa estica como pele)
                        fixo = max(fixo, 0.8 if not frente else 0.6)
                    c = (fr + tr_) / 2 + Y * (yc * sg)
                    lv, fw, rs, rf = Y.copy(), (fr - tr_) / 2, hw, 1.0
                else:
                    _, seg, t_, rs, rf, off, fixo = spec
                    A, B = Jt[seg], Jt[seg + 1]
                    d = (B - A).normalized()
                    lv = (Y - d * d.y).normalized()
                    fw = d.cross(lv)
                    c = A.lerp(B, t_) + fw * off
                ring = []
                for k in range(LP):
                    a = 2 * PI * k / LP
                    p = c + lv * (rs * math.cos(a)) + fw * (rf * math.sin(a))
                    pw = pesos_perna(p, segs)
                    if fixo > 0.0:
                        pw = {n_: w * (1.0 - fixo) for n_, w in pw.items()}
                        pw[nomes[0]] = pw.get(nomes[0], 0.0) + fixo
                    ring.append(m.v(p, pw, zona(dict(reg='perna', dentro=-math.cos(a) * sg, z=p.z, x=p.x, sa=0.0))))
                rings.append(ring)
            for i in range(len(rings) - 1):
                pt = P_BAIXA[ch] if i >= i_b else P_ALTA[ch]
                for k in range(LP):
                    j = (k + 1) % LP
                    m.f((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]), I_PELO, pt)
            m.ngon_ou_leque(rings[0][::-1], I_PELO, P_ALTA[ch])
            m.ngon_ou_leque(rings[-1], I_PELO, P_BAIXA[ch])
            # casco (2 dedos) ou pata
            F, T = Jt[3], Jt[4]
            pd = {nomes[4]: 1.0}
            m.parte = P_BAIXA[ch]
            if P['pe'] == 'casco':
                solas[ch] = casco(m, P, F, T, sg, pd)
            else:
                solas[ch] = pata(m, P, F, T, sg, pd, frente)
            m.parte = 0
            # esporões ósseos atrás do pulso (espreitador)
            if frente and P.get('esporoes'):
                e_ = P['esporoes']
                C, K = Jt[1], Jt[2]
                d = (K - C).normalized()
                lv = (Y - d * d.y).normalized()
                fw = d.cross(lv)
                raiz = K.lerp(C, 0.12) - fw * 0.017
                pts = []
                for k in range(5):
                    tt = k / 4
                    pts.append(raiz - d * (e_['comp'] * tt * 0.85) - fw * (e_['comp'] * (0.42 * tt + 0.18 * tt * tt)))
                m.parte = P_ESPORAO[ch]
                chifre(m, pts, [e_['raio'] * (1 - 0.85 * k / 4) for k in range(5)], {nomes[2]: 1.0}, I_OSSO,
                       lados=5 if JOGO_Q else 8)
                m.parte = 0
    # ---------------------------------------------------------------- cauda
    ca = P['cauda']
    pts = [Vector(p) for p in ca['pts']]
    if not JOGO_Q:
        pts2, rr2 = [], []
        for i in range(len(pts) - 1):
            p0, p1, p2, p3 = pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, len(pts) - 1)]
            pts2 += [p1, _catmull(p0, p1, p2, p3, 0.5)]
            r1, r2 = ca['raios'][i], ca['raios'][i + 1]
            rr2 += [r1, ((r1[0] + r2[0]) / 2, (r1[1] + r2[1]) / 2)]
        pts2.append(pts[-1])
        rr2.append(ca['raios'][-1])
        pts, raios = pts2, rr2
    else:
        raios = ca['raios']
    acc = [0.0]
    for a, b in zip(pts, pts[1:]):
        acc.append(acc[-1] + (b - a).length)
    LC = 6 if JOGO_Q else 10
    rings = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        lv = (Y - d * d.y).normalized()
        cm = d.cross(lv)
        s = acc[i] / acc[-1]
        f = s * no
        k0 = min(no - 1, int(f))
        pw = mistura(f'cauda{k0 + 1}', f'cauda{min(no, k0 + 2)}', (f - k0 - 0.75) / 0.5) if k0 < no - 1 else {f'cauda{no}': 1.0}
        if s < 0.12:
            pw = mistura('corpo', 'cauda1', s / 0.12)
        ring = []
        for k in range(LC):
            a = 2 * PI * k / LC
            rr = raios[i][0] * (1.0 + (0.12 * noise.noise(p * 40 + Vector((k, 0, 0))) if ca.get('tufo') is None and raios[i][0] > 0.035 else 0.0))
            q = p + lv * (rr * math.cos(a)) + cm * (raios[i][1] * math.sin(a))
            ring.append(m.v(q, pw, zona(dict(reg='cauda', sa=math.sin(a), x=q.x, z=q.z, t=s))))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(LC):
            j = (k + 1) % LC
            m.f((rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]), I_PELO, P_CAUDA)
    m.ngon_ou_leque(rings[0][::-1], I_PELO, P_CAUDA)
    dt = (pts[-1] - pts[-2]).normalized()
    if ca.get('tufo'):
        # tufo de pelo escuro na ponta (corcova): cone que abre e fecha em ponta
        tf = ca['tufo']
        p_ = pts[-1]
        lv = (Y - dt * dt.y).normalized()
        cm = dt.cross(lv)
        anel_t = []
        for kk, (dd, rr) in enumerate(((0.05, tf), (0.12, tf * 0.75))):
            r_ = [m.v(p_ + dt * dd + lv * rr * math.cos(2 * PI * k / LC) + cm * rr * math.sin(2 * PI * k / LC),
                      {f'cauda{no}': 1.0}, (0, 0, 1)) for k in range(LC)]
            anel_t.append(r_)
        for a_, b_ in ((rings[-1], anel_t[0]), (anel_t[0], anel_t[1])):
            for k in range(LC):
                j = (k + 1) % LC
                m.f((a_[k], a_[j], b_[j], b_[k]), I_PELO, P_CAUDA)
        m.ngon_ou_leque(anel_t[1], I_PELO, P_CAUDA, centro=p_ + dt * 0.2)
    else:
        m.ngon_ou_leque(rings[-1], I_PELO, P_CAUDA, centro=pts[-1] + dt * raios[-1][0] * 0.8)
    # ---------------------------------------------------------------- orelhas
    o_ = P['orelha']
    for lado, sg in (('e', 1), ('d', -1)):
        b0 = Vector((o_['base'][0], o_['base'][1] * sg, o_['base'][2]))
        ei = Vector((o_['eixo'][0], o_['eixo'][1] * sg, o_['eixo'][2])).normalized()
        ab = Vector((o_['abre'][0], o_['abre'][1] * sg, o_['abre'][2]))
        m.parte = P_ORELHA
        orelha(m, b0, ei, ab, o_['comp'], o_['larg'], o_['conc'], {f'orelha_{lado}': 1.0}, zona, sg,
               perfil=o_.get('perfil'))
        m.parte = 0
    # ---------------------------------------------------------------- olhos
    ex, ey, ez, er = P['olho']
    for sg in (1, -1):
        res = bmesh.ops.create_uvsphere(m.bm, u_segments=6 if JOGO_Q else 12, v_segments=4 if JOGO_Q else 8, radius=er)
        for vv in res['verts']:
            vv.co = Vector((vv.co.x * 0.9, vv.co.y * 0.75, vv.co.z * 0.85)) + Vector((ex, ey * sg, ez))
            m.pesos[vv] = {'cabeca': 1.0}
            m.zona[vv] = (0, 0, 0)
        for fa in {f for vv in res['verts'] for f in vv.link_faces}:
            fa.material_index = I_OLHO
            fa.smooth = True
            fa[m.lparte] = P_OLHO
    # ---------------------------------------------------------------- o estranho: osso
    if P.get('placas'):          # galhudo: duas placas chatas da testa, curvando para trás
        pl = P['placas']
        for sg in (1, -1):
            base = Vector((pl['base'][0], pl['base'][1] * sg, pl['base'][2]))
            pts, p_ = [], base.copy()
            n = 5 if JOGO_Q else 10
            for k in range(n + 1):
                tt = k / n
                pts.append(p_.copy())
                ang = pl['ang'][0] + (pl['ang'][1] - pl['ang'][0]) * tt ** 1.15
                p_ = p_ + Vector((-math.sin(ang), sg * pl['abre'] * (1 - tt), math.cos(ang))).normalized() * (pl['comp'] / n)
            pts[0] = pts[0] - (pts[1] - pts[0]).normalized() * 0.012          # a raiz entra um pouco na testa
            larg = [pl['larg'][0] + (pl['larg'][1] - pl['larg'][0]) * (k / n) ** 0.8 for k in range(n + 1)]
            esp = [pl['esp'][0] + (pl['esp'][1] - pl['esp'][0]) * k / n for k in range(n + 1)]
            m.parte = P_OSSO
            lamina(m, pts, larg, esp, Vector((0, sg, 0)), {'cabeca': 1.0}, I_OSSO)
            m.parte = 0
    if P.get('chifres'):         # corcova: chifres curtos e curvos de osso
        ch_ = P['chifres']
        for sg in (1, -1):
            b0 = Vector((ch_['base'][0], ch_['base'][1] * sg, ch_['base'][2]))
            pts = [b0 + Vector((d[0], d[1] * sg, d[2])) for d in ch_['pts']]
            pts.insert(0, b0 - Vector((0, 0.03 * sg, 0)))
            r = ch_['raio']
            m.parte = P_OSSO
            chifre(m, pts, [r * 1.05, r, r * 0.8, r * 0.55, r * 0.15], {'cabeca': 1.0}, I_OSSO, lados=6 if JOGO_Q else 10)
            m.parte = 0
    if P.get('nodulos'):         # nódulos ósseos na nuca (galhudo) ou na corcova (corcova)
        nd = P['nodulos']
        s0 = s_acc[-1] * nd['de'] if not nd.get('corcova') else None
        for k in range(nd['n']):
            tt = k / max(1, nd['n'] - 1)
            if nd.get('corcova'):
                xk = -0.08 + 0.50 * tt           # só no alto da corcova (na frente íngreme da capa pareciam soltos)
                s = _proj_s(cs, s_acc, Vector((xk, 0, 0.84)))
            else:
                s = juntas[1][0] + (juntas[3][0] - juntas[1][0]) * (nd['de'] + (nd['ate'] - nd['de']) * tt)
            tam = nd['tam'][0] + (nd['tam'][1] - nd['tam'][0]) * (tt if not nd.get('corcova') else abs(tt - 0.4) / 0.6)
            p, nrm, pw, t, cima = ponto_tubo(s, PI / 2)
            m.parte = P_NODULO
            nodulo(m, p - nrm * tam * 0.35, nrm, t, tam, pw)
            m.parte = 0
    if P.get('crista'):          # uivador: crista curta de placas ósseas da testa à nuca
        cr = P['crista']
        for k in range(cr['n']):
            tt = k / (cr['n'] - 1)
            xk = cr['ate'] - (cr['ate'] - cr['de']) * tt
            s = _proj_s(cs, s_acc, Vector((xk, 0, 0.75)))
            p, nrm, pw, t, cima = ponto_tubo(s, PI / 2)
            alt = cr['alt'][0] + (cr['alt'][1] - cr['alt'][0]) * math.sin(PI * (0.25 + 0.6 * tt))
            m.parte = P_NODULO
            aleta(m, p - nrm * 0.004, nrm, t, alt, 0.034, 0.0035, pw)
            m.parte = 0
    if P.get('barba'):           # corcova: barba de pelo sob o queixo
        s = (s_canto + s_acc[-1]) / 2
        p, nrm, pw, t, cima = ponto_tubo(s, -PI / 2)
        m.parte = P_MANDIBULA
        aleta(m, p - nrm * 0.02, nrm, t, 0.10, 0.12, 0.022, {'mandibula': 1.0}, I_PELO, zona=(0, 0, 1))
        m.parte = 0
    if P.get('dentes'):          # caninos (aparecem quando a boca abre)
        i_c = len(aneis) - 2
        mx_, md_ = aneis[i_c][1], aneis[i_c][2]
        for vs, pw, sinal in ((mx_, {'cabeca': 1.0}, -1), (md_, {'mandibula': 1.0}, 1)):
            for v_ in (vs[0], vs[-1]):
                base = v_.co.copy()
                lado_in = Vector((0, -math.copysign(1, base.y), 0))
                p0 = base + lado_in * 0.006
                dirz = (cima_de(cs, i_c) * sinal)
                h = 0.016 if sinal < 0 else 0.011
                b1 = m.v(p0 + X * 0.004, pw)
                b2 = m.v(p0 - X * 0.004, pw)
                b3 = m.v(p0 + lado_in * 0.006, pw)
                tp = m.v(p0 + lado_in * 0.002 + dirz * h, pw)
                for tri in ((b1, b2, tp), (b2, b3, tp), (b3, b1, tp), (b1, b3, b2)):
                    m.f(tri, I_DENTE, P_DENTE)

    bmesh.ops.recalc_face_normals(m.bm, faces=m.bm.faces[:])
    me = bpy.data.meshes.new(nome + '_malha')
    pesos = [m.pesos.get(v, {'corpo': 1.0}) for v in m.bm.verts]
    zonas = [m.zona.get(v, (0, 0, 0)) for v in m.bm.verts]
    m.bm.to_mesh(me)
    m.bm.free()
    for mt in MAT[especie]:
        me.materials.append(mt)
    at = me.color_attributes.new('zona', 'FLOAT_COLOR', 'POINT')
    for i, z_ in enumerate(zonas):
        at.data[i].color = (z_[0], z_[1], z_[2], 1.0)
    o = bpy.data.objects.new(nome + '_corpo', me)
    sc.collection.objects.link(o)
    grupos = {}
    for i, pw in enumerate(pesos):
        for n_, w in pw.items():
            if w <= 0.0:
                continue
            if n_ not in grupos:
                grupos[n_] = o.vertex_groups.new(name=n_)
            grupos[n_].add([i], w, 'REPLACE')
    o.parent = arm
    md = o.modifiers.new('esqueleto', 'ARMATURE')
    md.object = arm
    arm['especie'] = especie
    # vértices de cada parte (para medir o chão e as interseções) e solas (para o pé não raspar no balanço)
    pa = me.attributes['parte'].data
    vp = {}
    for pl_, poly in enumerate(me.polygons):
        vp.setdefault(pa[pl_].value, set()).update(poly.vertices)
    VPARTE[nome] = {k: sorted(v) for k, v in vp.items()}
    SOLAS[nome] = solas
    return arm


VPARTE, SOLAS = {}, {}


def _dist_seg(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
    return (a + ab * t - p).length


def pesos_perna(p, segs):
    """Pesos de um vértice da perna pela distância aos ossos (os dois mais perto, 1/d⁴): as massas de músculo longe do
    osso (jarrete, garupa, olécrano) ficam entre os dois ossos e esticam como pele."""
    ds = sorted((_dist_seg(p, a, b), n) for n, a, b in segs)
    (d1, n1), (d2, n2) = ds[0], ds[1]
    w1, w2 = 1.0 / (d1 + 0.004) ** 4, 1.0 / (d2 + 0.004) ** 4
    return {n1: w1 / (w1 + w2), n2: w2 / (w1 + w2)}


def cima_de(cs, i):
    t = (cs[min(i + 1, len(cs) - 1)] - cs[max(i - 1, 0)]).normalized()
    return t.cross(Y)


def casco(m, P, F, T, sg, pesos):
    """Casco de 2 dedos (unhas): cada unha é uma cunha com a sola chata em z = 0 e a ponta em x = T.x (o ponto onde o
    pé gira ao sair do chão); a parede da frente inclina para trás até a coroa. Devolve os pontos da sola."""
    comp, larg, alt, fenda = P['casco_dim']
    sola = []
    for lc in (1, -1):                                   # 1 = unha de fora, −1 = de dentro
        yc = T.y + sg * lc * (fenda / 2 + larg / 2)
        y_in = yc - sg * lc * larg / 2
        y_out = yc + sg * lc * larg / 2
        x1, x0 = T.x, T.x - comp
        fundo = [(x0, y_out), (x0 + 0.05 * comp, y_in), (x1 - 0.22 * comp, y_in), (x1, y_in + (y_out - y_in) * 0.2),
                 (x1 - 0.30 * comp, y_out)]
        vb = [m.v(Vector((x, y, 0.0)), pesos) for x, y in fundo]
        topo = []
        for x, y in fundo:
            xt = x0 + 0.04 * comp + (x - x0) * 0.42
            yt = yc + (y - yc) * 0.82
            zt = alt * (1.0 - 0.18 * (x - x0) / comp)
            topo.append(m.v(Vector((xt, yt, zt)), pesos))
        n = len(vb)
        for k in range(n):
            j = (k + 1) % n
            m.f((vb[k], vb[j], topo[j], topo[k]), I_CASCO)
        m.f(vb[::-1], I_CASCO)
        m.f(topo, I_CASCO)
        sola += [Vector((x, y, 0.0)) for x, y in fundo]
    return sola


def pata(m, P, F, T, sg, pesos, frente):
    """Pata de digitígrado: almofada em cúpula com o fundo chato em z = 0; as 4 garras na frente terminam em x = T.x,
    z = 0 (o ponto onde a pata gira ao sair do chão). Devolve os pontos da sola."""
    comp, larg, alt = P['pata_f' if frente else 'pata_t']
    garra = comp * 0.13
    a = (comp - garra) / 2
    b = larg / 2
    cx = T.x - garra - a
    N = 8 if JOGO_Q else 14
    fundo, meio = [], []
    for i in range(N):
        an = 2 * PI * i / N
        ca, sa = math.cos(an), math.sin(an)
        dedo = 1.0 + 0.06 * max(0.0, ca) * math.cos(4 * an) if not JOGO_Q else 1.0
        fundo.append(m.v(Vector((cx + a * ca * dedo, T.y + b * sa, 0.0)), pesos))
        meio.append(m.v(Vector((cx - 0.08 * a + a * 0.9 * ca, T.y + b * 0.88 * sa, alt * 0.55)), pesos, (0.0, 0.0, 0.0)))
    for i in range(N):
        j = (i + 1) % N
        m.f((fundo[i], fundo[j], meio[j], meio[i]), I_PELO)
    m.f(fundo[::-1], I_FOCINHO)
    m.ngon_ou_leque(meio, I_PELO, centro=Vector((cx - 0.25 * a, T.y, alt)))
    sola = [Vector((v.co.x, v.co.y, 0.0)) for v in fundo]
    for k in range(4):
        yk = T.y + b * (-0.66 + 0.44 * k)
        tip = m.v(Vector((T.x, yk, 0.0)), pesos)
        xb = cx + a * 0.80
        b1 = m.v(Vector((xb, yk - 0.0035, 0.007)), pesos)
        b2 = m.v(Vector((xb, yk + 0.0035, 0.007)), pesos)
        b3 = m.v(Vector((xb, yk, 0.015)), pesos)
        for tri in ((b1, b2, tip), (b2, b3, tip), (b3, b1, tip)):
            m.f(tri, I_CASCO)
        sola.append(Vector((T.x, yk, 0.0)))
    return sola


def orelha(m, base, eixo, abre, comp, larg, conc, pesos, zona, sg, perfil=None):
    """Orelha com espessura: borda em folha (ou arredondada), a face de dentro côncava (abre para `abre`) e a de fora
    abaulada, unidas na borda; a base entra 3 mm na cabeça."""
    e1 = eixo.normalized()
    e3 = (abre - e1 * abre.dot(e1)).normalized()
    e2 = e1.cross(e3)
    perfil = perfil or ((0.0, 0.55), (0.22, 0.92), (0.5, 1.0), (0.78, 0.72), (1.0, 0.0))
    b = base - e1 * 0.003
    borda = [b + e1 * comp * t + e2 * larg / 2 * w for t, w in perfil] + \
            [b + e1 * comp * t - e2 * larg / 2 * w for t, w in perfil[-2::-1]]
    vb = [m.v(p, pesos, zona(dict(reg='orelha', dentro=0.5, sa=0, x=p.x, z=p.z))) for p in borda]
    fc = m.v(b + e1 * comp * 0.42 - e3 * conc, pesos, zona(dict(reg='orelha', dentro=1.0, sa=0, x=0, z=0)))
    bc = m.v(b + e1 * comp * 0.42 - e3 * (conc + 0.009), pesos, zona(dict(reg='orelha', dentro=0.0, sa=0, x=0, z=0)))
    n = len(vb)
    for i in range(n):
        j = (i + 1) % n
        m.f((vb[i], vb[j], fc), I_PELO)
        m.f((vb[j], vb[i], bc), I_PELO)


def lamina(m, pts, larg, esp, lado, pesos, mat):
    """Placa chata varrida ao longo de pts: seção hexagonal larga no plano do caminho e fina para o lado (`lado`)."""
    perfil = ((1.0, 0.0), (0.55, 1.0), (-0.55, 1.0), (-1.0, 0.0), (-0.55, -1.0), (0.55, -1.0))
    aneis = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        lv = (lado - d * d.dot(lado)).normalized()
        nw = d.cross(lv)
        aneis.append([m.v(p + nw * (larg[i] / 2 * a) + lv * (esp[i] / 2 * b), pesos) for a, b in perfil])
    for a, b in zip(aneis, aneis[1:]):
        for k in range(6):
            j = (k + 1) % 6
            m.f((a[k], a[j], b[j], b[k]), mat)
    m.f(aneis[0][::-1], mat)
    m.ngon_ou_leque(aneis[-1], mat, centro=pts[-1] + (pts[-1] - pts[-2]).normalized() * larg[-1] * 0.5)


def chifre(m, pts, raios, pesos, mat, lados=6):
    aneis = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        u = d.cross(Z)
        if u.length < 1e-3:
            u = d.cross(X)
        u.normalize()
        w = d.cross(u)
        aneis.append([m.v(p + (u * math.cos(2 * PI * k / lados) + w * math.sin(2 * PI * k / lados)) * raios[i], pesos)
                      for k in range(lados)])
    for a, b in zip(aneis, aneis[1:]):
        for k in range(lados):
            j = (k + 1) % lados
            m.f((a[k], a[j], b[j], b[k]), mat)
    m.f(aneis[0][::-1], mat)
    m.ngon_ou_leque(aneis[-1], mat, centro=pts[-1] + (pts[-1] - pts[-2]).normalized() * raios[-1] * 2)


def nodulo(m, p, nrm, t, tam, pesos):
    """Nódulo ósseo: pirâmide baixa de 4 lados com a base dentro da pele."""
    u = t.normalized()
    w = nrm.cross(u).normalized()
    base = [m.v(p + (u * math.cos(a) + w * math.sin(a)) * tam, pesos) for a in (0, PI / 2, PI, 3 * PI / 2)]
    tp = m.v(p + nrm * tam * 1.15 - u * tam * 0.25, pesos)
    for k in range(4):
        m.f((base[k], base[(k + 1) % 4], tp), I_OSSO)
    m.f(base[::-1], I_OSSO)


def aleta(m, p, nrm, t, alt, comp, esp, pesos, mat=I_OSSO, zona=(0, 0, 0)):
    """Placa fina (crista óssea) ou barba: base ao longo de t, ponta para trás e para fora (nrm)."""
    u = t.normalized()
    w = nrm.cross(u).normalized()
    pts = [p + u * comp * 0.5, p - u * comp * 0.5, p - u * comp * 0.55 + nrm * alt]
    vs = [[m.v(q + w * esp / 2 * s, pesos, zona) for q in pts] for s in (1, -1)]
    a, b = vs
    m.f((a[0], a[1], a[2]), mat)
    m.f((b[0], b[2], b[1]), mat)
    for i in range(3):
        j = (i + 1) % 3
        m.f((a[j], a[i], b[i], b[j]), mat)


# ------------------------------------------------------------------ esqueleto: pose por matrizes (FK da coluna + IK das pernas)
class Rig:
    def __init__(self, arm):
        self.arm = arm
        bones = arm.data.bones

        def prof(b):
            d = 0
            while b.parent:
                b, d = b.parent, d + 1
            return d
        self.ordem = [b.name for b in sorted(bones, key=prof)]
        self.R = {b.name: b.matrix_local.copy() for b in bones}
        self.Ri = {n: M.inverted() for n, M in self.R.items()}
        self.pai = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.L = {b.name: b.length for b in bones}
        self.cab = {b.name: b.head_local.copy() for b in bones}
        self.pon = {b.name: b.tail_local.copy() for b in bones}
        self.polo = {}
        for lado in 'ed':
            for frente in (True, False):
                a, b, c, d = (f'{n}_{lado}' for n in NOMES_PERNA[frente])
                H, J, K = self.cab[a], self.cab[b], self.cab[c]
                dk = (K - H).normalized()
                p = (J - H) - dk * (J - H).dot(dk)
                self.polo[(lado, frente)] = p.normalized()
        self.zerar()

    def zerar(self):
        self.B = {n: Matrix.Identity(4) for n in self.ordem}
        self.P = {}
        self.desl = Vector()
        self.rraiz = Matrix.Identity(3)
        self.pivo = self.cab['corpo'].copy()

    def gira(self, n, pitch=0.0, yaw=0.0, rola=0.0):
        """Gira o osso em volta dos eixos do bicho (pitch: lado; + = a ponta de um osso que vai para a frente desce)."""
        inv = self.Ri[n].to_3x3()
        q = Quaternion(inv @ Z, yaw) @ Quaternion(inv @ Y, pitch) @ Quaternion(inv @ X, rola)
        self.B[n] = self.B[n] @ q.to_matrix().to_4x4()

    def gira_local(self, n, eixo, ang):
        self.B[n] = self.B[n] @ Matrix.Rotation(ang, 4, eixo)

    def raiz(self, desl=(0, 0, 0), pitch=0.0, yaw=0.0, rola=0.0, pivo=None):
        self.desl = Vector(desl)
        self.rraiz = (Quaternion(Z, yaw) @ Quaternion(Y, pitch) @ Quaternion(X, rola)).to_matrix()
        self.pivo = Vector(pivo) if pivo is not None else self.cab['corpo'].copy()

    def fk(self):
        self.P = {}
        for n in self.ordem:
            p = self.pai[n]
            if p is None:
                pv = self.pivo
                M = Matrix.Translation(pv + self.desl) @ self.rraiz.to_4x4() @ Matrix.Translation(-pv) @ self.R[n] @ self.B[n]
            else:
                M = self.P[p] @ self.Ri[p] @ self.R[n] @ self.B[n]
            self.P[n] = M

    def fk_de(self, raiz):
        """Refaz a FK só dos descendentes de `raiz` (depois de mexer no B dele)."""
        for n in self.ordem:
            k, dentro = n, False
            while k is not None:
                if k == raiz:
                    dentro = True
                    break
                k = self.pai[k]
            if dentro:
                p = self.pai[n]
                self.P[n] = self.P[p] @ self.Ri[p] @ self.R[n] @ self.B[n]

    def base(self, n):
        p = self.pai[n]
        if p is None:
            return self.Ri[n] @ self.P[n]
        return (self.P[p] @ self.Ri[p] @ self.R[n]).inverted() @ self.P[n]

    def aplicar(self):
        for n in self.ordem:
            pb = self.arm.pose.bones[n]
            pb.rotation_mode = 'QUATERNION'
            pb.matrix_basis = self.base(n)
            pb.scale = (1.0, 1.0, 1.0)

    def ponta(self, n):
        return self.P[n] @ Vector((0, self.L[n], 0))

    def cab_posada(self, n):
        p = self.pai[n]
        return (self.P[p] @ self.Ri[p] @ self.R[n]).translation.copy()

    def rot_corpo(self, n):
        return self.P[n].to_3x3() @ self.R[n].to_3x3().inverted()

    def segmento(self, n, A, B, Rb):
        dr = (self.pon[n] - self.cab[n]).normalized()
        q = dr.rotation_difference(Rb.transposed() @ (B - A).normalized())
        M = (Rb @ q.to_matrix() @ self.R[n].to_3x3()).to_4x4()
        M.translation = A
        return M

    def vd(self, lado, frente):
        d = f'{NOMES_PERNA[frente][3]}_{lado}'
        return self.pon[d] - self.cab[d]

    def theta_rest(self, lado, frente):
        c = f'{NOMES_PERNA[frente][2]}_{lado}'
        u = (self.pon[c] - self.cab[c]).normalized()
        return math.atan2(u.x, -u.z)

    def _theta(self, lado, frente, F, th0, rlim):
        a, b, c, d = (f'{n}_{lado}' for n in NOMES_PERNA[frente])
        H = self.cab_posada(a)
        la, lb, lc = self.L[a], self.L[b], self.L[c]

        def fora(th):
            K = F - Vector((math.sin(th), 0.0, -math.cos(th))) * lc
            r = (K - H).length / (la + lb)
            return max(0.0, rlim[0] - r, r - rlim[1])
        if fora(th0) == 0.0:
            return th0
        melhor = (fora(th0), th0)
        for k in range(1, 500):
            for sg in (1, -1):
                t2 = th0 + sg * k * 0.005
                f2 = fora(t2)
                if f2 < melhor[0]:
                    melhor = (f2, t2)
                if f2 == 0.0:
                    return t2
        return melhor[1]

    def perna(self, lado, frente, T=None, F=None, alfa=0.0, theta=None, flex=0.0, rlim=None, abre=0.0):
        """IK da perna. Apoio: T (ponta no chão) e alfa (giro do casco na ponta; + = calcanhar sobe). Balanço: F (boleto),
        theta (ângulo do pé/mão; + = ponta de baixo para a frente) e flex (dobra do casco além de acompanhar o pé).
        O ângulo do pé é ajustado só o necessário para a coxa+canela alcançarem (rlim = fração do comprimento)."""
        a, b, c, d = (f'{n}_{lado}' for n in NOMES_PERNA[frente])
        baseb = 'peito' if frente else 'corpo'
        Rb = self.rot_corpo(baseb)
        H = self.cab_posada(a)
        la, lb, lc = self.L[a], self.L[b], self.L[c]
        vd = self.vd(lado, frente)
        th_r = self.theta_rest(lado, frente)
        if rlim is None:
            rlim = (0.45, 0.985) if frente else (0.42, 0.965)
        apoio = T is not None
        if apoio:
            F = T - Matrix.Rotation(alfa, 3, 'Y') @ vd
        th = self._theta(lado, frente, F, th_r if theta is None else theta, rlim)
        K = F - Vector((math.sin(th), 0.0, -math.cos(th))) * lc
        polo = self.polo[(lado, frente)] + Y * ((1 if lado == 'e' else -1) * abre)
        J, K2 = ik2(H, K, la, lb, Rb @ polo.normalized())
        if not apoio:
            alfa = -(th - th_r) + flex
        self.P[a] = self.segmento(a, H, J, Rb)
        self.P[b] = self.segmento(b, J, K2, Rb)
        self.P[c] = self.segmento(c, K2, F, Rb)
        M = (Matrix.Rotation(alfa, 3, 'Y') @ self.R[d].to_3x3()).to_4x4()
        M.translation = self.ponta(c)
        self.P[d] = M
        return th, alfa

    def cadeia(self, lado, frente, pts, rot_dedo=None):
        """Perna por pontos dados (deitado): ombro/quadril → cotovelo/joelho → carpo/jarrete → boleto; o dedo com a
        rotação dada (mundo) ou a de repouso."""
        a, b, c, d = (f'{n}_{lado}' for n in NOMES_PERNA[frente])
        Rb = self.rot_corpo('peito' if frente else 'corpo')
        H = self.cab_posada(a)
        E, C, F = pts
        self.P[a] = self.segmento(a, H, E, Rb)
        self.P[b] = self.segmento(b, self.ponta(a), C, Rb)
        self.P[c] = self.segmento(c, self.ponta(b), F, Rb)
        M = ((rot_dedo or Matrix.Identity(3)) @ self.R[d].to_3x3()).to_4x4()
        M.translation = self.ponta(c)
        self.P[d] = M

    def sola(self, lado, frente):
        d = f'{NOMES_PERNA[frente][3]}_{lado}'
        M = self.P[d] @ self.Ri[d]
        return [M @ p for p in SOLAS[self.arm.name][CHAVE[(lado, frente)]]]


def ik2(H, K, a, b, polo):
    d = K - H
    L = max(abs(a - b) + 1e-5, min(a + b - 1e-5, d.length))
    dn = d.normalized()
    ca = (a * a + L * L - b * b) / (2 * a * L)
    sa = math.sqrt(max(0.0, 1.0 - ca * ca))
    p = polo - dn * polo.dot(dn)
    p.normalize()
    return H + dn * (a * ca) + p * (a * sa), H + dn * L


RIGS = {}


def rig_de(arm):
    r = RIGS.get(arm.name)
    if r is None or r.arm != arm:
        r = RIGS[arm.name] = Rig(arm)
    return r


def corpo_de(arm):
    return next(c for c in arm.children if c.type == 'MESH')


def _zmin(arm, partes=None):
    """Menor z (em relação à origem do bicho) da malha deformada; com `partes`, só os vértices dessas partes."""
    bpy.context.view_layer.update()
    o = corpo_de(arm)
    oe = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = oe.to_mesh()
    mw = arm.matrix_world.inverted() @ oe.matrix_world
    if partes is None:
        z = min((mw @ v.co).z for v in me.vertices)
    else:
        vp = VPARTE[arm.name]
        idx = [i for p in partes for i in vp.get(p, ())]
        z = min((mw @ me.vertices[i].co).z for i in idx) if idx else 0.0
    oe.to_mesh_clear()
    return z


def _zmin_osso(arm, ossos):
    """Menor z dos vértices em que um destes ossos é o de maior peso."""
    bpy.context.view_layer.update()
    o = corpo_de(arm)
    if arm.name not in VOSSO:
        gi = {g.index: g.name for g in o.vertex_groups}
        d = {}
        for v in o.data.vertices:
            if v.groups:
                d.setdefault(gi[max(v.groups, key=lambda g: g.weight).group], []).append(v.index)
        VOSSO[arm.name] = d
    oe = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = oe.to_mesh()
    mw = arm.matrix_world.inverted() @ oe.matrix_world
    idx = [i for n in ossos for i in VOSSO[arm.name].get(n, ())]
    z = min((mw @ me.vertices[i].co).z for i in idx) if idx else 0.0
    oe.to_mesh_clear()
    return z


VOSSO = {}


# ------------------------------------------------------------------ poses
def pose_zero(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)


def _postura(rig, pst, aceno=0.0):
    for n in ('pescoco1', 'pescoco2', 'cabeca'):
        if pst.get(n):
            rig.gira(n, pitch=pst[n])
    if aceno:
        rig.gira('pescoco1', pitch=aceno * 0.6)
        rig.gira('cabeca', pitch=-aceno * 0.3)


def _pata_ciclo(rig, lado, frente, u, g):
    """Uma perna no ciclo (u 0..1): apoio de 0 a duty (a ponta parada no chão desliza para trás), balanço no resto."""
    ch = CHAVE[(lado, frente)]
    duty = g['duty']
    L = g['ciclo'] * duty
    phi = (u - g['fases'][ch]) % 1.0
    dn = NOMES_PERNA[frente][3] + '_' + lado
    T0 = rig.pon[dn]
    dx = g.get('dx_f' if frente else 'dx_t', 0.0)
    x_td, x_lo = T0.x + dx + L / 2, T0.x + dx - L / 2
    alo = g['alfa_f' if frente else 'alfa_t']
    rlim = g.get('rlim_f' if frente else 'rlim_t')
    if rlim is None:
        rlim = (0.45, 0.995) if frente else (0.42, 0.97)
    if phi < duty:
        s = phi / duty
        T = Vector((x_td + (x_lo - x_td) * s, T0.y, 0.0))
        rig.perna(lado, frente, T=T, alfa=alo * suave((s - 0.72) / 0.28), rlim=rlim,
                  abre=g.get('abre_f' if frente else 'abre_t', 0.0))
        return True
    s = (phi - duty) / (1.0 - duty)
    vd = rig.vd(lado, frente)
    th_r = rig.theta_rest(lado, frente)
    F_lo = Vector((x_lo, T0.y, 0.0)) - Matrix.Rotation(alo, 3, 'Y') @ vd
    F_td = Vector((x_td, T0.y, 0.0)) - vd
    th_lo = rig._theta(lado, frente, F_lo, th_r, rlim)
    th_td = rig._theta(lado, frente, F_td, th_r, rlim)
    e = suave(s)
    sob = math.sin(PI * s) ** 0.8
    F = F_lo.lerp(F_td, e) + Z * (g['h_f' if frente else 'h_t'] * sob)
    dob = math.sin(PI * min(1.0, s / 0.8)) * (1.0 - 0.25 * s)      # dobra cedo; nos últimos 20% a perna já estica
    th = th_lo + (th_td - th_lo) * e + g['dobra_f' if frente else 'dobra_t'] * dob
    fx0 = alo + th_lo - th_r
    fx1 = th_td - th_r
    flex = fx0 + (fx1 - fx0) * e + g['flex_f' if frente else 'flex_t'] * dob
    for _ in range(3):                              # o casco não raspa o chão no balanço
        rig.perna(lado, frente, F=F, theta=th, flex=flex, rlim=rlim, abre=g.get('abre_f' if frente else 'abre_t', 0.0))
        zmin = min(p.z for p in rig.sola(lado, frente))
        if zmin >= 0.004 * sob - 1e-5:
            break
        F = F + Z * (0.004 * sob - zmin)
    return False


def _x_rel(lado, frente, u, g):
    """Posição do pé no ciclo, de +1 (pousando, à frente) a −1 (saindo, atrás)."""
    duty = g['duty']
    phi = (u - g['fases'][CHAVE[(lado, frente)]]) % 1.0
    if phi < duty:
        return 1.0 - 2.0 * phi / duty
    return -1.0 + 2.0 * suave((phi - duty) / (1.0 - duty))


def _locomover(arm, u, g, pst):
    rig = rig_de(arm)
    P = ESPECIES[arm['especie']]
    rig.zerar()
    w = 2 * PI * u
    if g['tipo'] == 'passo':
        dz = g.get('bob', 0.0) * math.cos(2 * w)          # mais baixo quando a mão pousa (apoio duplo)
        pitch = 0.0
        rola = g.get('rola', 0.0) * math.sin(w)
        aceno = g.get('aceno', 0.0) * math.sin(2 * w - 0.6)
    else:
        dz = g.get('bob', 0.0) * math.cos(2 * PI * (u - g['susp']))
        pitch = g.get('arfa', 0.0) * math.sin(2 * PI * (u - g.get('arfa_fase', 0.0)))
        rola = 0.0
        aceno = g.get('aceno', 0.0) * math.sin(2 * PI * (u - g.get('arfa_fase', 0.0)))
    meio = (rig.cab['corpo'] + rig.pon['peito']) / 2
    rig.raiz(desl=(0.0, 0.0, dz + g.get('dz', 0.0)), pitch=pitch + pst.get('pitch', 0.0), rola=rola, pivo=meio)
    if g.get('flexao'):
        fl = g['flexao'] * max(0.0, math.cos(2 * PI * (u - g.get('flexao_fase', 0.0))))   # só arqueia (reunido)
        rig.gira('peito', pitch=fl)
        rig.gira('pescoco1', pitch=-fl * 0.6)
    _postura(rig, pst, aceno)
    rig.gira('cauda1', pitch=pst.get('cauda', 0.0) - (0.15 if g['tipo'] == 'galope' else 0.0),
             yaw=0.10 * math.sin(w))
    if 'cauda2' in rig.B:
        rig.gira('cauda2', yaw=0.10 * math.sin(w - 0.8))
    for lado in 'ed':
        sg = 1 if lado == 'e' else -1
        rig.gira(f'escapula_{lado}', pitch=g.get('escapula', 0.20) * max(0.0, -_x_rel(lado, True, u, g)))
        rig.gira(f'orelha_{lado}', pitch=0.03 * math.sin(2 * w + sg))
    rig.fk()
    apoio = {}
    for lado, frente in PERNAS:
        apoio[CHAVE[(lado, frente)]] = _pata_ciclo(rig, lado, frente, u, g)
    rig.aplicar()
    return apoio


def pose_parado(arm, u=0.0):
    rig = rig_de(arm)
    rig.zerar()
    rig.fk()
    for lado, frente in PERNAS:
        rig.perna(lado, frente, T=rig.pon[f'{NOMES_PERNA[frente][3]}_{lado}'].copy())
    rig.aplicar()


def pose_andar(arm, u):
    P = ESPECIES[arm['especie']]
    return _locomover(arm, u, P['andar'], P['postura'].get('andar', {}))


def pose_correr(arm, u):
    P = ESPECIES[arm['especie']]
    return _locomover(arm, u, P['correr'], P['postura'].get('correr', {}))


def pose_espreitar(arm, u):
    P = ESPECIES[arm['especie']]
    return _locomover(arm, u, P['espreitar'], P['postura'].get('espreitar', {}))


def _pes_fixos(rig, desl=None, rlim=None):
    for lado, frente in PERNAS:
        T = rig.pon[f'{NOMES_PERNA[frente][3]}_{lado}'].copy()
        if desl:
            T = T + Vector(desl.get(CHAVE[(lado, frente)], (0, 0, 0)))
        rig.perna(lado, frente, T=T, rlim=rlim)


def _orelhas(rig, ang_e, ang_d, pitch=0.0):
    rig.gira('orelha_e', pitch=pitch)
    rig.gira('orelha_d', pitch=pitch)
    rig.gira_local('orelha_e', 'Y', ang_e)
    rig.gira_local('orelha_d', 'Y', -ang_d)


def pose_pastar(arm, u):
    """Pastando (herbívoro): pescoço para baixo e para a frente, o focinho no capim (a 5 mm do chão — o ângulo do
    pescoço é procurado uma vez para isso), mastigando (a mandíbula mexe de lado e abre um pouco); a cabeça sobe e desce
    pouco (só para cima, nunca entra no chão); as pernas da frente um pouco abertas, os cascos parados."""
    P = ESPECIES[arm['especie']]
    rig = rig_de(arm)
    q = P.get('pastar', {})
    mast = math.sin(2 * PI * u * 3)
    sobe = 0.5 - 0.5 * math.cos(2 * PI * u)

    def montar_pose(p1, u_):
        rig.zerar()
        pt, pe, p2 = q.get('pitch', 0.05), q.get('peito', 0.05), q.get('pescoco2', 0.35)
        rig.raiz(desl=(0.0, 0.0, q.get('dz', -0.01)), pitch=pt, pivo=rig.cab['corpo'])
        rig.gira('peito', pitch=pe)
        rig.gira('pescoco1', pitch=p1 - 0.05 * u_)
        rig.gira('pescoco2', pitch=p2)
        # a cara fica num ângulo fixo em relação ao chão (focinho no capim): a cabeça desfaz o giro do pescoço
        rig.gira('cabeca', pitch=q.get('cara', 1.1) - (pt + pe + p1 + p2) - 0.03 * u_, yaw=0.06 * math.sin(2 * PI * u))
        rig.gira('mandibula', pitch=-0.06 * max(0.0, mast), yaw=0.05 * mast)
        _orelhas(rig, 0.25 + 0.1 * math.sin(2 * PI * u), 0.25, pitch=q.get('orelha', 0.1))
        rig.gira('cauda1', yaw=0.15 * math.sin(2 * PI * u * 2))
        rig.fk()
        _pes_fixos(rig, q.get('pes', {'fe': (0.06, 0.01, 0), 'fd': (-0.03, -0.01, 0)}))
        rig.aplicar()
    if 'pastar_p' not in arm:
        lo, hi = q.get('faixa', (0.6, 2.2))
        for _ in range(18):
            mid = (lo + hi) / 2
            montar_pose(mid, 0.0)
            if min(_zmin(arm, (P_CABECA, P_MANDIBULA)) - 0.005, _zmin(arm, (P_OSSO, P_ORELHA)) - 0.003) > 0.0:
                lo = mid
            else:
                hi = mid
        arm['pastar_p'] = lo
    montar_pose(arm['pastar_p'], sobe)


def pose_alerta(arm, u):
    """Alerta (herbívoro): pescoço erguido, cabeça alta olhando para um lado e depois para o outro, as orelhas virando
    (uma para trás, depois a outra), o rabo levantado; os cascos parados."""
    P = ESPECIES[arm['especie']]
    rig = rig_de(arm)
    q = P.get('alerta', {})
    rig.zerar()
    rig.fk()
    olha = 0.35 * math.sin(2 * PI * u)
    rig.zerar()
    rig.raiz(desl=(0.0, 0.0, 0.0), pitch=q.get('pitch', -0.02), pivo=rig.cab['corpo'])
    rig.gira('pescoco1', pitch=q.get('pescoco1', -0.18), yaw=olha * 0.3)
    rig.gira('pescoco2', pitch=q.get('pescoco2', -0.06), yaw=olha * 0.3)
    rig.gira('cabeca', pitch=q.get('cabeca', 0.10), yaw=olha * 0.4)
    fe = 0.9 * suave((math.sin(2 * PI * u) + 0.2) / 0.6)
    fd = 0.9 * suave((-math.sin(2 * PI * u) + 0.2) / 0.6)
    _orelhas(rig, -0.2 + fe, -0.2 + fd, pitch=-0.08)
    rig.gira('cauda1', pitch=q.get('cauda', -0.6))
    rig.fk()
    _pes_fixos(rig)
    rig.aplicar()


def pose_morder(arm, u):
    """Bote/mordida (predador): encolhe (0–0,3), dá o bote para a frente com a boca aberta (0,3–0,55), fecha a boca de
    golpe (0,55) e volta (0,6–1); as patas não saem do chão — o corpo é que vai e volta. Serve para atacar e brigar."""
    rig = rig_de(arm)
    P = ESPECIES[arm['especie']]
    e = suave(u / 0.3) * (1 - suave((u - 0.3) / 0.15))           # encolhe
    b = suave((u - 0.3) / 0.22) * (1 - suave((u - 0.6) / 0.4))   # bote
    boca = suave((u - 0.28) / 0.14) * (1 - suave((u - 0.52) / 0.06))
    alc = P.get('morder', {}).get('alcance', 0.11)
    rig.zerar()
    rig.raiz(desl=(-0.03 * e + alc * b, 0.0, -0.035 * e - 0.015 * b), pitch=0.05 * e + 0.06 * b, pivo=rig.cab['corpo'])
    rig.gira('peito', pitch=0.04 * e - 0.02 * b)
    rig.gira('pescoco1', pitch=-0.25 * e + 0.32 * b)
    rig.gira('pescoco2', pitch=-0.1 * e + 0.1 * b)
    rig.gira('cabeca', pitch=0.2 * e - 0.28 * b)
    rig.gira('mandibula', pitch=0.75 * boca)
    _orelhas(rig, -0.5 * (e + b), -0.5 * (e + b), pitch=0.25 * (e + b))
    rig.gira('cauda1', pitch=-0.25 * b)
    rig.fk()
    _pes_fixos(rig)
    rig.aplicar()


def pose_comer(arm, u):
    """Comendo carne (predador): cabeça baixa na carcaça (no chão à frente), morde e puxa para trás torcendo a cabeça,
    duas puxadas por laço; as patas da frente firmes, o corpo recua um pouco a cada puxão."""
    rig = rig_de(arm)
    P = ESPECIES[arm['especie']]
    q = P.get('comer', {})
    pu = max(0.0, math.sin(2 * PI * u * 2)) ** 1.5
    rig.zerar()
    rig.raiz(desl=(-0.025 * pu, 0.0, -0.04 + 0.01 * pu), pitch=0.10 - 0.04 * pu, pivo=rig.cab['corpo'])
    rig.gira('peito', pitch=0.05)
    rig.gira('pescoco1', pitch=q.get('pescoco1', 0.95) - 0.25 * pu)
    rig.gira('pescoco2', pitch=q.get('pescoco2', 0.25))
    rig.gira('cabeca', pitch=q.get('cabeca', 0.45) - 0.15 * pu, rola=0.25 * pu * (1 if (u * 2) % 1 < 0.5 else -1))
    rig.gira('mandibula', pitch=0.32 * (1 - pu) * (0.5 + 0.5 * math.cos(2 * PI * u * 4)))
    _orelhas(rig, -0.3, -0.3, pitch=0.15)
    rig.gira('cauda1', pitch=0.1)
    rig.fk()
    _pes_fixos(rig, {'fe': (0.05, 0.012, 0), 'fd': (0.02, -0.012, 0)})
    rig.aplicar()


def pose_deitado(arm, u=0.0):
    """Deitado de barriga (predador, no covil): a barriga no chão, as pernas da frente esticadas para a frente com os
    cotovelos e antebraços no chão, as de trás dobradas ao lado da barriga (jarrete e pé no chão), cabeça erguida,
    respirando devagar (o peito sobe e desce; nada sai do chão)."""
    rig = rig_de(arm)
    P = ESPECIES[arm['especie']]
    q = P['deitado']
    resp = math.sin(2 * PI * u)
    cache = arm.get('deitado_z')

    def montar_pose(z_raiz, pts_pernas=None, cauda=0.0):
        rig.zerar()
        rig.raiz(desl=(0.0, 0.0, z_raiz), pitch=-0.02, pivo=rig.cab['corpo'])
        rig.gira('peito', pitch=-0.012 * resp)
        rig.gira('pescoco1', pitch=q['pescoco1'])
        rig.gira('pescoco2', pitch=q['pescoco2'])
        rig.gira('cabeca', pitch=q['cabeca'] + 0.01 * resp, yaw=0.08 * math.sin(2 * PI * u))
        _orelhas(rig, 0.05, 0.05)
        rig.gira('cauda1', pitch=-cauda, yaw=0.55)
        if 'cauda2' in rig.B:
            rig.gira('cauda2', yaw=0.45)
        if 'cauda3' in rig.B:
            rig.gira('cauda3', yaw=0.35)
        for lado in 'ed':
            rig.gira(f'escapula_{lado}', pitch=-0.25)
        rig.fk()
        if pts_pernas:
            for (lado, frente), pts in pts_pernas.items():
                rig.cadeia(lado, frente, pts)
        rig.aplicar()

    # 1) o tronco encosta no chão
    z = -0.3 if cache is None else cache
    for _ in range(4):
        montar_pose(z)
        z -= _zmin(arm, (P_TRONCO,))
    arm['deitado_z'] = z
    # 2) pernas no chão: da frente esticadas (cotovelo, antebraço, mão e pata no chão), de trás dobradas
    pts = {}
    corr = arm.get('deitado_corr') or {}
    for lado, frente in PERNAS:
        sg = 1 if lado == 'e' else -1
        a, b, c, d = (f'{n}_{lado}' for n in NOMES_PERNA[frente])
        la, lb, lc = rig.L[a], rig.L[b], rig.L[c]
        H = rig.cab_posada(a)
        vd = rig.vd(lado, frente)
        ch = CHAVE[(lado, frente)]
        dz = corr.get(ch, 0.0)
        if frente:
            r_cot = q.get('r_cot', 0.03) + dz
            dzh = H.z - r_cot
            E = Vector((H.x - math.sqrt(max(1e-6, la * la - dzh * dzh)), H.y + sg * q['abre_f'], r_cot))
            r_car = q.get('r_car', 0.018) + dz
            C = E + Vector((math.sqrt(max(1e-6, lb * lb - (E.z - r_car) ** 2)), 0.0, r_car - E.z))
            Fz = -vd.z
            F = C + Vector((math.sqrt(max(1e-6, lc * lc - (Fz - C.z) ** 2)), 0.0, Fz - C.z))
            pts[(lado, frente)] = (E, C, F)
        else:
            r_jar = q.get('r_jar', 0.02) + dz
            K = Vector((H.x + q['jarrete'], H.y + sg * q['abre_t'], r_jar))
            Fz = -vd.z
            F = K + Vector((math.sqrt(max(1e-6, lc * lc - (Fz - K.z) ** 2)), 0.0, Fz - K.z))
            polo = Vector((1.0, 0.55 * sg, 0.35)).normalized()
            J, K2 = ik2(H, K, la, lb, polo)
            pts[(lado, frente)] = (J, K2, F + (K2 - K))
    cauda = arm.get('deitado_cauda', 0.4)
    montar_pose(z, pts, cauda)
    if 'deitado_corr' in arm and 'deitado_cauda' in arm:
        for lado, frente in PERNAS:          # a respiração mexe o ombro: cada perna volta a encostar
            zl = _zmin_osso(arm, (f'antebraco_{lado}',) if frente else (f'pe_{lado}',))
            E, C, F = pts[(lado, frente)]
            pts[(lado, frente)] = (E - Z * zl if frente else E, C - Z * zl, F)
        montar_pose(z, pts, cauda)
        zt = min(0.0, _zmin(arm))
        if zt < 0.0:                         # algo (de décimos de milímetro) passou do chão: sobe tudo junto
            pts = {k: tuple(p_ - Z * zt for p_ in v) for k, v in pts.items()}
            montar_pose(z - zt, pts, cauda)
    if 'deitado_corr' not in arm:        # acerta uma vez: cada perna encosta (nem enterrada nem no ar)
        corr = {}
        for lado, frente in PERNAS:
            ch = CHAVE[(lado, frente)]
            corr[ch] = -_zmin_osso(arm, (f'antebraco_{lado}',) if frente else (f'pe_{lado}',))
        arm['deitado_corr'] = corr
        return pose_deitado(arm, u)
    if 'deitado_cauda' not in arm:       # a cauda deitada no chão
        lo, hi = -0.6, 1.6
        for _ in range(16):
            mid = (lo + hi) / 2
            montar_pose(z, pts, mid)
            if _zmin(arm, (P_CAUDA,)) > 0.0:
                lo = mid
            else:
                hi = mid
        arm['deitado_cauda'] = lo
        montar_pose(z, pts, lo)


def pose_morto(arm, u=0.0):
    """Morto: deitado sobre o lado direito, as pernas meio esticadas e duras (as de cima um pouco para a frente e para
    trás das de baixo, para não se cruzarem), o pescoço estendido com a cabeça no chão, as orelhas para trás, a cauda
    solta. Cada perna, a cabeça e a cauda são baixadas (busca) até encostar no chão — nada no ar, nada enterrado."""
    rig = rig_de(arm)
    P = ESPECIES[arm['especie']]
    prm = dict(arm['morto_prm']) if 'morto_prm' in arm else dict(z=0.0, fe=0.1, fd=0.1, te=0.1, td=0.1, pesc=0.3, cauda=0.3)
    abre = {'fe': (-0.6, 0.0), 'fd': (-0.25, 0.0), 'te': (0.75, 0.0), 'td': (0.25, 0.0)}

    def montar_pose(p):
        rig.zerar()
        rig.raiz(desl=(0.0, 0.0, p['z']), rola=PI / 2 * 0.97, pivo=(rig.cab['corpo'] + rig.pon['peito']) / 2)
        rig.gira('pescoco1', pitch=-0.25, yaw=-p['pesc'])
        rig.gira('pescoco2', pitch=-0.1, yaw=-p['pesc'] * 0.6)
        rig.gira('cabeca', pitch=-0.25, yaw=-p['pesc'] * 0.4)
        rig.gira('mandibula', pitch=0.08)
        op, orl = P.get('morto_orelha', (0.3, 0.7))
        rig.gira('orelha_e', pitch=op, rola=-orl)
        rig.gira('orelha_d', pitch=op, rola=orl)
        rig.gira('cauda1', pitch=0.45, rola=-p['cauda'])
        for lado, frente in PERNAS:
            ch = CHAVE[(lado, frente)]
            a, b, c, d = (f'{n}_{lado}' for n in NOMES_PERNA[frente])
            sw, _ = abre[ch]
            top = f'escapula_{lado}' if frente else a
            if lado == 'e':                  # pernas de cima: descem girando no ombro/quadril
                rig.gira(top, pitch=sw, rola=-p[ch])
                rig.gira(b, pitch=(-0.25 if frente else 0.25) * 0.5)
            else:                            # pernas de baixo: a coxa já está no chão; dobram no cotovelo/joelho
                rig.gira(top, pitch=sw, rola=0.18)     # a coxa sobe um pouco para o tronco encostar
                rig.gira(b, pitch=(-0.25 if frente else 0.25) * 0.5, rola=-p[ch])
            rig.gira(c, pitch=(0.2 if frente else -0.2) * 0.5)
            rig.gira(d, pitch=0.35)
        rig.fk()
        rig.aplicar()

    if 'morto_prm' not in arm:
        # o tronco (com as coxas de baixo) encosta
        for _ in range(4):
            montar_pose(prm)
            prm['z'] -= _zmin(arm, (P_TRONCO, P_PESCOCO, *P_ALTA.values()))

        def busca(chave, partes, lo, hi):
            for _ in range(18):
                mid = (lo + hi) / 2
                prm[chave] = mid
                montar_pose(prm)
                if _zmin(arm, partes) > 0.0:
                    lo = mid
                else:
                    hi = mid
            prm[chave] = lo
        for volta in range(4):
            if volta:
                for _ in range(3):
                    montar_pose(prm)
                    prm['z'] -= _zmin(arm, (P_TRONCO, P_PESCOCO, *P_ALTA.values()))
            for lado, frente in PERNAS:
                ch = CHAVE[(lado, frente)]
                busca(ch, (P_BAIXA[ch],), -0.3, 1.3)
            busca('pesc', (P_CABECA, P_MANDIBULA, P_ORELHA, P_OSSO), -0.5, 1.5)
            busca('cauda', (P_CAUDA,), -0.6, 2.4)
            montar_pose(prm)                 # nada abaixo do chão: se algo desceu demais, sobe tudo e busca de novo
            zt = _zmin(arm)
            if zt > -1e-4:
                break
        montar_pose(prm)
        prm['z'] -= min(0.0, _zmin(arm))
        arm['morto_prm'] = prm
    montar_pose(prm)


ACOES = {'herbivoro': (('andar', 12, pose_andar), ('correr', 12, pose_correr), ('pastar', 24, pose_pastar),
                       ('alerta', 24, pose_alerta), ('morto', 2, pose_morto)),
         'predador': (('andar', 12, pose_andar), ('correr', 12, pose_correr), ('espreitar', 12, pose_espreitar),
                      ('morder', 12, pose_morder), ('comer', 24, pose_comer), ('deitado', 24, pose_deitado),
                      ('morto', 2, pose_morto))}


# ------------------------------------------------------------------ conferência: chão e interseções, quadro a quadro
def _pares(P):
    baixas = list(P_BAIXA.values())
    altas = list(P_ALTA.values())
    pares = []
    for i in baixas:
        for p in (P_TRONCO, P_PESCOCO, P_CABECA, P_MANDIBULA, P_CAUDA, P_OSSO):
            pares.append((i, p))
    for i in range(len(baixas)):
        for j in range(i + 1, len(baixas)):
            pares.append((baixas[i], baixas[j]))
    for ch, i in P_BAIXA.items():
        for ch2, j in P_ALTA.items():
            if ch2 != ch:
                pares.append((i, j))
    pares += [(P_OSSO, P_PESCOCO), (P_OSSO, P_TRONCO), (P_ORELHA, P_PESCOCO), (P_ORELHA, P_TRONCO), (P_ORELHA, P_OSSO),
              (P_MANDIBULA, P_PESCOCO), (P_MANDIBULA, P_TRONCO), (P_CAUDA, P_ALTA['te']), (P_CAUDA, P_ALTA['td'])]
    for ch, e in P_ESPORAO.items():
        for p in (P_TRONCO, P_CABECA, P_PESCOCO, *[P_BAIXA[c] for c in P_BAIXA if c != ch]):
            pares.append((e, p))
    return pares


NOME_PARTE = {P_TRONCO: 'tronco', P_PESCOCO: 'pescoço', P_CABECA: 'cabeça', P_MANDIBULA: 'mandíbula', P_CAUDA: 'cauda',
              P_ORELHA: 'orelha', P_OSSO: 'osso', **{v: 'perna-' + k for k, v in P_BAIXA.items()},
              **{v: 'coxa/braço-' + k for k, v in P_ALTA.items()}, **{v: 'esporão-' + k for k, v in P_ESPORAO.items()}}


def conferir_quadro(arm, apoio=None, tol=0.0025):
    """Mede o quadro atual: menor z (nada abaixo do chão), as solas no chão (pernas em apoio) e as interseções."""
    bpy.context.view_layer.update()
    o = corpo_de(arm)
    oe = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = oe.to_mesh()
    mw = arm.matrix_world.inverted() @ oe.matrix_world
    co = [mw @ v.co for v in me.vertices]
    pa = o.data.attributes['parte'].data
    polys = {}
    for i, poly in enumerate(me.polygons):
        polys.setdefault(pa[i].value, []).append(tuple(poly.vertices))
    oe.to_mesh_clear()
    zmin = min(c.z for c in co)
    arvores = {}

    def arvore(p):
        if p not in arvores:
            fs = polys.get(p, [])
            arvores[p] = BVHTree.FromPolygons(co, fs, all_triangles=False) if fs else None
        return arvores[p]
    cruz = []
    for a, b in _pares(ESPECIES[arm['especie']]):
        ta, tb = arvore(a), arvore(b)
        if ta is None or tb is None:
            continue
        n = len(ta.overlap(tb))
        if n:
            cruz.append((NOME_PARTE.get(a, a), NOME_PARTE.get(b, b), n))
    solto = []
    if apoio:
        rig = rig_de(arm)
        for lado, frente in PERNAS:
            ch = CHAVE[(lado, frente)]
            if apoio.get(ch):
                zs = min(p.z for p in rig.sola(lado, frente))
                if abs(zs) > tol:
                    solto.append((ch, round(zs, 4)))
    return zmin, cruz, solto


def conferir(arm, log):
    P = ESPECIES[arm['especie']]
    ruins = 0
    for nome, nq, posar in ACOES[P['grupo']]:
        for q in range(nq):
            r = posar(arm, q / nq)
            zmin, cruz, solto = conferir_quadro(arm, r if isinstance(r, dict) else None)
            ok = zmin > -0.0015 and not cruz and not solto
            if not ok:
                ruins += 1
                log.append(f'  {arm["especie"]} {nome} q{q}: zmin={zmin:.4f} cruza={cruz} solto={solto}')
    return ruins


# ------------------------------------------------------------------ cena (fotos e pranchas)
def luz_e_mundo():
    sol = bpy.data.lights.new('Sol', 'SUN'); sol.energy = 4.0; sol.angle = math.radians(2.5)
    so = bpy.data.objects.new('Sol', sol); sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), 0, math.radians(-35))
    sol2 = bpy.data.lights.new('Sol2', 'SUN'); sol2.energy = 1.4
    so2 = bpy.data.objects.new('Sol2', sol2); sc.collection.objects.link(so2)
    so2.rotation_euler = (math.radians(-30), 0, math.radians(140))
    mundo = bpy.data.worlds.new('Mundo'); sc.world = mundo
    bg = mundo.node_tree.nodes['Background']
    bg.inputs['Color'].default_value = (0.45, 0.48, 0.58, 1)
    bg.inputs['Strength'].default_value = 0.7


def cycles():
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'GPU'
    try:
        pr = bpy.context.preferences.addons['cycles'].preferences
        pr.compute_device_type = 'OPTIX'
        pr.get_devices()
        for dv in pr.devices:
            dv.use = True
    except Exception:
        sc.cycles.device = 'CPU'
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Medium High Contrast'
    sc.view_settings.exposure = -0.2


def camera():
    cam_d = bpy.data.cameras.new('Cam')
    cam = bpy.data.objects.new('Cam', cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def mirar(cam, pos, alvo, lente=None, orto=None):
    cam.location = pos
    cam.rotation_euler = (Vector(alvo) - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
    if orto:
        cam.data.type = 'ORTHO'
        cam.data.ortho_scale = orto
    else:
        cam.data.type = 'PERSP'
        cam.data.lens = lente


def rotulo(cam, texto, tam=0.022, pos=None):
    """Texto preso à câmera (canto de cima à esquerda da foto, calculado pela lente)."""
    if pos is None:
        hw = 18.0 / cam.data.lens
        pos = (-hw * 0.93, hw * (sc.render.resolution_y / sc.render.resolution_x) * 0.82)
    cu = bpy.data.curves.new('rot_' + texto[:8], 'FONT')
    cu.body = texto
    cu.size = tam
    o = bpy.data.objects.new('ROT_' + texto[:12], cu)
    sc.collection.objects.link(o)
    mt = bpy.data.materials.new('RotuloMat')
    nt = mt.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (0, 0, 0, 1)
    b.inputs['Emission Color'].default_value = (1, 1, 1, 1)
    b.inputs['Emission Strength'].default_value = 1.0
    mt.diffuse_color = (1, 1, 1, 1)
    o.data.materials.append(mt)
    o.parent = cam
    o.location = (pos[0], pos[1], -1.0)
    o.visible_shadow = False
    return o


def regua(origem, alt=1.5):
    """Régua de escala: estaca de faixas de 10 cm (branco/preto), com marcas maiores a cada 50 cm."""
    base3d.M['regua_b'] = liso_mat('ReguaB', (0.8, 0.8, 0.78), 0.6)
    base3d.M['regua_p'] = liso_mat('ReguaP', (0.02, 0.02, 0.02), 0.6)
    for k in range(int(round(alt / 0.1))):
        bm = bmesh.new()
        largo = 0.03 if (k + 1) % 5 else 0.045
        base3d.caixa(bm, (origem[0], origem[1], 0.05 + 0.1 * k), (largo, largo, 0.1))
        base3d.obj(f'EFEITO_regua{k}', bm, 'regua_b' if k % 2 == 0 else 'regua_p')


def chao(cx, cy, w, h, cor=((0.20, 0.17, 0.12), (0.08, 0.07, 0.05))):
    if 'chao' not in base3d.M:
        base3d.M['chao'] = pelagem_mat('Chao', dict(dorso=cor[0], barriga=cor[0], marca1=cor[0], marca2=cor[0],
                                                     fino=8.0, largo=1.5, aspereza=0.95))
    bm = bmesh.new()
    base3d.caixa(bm, (cx, cy, -0.05), (w, h, 0.10))
    return base3d.obj('EFEITO_chao', bm, 'chao')


def rato_de_escala(pos, giro):
    glb = os.path.join(AQUI, '..', 'modelos', 'fauna', 'ratos', 'rato_pardo', 'rato_pardo.glb')
    if not os.path.exists(glb):
        return None
    antes = set(sc.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    novos = [o for o in sc.objects if o not in antes]
    raiz = next((o for o in novos if o.parent is None), None)
    if raiz:
        raiz.location = pos
        raiz.rotation_euler = (0.0, 0.0, giro)
    return novos


def prancha(arquivos, colunas, saida, fundo=(0.12, 0.12, 0.13)):
    """Junta as imagens (mesmo tamanho) numa grade."""
    import numpy as np
    imgs = [bpy.data.images.load(f) for f in arquivos]
    w, h = imgs[0].size
    linhas = (len(imgs) + colunas - 1) // colunas
    W, H = w * colunas, h * linhas
    big = np.zeros((H, W, 4), dtype=np.float32)
    big[:, :, :3] = fundo
    big[:, :, 3] = 1.0
    for i, im in enumerate(imgs):
        px = np.empty(w * h * 4, dtype=np.float32)
        im.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        c, l = i % colunas, i // colunas
        y0 = H - (l + 1) * h
        big[y0:y0 + h, c * w:(c + 1) * w] = px
    out = bpy.data.images.new('prancha', W, H, alpha=False)
    out.pixels.foreach_set(big.ravel())
    out.filepath_raw = saida
    out.file_format = 'PNG'
    out.save()
    for im in imgs:
        bpy.data.images.remove(im)
    bpy.data.images.remove(out)


def cena_fotos():
    """Pranchas das candidatas: por grupo, cada bicho de lado (parado) e de 3/4 (andando), com régua e um rato."""
    luz_e_mundo()
    cycles()
    cam = camera()
    sc.cycles.samples = 96
    sc.render.resolution_x, sc.render.resolution_y = 1000, 680
    chao(0, 20, 90, 120)
    grupos = (('herbivoros', (('galhudo', 'A'), ('corcova', 'B'))), ('predadores', (('uivador', 'A'), ('espreitador', 'B'))))
    os.makedirs(SAIDA, exist_ok=True)
    y0 = 0.0
    for gnome, lista in grupos:
        arqs = []
        for esp, letra in lista:
            P = ESPECIES[esp]
            lado = montar(f'{esp}_foto_lado', esp, Vector((0, y0, 0)), 0.0)
            pose_parado(lado)
            anda = montar(f'{esp}_foto_anda', esp, Vector((0, y0 - 6.0, 0)), 0.5)
            pose_andar(anda, 0.15)
            regua((0.0, y0 + 0.55, 0.0) if P['grupo'] == 'herbivoro' else (0.0, y0 + 0.45, 0.0), 1.5 if P['grupo'] == 'herbivoro' else 1.0)
            rato_de_escala((0.25, y0 - 0.32, 0.0), 0.6)
            comp = P['tubo'][-1][0] - P['tubo'][0][0]
            alt = max(s[1] + s[3] for s in P['tubo'])
            meio = (P['tubo'][-1][0] + P['tubo'][0][0]) / 2
            dist = comp * 2.9
            mirar(cam, (meio, y0 - dist, alt * 0.55), (meio, y0, alt * 0.48), 50)
            rot = [rotulo(cam, f'{letra} — {esp}  ({P["nome"]})', tam=0.018)]

            def so_este(arm_vis):                  # cada foto mostra só o bicho da vez (os outros somem)
                for o_ in sc.objects:
                    if o_.type == 'MESH' and o_.parent is not None and o_.parent.type == 'ARMATURE' \
                            and o_.parent.get('especie'):
                        o_.hide_render = o_.parent is not arm_vis
            so_este(lado)
            sc.render.filepath = os.path.join(SAIDA, f'_{esp}_lado.png')
            bpy.ops.render.render(write_still=True)
            arqs.append(sc.render.filepath)
            c3 = Vector((meio, y0 - 6.0, 0))
            mirar(cam, (c3.x + comp * 1.6, c3.y - comp * 2.0, alt * 1.35), (c3.x, c3.y, alt * 0.42), 45)
            so_este(anda)
            sc.render.filepath = os.path.join(SAIDA, f'_{esp}_34.png')
            bpy.ops.render.render(write_still=True)
            arqs.append(sc.render.filepath)
            for o in rot:
                bpy.data.objects.remove(o, do_unlink=True)
            y0 += 14.0
        prancha(arqs, 2, os.path.join(SAIDA, f'{gnome}.png'))
        for f in arqs:
            os.remove(f)
        print('PRANCHA', gnome)


def cena_quadros(especies, vistas=('lado', '34'), nome_saida='acoes_{esp}_estudo'):
    """Prancha de quadros por ação (Workbench): uma linha por ação, uma coluna por quadro (ações de 24 quadros: um
    sim, um não); a faixa cinza é o chão (z = 0). Vista 'lado' (quase rente ao chão: contato) e '34' (de cima, de 3/4:
    pernas cruzando, cabeça, cauda). Cada quadro também é medido (chão e interseções) e o resultado sai no log."""
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_shadows = True
    sh.show_cavity = True
    sc.display.light_direction = (0.35, -0.45, 0.82)
    sc.view_settings.view_transform = 'Standard'
    cam = camera()
    os.makedirs(SAIDA, exist_ok=True)
    base3d.M['faixa'] = liso_mat('ChaoFaixa', (0.32, 0.32, 0.32), 0.9)
    for esp in especies:
        P = ESPECIES[esp]
        comp = P['tubo'][-1][0] - P['tubo'][0][0] + 0.45
        alt = max(s_[1] + s_[3] for s_ in P['tubo']) + 0.2
        acoes = ACOES[P['grupo']]
        ncol = 12
        log = []
        linhas = {v: [] for v in vistas}
        for li, (nome, nq, posar) in enumerate(acoes):
            for o in list(sc.objects):
                if o is not cam:
                    bpy.data.objects.remove(o, do_unlink=True)
            passo = max(1, nq // ncol)
            qs = list(range(0, nq, passo))[:ncol]
            arms = []
            for ci, q in enumerate(qs):
                arm = montar(f'{esp}_{nome}_{q}', esp, Vector((ci * comp, 0.0, 0.0)), 0.0)
                arms.append(arm)
                r = posar(arm, q / nq)
                zmin, cruz, solto = conferir_quadro(arm, r if isinstance(r, dict) else None)
                if zmin < -0.0015 or cruz or solto:
                    log.append(f'{nome} q{q}: zmin={zmin:.4f} cruza={cruz} solto={solto}')
            bm = bmesh.new()
            base3d.caixa(bm, ((ncol - 1) * comp / 2, 0.0, -0.004), (ncol * comp + 0.3, 1.6, 0.008))
            base3d.obj('EFEITO_faixa', bm, 'faixa')
            cu = bpy.data.curves.new('t', 'FONT')
            cu.body = f'{nome} ({nq})'
            cu.size = 0.22 * alt
            ot = bpy.data.objects.new('ROT', cu)
            sc.collection.objects.link(ot)
            ot.data.materials.append(liso_mat('RotBranco', (0.9, 0.9, 0.9)))
            cx = (ncol - 1) * comp / 2
            W = ncol * comp
            for v in vistas:
                for a_ in arms:                  # 3/4: cada bicho gira no lugar (mostra o lado e a frente)
                    a_.rotation_euler = (0.0, 0.0, 0.0 if v == 'lado' else -0.75)
                azi = 0.0
                if v == 'lado':
                    ele = math.radians(6)
                    H_ = alt * 1.12
                else:
                    ele = math.radians(30)
                    H_ = alt * 1.12 + 0.35
                dist = 60.0
                d = Vector((math.sin(azi) * math.cos(ele), -math.cos(azi) * math.cos(ele), math.sin(ele)))
                alvo = Vector((cx, 0.0, alt * 0.45))
                ot.location = (-comp * 0.05, -0.8, alt * 0.85)
                ot.rotation_euler = (math.pi / 2 - ele, 0, azi)
                mirar(cam, tuple(alvo + d * dist), tuple(alvo), orto=W * 1.02)
                sc.render.resolution_x = 4200
                sc.render.resolution_y = int(4200 * H_ / (W * 1.02))
                arq = os.path.join(SAIDA, f'_q_{esp}_{nome}_{v}.png')
                sc.render.filepath = arq
                bpy.ops.render.render(write_still=True)
                linhas[v].append(arq)
        for v in vistas:
            prancha(linhas[v], 1, os.path.join(SAIDA, nome_saida.format(esp=esp) + ('' if v == 'lado' else '_34') + '.png'))
            if not _OPC.get('manter'):
                for arq in linhas[v]:                # as linhas soltas já estão na prancha
                    os.remove(arq)
        print('QUADROS', esp, 'problemas:', len(log))
        for linha in log:
            print('   ', linha)


modo = _ARGS[0] if _ARGS else 'foto'
if modo == 'foto':
    cena_fotos()
elif modo == 'quadros':
    so_ = _OPC.get('so')
    cena_quadros(so_.split(',') if so_ else list(ESPECIES))
elif modo == 'conferir':
    for esp in (_OPC['so'].split(',') if 'so' in _OPC else ESPECIES):
        arm = montar(f'{esp}_conf', esp)
        o = corpo_de(arm)
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        log = []
        n = conferir(arm, log)
        print(f'CONFERIR {esp} tris={tris} quadros_ruins={n}')
        for l in log:
            print(l)
elif modo == 'diag':
    # vistas rápidas (Workbench, ortográficas): lado, frente, cima e 3/4 de cada espécie numa pose
    sc.render.engine = 'BLENDER_WORKBENCH'
    sh = sc.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_shadows = False
    sh.show_cavity = True
    sc.view_settings.view_transform = 'Standard'
    cam = camera()
    acao = _OPC.get('acao', 'parado')
    u = float(_OPC.get('u', '0'))
    os.makedirs(SAIDA, exist_ok=True)
    for esp in (_OPC['so'].split(',') if 'so' in _OPC else ESPECIES):
        for o in list(sc.objects):
            if o is not cam:
                bpy.data.objects.remove(o, do_unlink=True)
        arm = montar(f'{esp}_diag', esp)
        fn = globals()['pose_' + acao]
        r = fn(arm, u)
        print('DIAG', esp, acao, u, conferir_quadro(arm, r if isinstance(r, dict) else None))
        P = ESPECIES[esp]
        comp = P['tubo'][-1][0] - P['tubo'][0][0] + 0.5
        alt = max(s[1] + s[3] for s in P['tubo'])
        mx = (P['tubo'][-1][0] + P['tubo'][0][0]) / 2
        bm = bmesh.new()
        base3d.M['faixa'] = liso_mat('ChaoFaixa', (0.30, 0.30, 0.30), 0.9)
        base3d.caixa(bm, (mx, 0.0, -0.005), (comp * 1.5, 0.002, 0.01))
        base3d.obj('EFEITO_linha', bm, 'faixa')
        sc.render.resolution_x, sc.render.resolution_y = 900, 700
        for nome, pos, orto in (('lado', (mx, -10, alt * 0.55), comp * 1.25), ('frente', (10, 0, alt * 0.55), alt * 1.3),
                                ('cima', (mx, 0.0, 10), comp * 1.25),
                                ('34', (mx + 6, -7, 5), comp * 1.25)):
            alvo = (mx, 0.0, alt * 0.55) if nome != 'cima' else (mx, 0.001, 0.0)
            mirar(cam, pos, alvo, orto=orto)
            sc.render.filepath = os.path.join(SAIDA, f'{esp}_{acao}_{nome}.png')
            bpy.ops.render.render(write_still=True)
        prancha([os.path.join(SAIDA, f'{esp}_{acao}_{n}.png') for n in ('lado', 'frente', 'cima', '34')], 2,
                os.path.join(SAIDA, f'D_{esp}_{acao}.png'))
elif modo == 'tris':
    for esp in ESPECIES:
        arm = montar(f'{esp}_t', esp)
        o = corpo_de(arm)
        print(f'TRIS {esp} {sum(len(p.vertices) - 2 for p in o.data.polygons)}')
