"""Estudo isolado (fora do jogo): PÁSSAROS do planeta (patch fauna; pedido de Sapyst: natureza viva, "bem pé no chão").
Fauna nativa de um mundo alienígena, mas crível: anatomia de ave de verdade, com um detalhe estranho cada.
  A) PARDELO — pássaro pequeno de bando (~0,24 m sem a cauda, envergadura ~0,55 m): pardo-escuro, peito ferrugem,
     bico curto de semente; o estranho: crista óssea clara na nuca e duas penas-fita na cauda.
  B) PLANADOR-CINZA — ave grande que plana alto (envergadura ~1,8 m): cinza-ardósia, primárias escuras e separadas
     ("dedos"); o estranho: um par de asinhas atrás (lemes) que abrem ao planar.
MODELO (refeito a pedido de Sapyst): UMA malha só, deformada pelo esqueleto. Corpo, pescoço e cabeça num tubo
contínuo; a asa nasce de dentro do tronco (membrana do ombro ao punho) e as penas são encaixadas nela no sentido em
que crescem — primárias na mão, secundárias no braço, duas fileiras de coberteiras por cima. Cada pena acompanha
rígida o osso em que nasce (o peso é o da raiz), então dobrar a asa não estica nem torce pena para fora.
Poses: voo (batida), planar, pousado (asas fechadas sobre o dorso) e bicando.

Uso: blender -b --python estudo_passaro.py -- foto
     blender -b --python estudo_passaro.py -- nada
"""
import bpy, bmesh, math, os, sys, random
from mathutils import Vector, Matrix, noise

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import base3d

PI = math.pi
random.seed(23)
_ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
JOGO_Q = 'jogo' in _ARGS                 # qualidade do jogo: penas com menos segmentos, uma fileira de coberteiras

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = base3d.iniciar()


# ------------------------------------------------------------------ materiais
def plumagem_mat(nome, claro, escuro, faixas=0.0, escala=30.0, aspereza=0.72):
    """Pena miúda do corpo: mancha fina entre o claro e o escuro, barras leves ao longo do corpo, fosca."""
    m = bpy.data.materials.new(nome)
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = escala; nz.inputs['Detail'].default_value = 6.0
    nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    wv = nt.nodes.new('ShaderNodeTexWave'); wv.inputs['Scale'].default_value = 9.0; wv.inputs['Distortion'].default_value = 3.0
    wv.bands_direction = 'X'
    nt.links.new(tc.outputs['Object'], wv.inputs['Vector'])
    mx = nt.nodes.new('ShaderNodeMath'); mx.operation = 'MULTIPLY_ADD'
    nt.links.new(wv.outputs['Fac'], mx.inputs[0]); mx.inputs[1].default_value = faixas
    nt.links.new(nz.outputs['Fac'], mx.inputs[2])
    rmp = nt.nodes.new('ShaderNodeValToRGB')
    rmp.color_ramp.elements[0].position = 0.38; rmp.color_ramp.elements[0].color = (*escuro, 1)
    rmp.color_ramp.elements[1].position = 0.72; rmp.color_ramp.elements[1].color = (*claro, 1)
    nt.links.new(mx.outputs[0], rmp.inputs['Fac'])
    nt.links.new(rmp.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = aspereza
    b.inputs['Sheen Weight'].default_value = 0.0
    return m


def pena_mat(nome, base, ponta, borda, y0, y1):
    """Pena da asa/cauda: a cor da base escurece para a ponta da asa (|y| do objeto, a envergadura) e cada pena tem a
    borda clara (UV.x = através da pena: 0 e 1 nas bordas, 0,5 na haste), como as penas de verdade."""
    m = bpy.data.materials.new(nome)
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ'); nt.links.new(tc.outputs['Object'], sep.inputs[0])
    ab = nt.nodes.new('ShaderNodeMath'); ab.operation = 'ABSOLUTE'; nt.links.new(sep.outputs['Y'], ab.inputs[0])
    mr = nt.nodes.new('ShaderNodeMapRange'); mr.inputs['From Min'].default_value = y0; mr.inputs['From Max'].default_value = y1
    nt.links.new(ab.outputs[0], mr.inputs['Value'])
    rmp = nt.nodes.new('ShaderNodeValToRGB')
    rmp.color_ramp.elements[0].position = 0.0; rmp.color_ramp.elements[0].color = (*base, 1)
    rmp.color_ramp.elements[1].position = 1.0; rmp.color_ramp.elements[1].color = (*ponta, 1)
    nt.links.new(mr.outputs[0], rmp.inputs['Fac'])
    uv = nt.nodes.new('ShaderNodeUVMap'); uv.uv_map = 'UVMap'     # nome fixo: o assado escreve em outro mapa
    sep2 = nt.nodes.new('ShaderNodeSeparateXYZ'); nt.links.new(uv.outputs['UV'], sep2.inputs[0])
    meio = nt.nodes.new('ShaderNodeMath'); meio.operation = 'SUBTRACT'; meio.inputs[1].default_value = 0.5
    nt.links.new(sep2.outputs['X'], meio.inputs[0])
    ab2 = nt.nodes.new('ShaderNodeMath'); ab2.operation = 'ABSOLUTE'; nt.links.new(meio.outputs[0], ab2.inputs[0])
    bd = nt.nodes.new('ShaderNodeMapRange'); bd.inputs['From Min'].default_value = 0.44; bd.inputs['From Max'].default_value = 0.5
    nt.links.new(ab2.outputs[0], bd.inputs['Value'])
    mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'
    nt.links.new(bd.outputs[0], mix.inputs[0])
    nt.links.new(rmp.outputs['Color'], mix.inputs[6]); mix.inputs[7].default_value = (*borda, 1)
    nt.links.new(mix.outputs[2], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.68
    b.inputs['Sheen Weight'].default_value = 0.0
    return m


def liso_mat(nome, cor, aspereza=0.5, brilho=0.0):
    m = bpy.data.materials.new(nome)
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*cor, 1)
    b.inputs['Roughness'].default_value = aspereza
    b.inputs['Coat Weight'].default_value = brilho
    return m


PALETAS = {   # corpo (claro, escuro), peito (claro, escuro), pena (base, ponta, borda), bico
    'cobrico': ((0.36, 0.33, 0.04), (0.12, 0.11, 0.015), (0.62, 0.50, 0.03), (0.30, 0.22, 0.01),
                ((0.035, 0.035, 0.03), (0.01, 0.01, 0.01), (0.55, 0.48, 0.06)), 'claro'),
    'azulao': ((0.03, 0.10, 0.30), (0.008, 0.03, 0.10), (0.55, 0.20, 0.04), (0.26, 0.07, 0.015),
               ((0.02, 0.06, 0.20), (0.005, 0.01, 0.03), (0.10, 0.22, 0.42)), 'escuro'),
    'rubro': ((0.42, 0.035, 0.03), (0.14, 0.01, 0.01), (0.55, 0.10, 0.06), (0.25, 0.03, 0.02),
              ((0.05, 0.02, 0.02), (0.012, 0.008, 0.008), (0.30, 0.06, 0.04)), 'claro'),
}
MAT = {
    'pardelo': [plumagem_mat('PardeloCorpo', (0.23, 0.17, 0.11), (0.07, 0.05, 0.035), faixas=0.18),
                plumagem_mat('PardeloPeito', (0.50, 0.24, 0.10), (0.24, 0.10, 0.045), escala=45),
                pena_mat('PardeloPena', (0.13, 0.09, 0.06), (0.035, 0.026, 0.02), (0.26, 0.20, 0.13), 0.08, 0.27)],
    'planador': [plumagem_mat('PlanadorCorpo', (0.20, 0.21, 0.23), (0.08, 0.085, 0.10), faixas=0.1),
                 plumagem_mat('PlanadorPeito', (0.42, 0.42, 0.41), (0.22, 0.23, 0.24), escala=40),
                 pena_mat('PlanadorPena', (0.15, 0.16, 0.18), (0.025, 0.025, 0.03), (0.28, 0.29, 0.31), 0.45, 0.95)],
}
M_BICO = {'pardelo': liso_mat('BicoClaro', (0.55, 0.45, 0.22), 0.4, 0.2), 'planador': liso_mat('Bico', (0.10, 0.09, 0.08), 0.35, 0.3)}
for _n, (_cc, _ce, _pc, _pe, (_b, _p, _bo), _bico) in PALETAS.items():
    MAT[_n] = [plumagem_mat(_n + 'Corpo', _cc, _ce, faixas=0.08), plumagem_mat(_n + 'Peito', _pc, _pe, escala=45),
               pena_mat(_n + 'Pena', _b, _p, _bo, 0.08, 0.27)]
    M_BICO[_n] = M_BICO['pardelo'] if _bico == 'claro' else M_BICO['planador']
M_OLHO = liso_mat('Olho', (0.01, 0.01, 0.01), 0.08, 1.0)
M_PE = liso_mat('PelePe', (0.30, 0.24, 0.18), 0.6)
M_CRISTA = liso_mat('PardeloCrista', (0.72, 0.66, 0.52), 0.45, 0.2)
I_CORPO, I_PEITO, I_PENA, I_BICO, I_OLHO, I_PE, I_CRISTA = range(7)

ESPECIES = {
    'pardelo': dict(escala=1.0, altura=0.075, largura=1.0, envergadura=0.55, corte=0.45, corda=0.085,
                    primarias=9, prim_comp=(0.060, 0.085), prim_larg=0.016, secundarias=10, sec_comp=0.062, sec_larg=0.017,
                    cauda_n=9, cauda_comp=0.075, leque=0.55, bico=0.020, bico_r=0.0085, crista=True, fitas=True),
    # coloridos: o mesmo corpo de pássaro pequeno, outra cor e um detalhe cada
    'cobrico': dict(escala=0.85, altura=0.075, largura=1.0, envergadura=0.52, corte=0.45, corda=0.085,
                    primarias=9, prim_comp=(0.058, 0.080), prim_larg=0.016, secundarias=10, sec_comp=0.060, sec_larg=0.017,
                    cauda_n=9, cauda_comp=0.060, leque=0.5, bico=0.024, bico_r=0.010, crista=False, fitas=False),
    'azulao': dict(escala=1.1, altura=0.075, largura=1.0, envergadura=0.56, corte=0.45, corda=0.085,
                   primarias=9, prim_comp=(0.062, 0.088), prim_larg=0.016, secundarias=10, sec_comp=0.064, sec_larg=0.017,
                   cauda_n=9, cauda_comp=0.095, leque=0.35, bico=0.018, bico_r=0.007, crista=True, fitas=False),
    'rubro': dict(escala=0.95, altura=0.075, largura=1.0, envergadura=0.54, corte=0.45, corda=0.085,
                  primarias=9, prim_comp=(0.060, 0.085), prim_larg=0.016, secundarias=10, sec_comp=0.062, sec_larg=0.017,
                  cauda_n=9, cauda_comp=0.07, leque=0.6, bico=0.020, bico_r=0.0095, crista=False, fitas=True),
    'planador': dict(escala=2.4, altura=0.07, largura=0.9, envergadura=0.75, corte=0.40, corda=0.072,
                     primarias=7, prim_comp=(0.075, 0.105), prim_larg=0.011, secundarias=13, sec_comp=0.060, sec_larg=0.013,
                     cauda_n=11, cauda_comp=0.06, leque=0.8, bico=0.026, bico_r=0.0075, lemes=True, dedos=True),
}


# ------------------------------------------------------------------ montagem: uma malha, pesos por regra
class Malha:
    """Junta tudo numa bmesh só; cada vértice guarda os pesos dos ossos (dicionário), gravados no fim em grupos."""
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap')
        self.pesos = {}

    def v(self, co, pesos):
        vv = self.bm.verts.new(co)
        self.pesos[vv] = pesos
        return vv

    def f(self, vs, mat, uvs=None):
        try:
            fa = self.bm.faces.new(vs)
        except ValueError:
            return None
        fa.material_index = mat
        fa.smooth = True
        if uvs:
            for lp, u in zip(fa.loops, uvs):
                lp[self.uv].uv = u
        return fa


def mistura(a, b, t):
    """Pesos: osso a → osso b conforme t (0..1, suavizado)."""
    t = max(0.0, min(1.0, t))
    t = t * t * (3 - 2 * t)
    if t <= 0.0:
        return {a: 1.0}
    if t >= 1.0:
        return {b: 1.0}
    return {a: 1.0 - t, b: t}


def pena(m, raiz, d, comp, larg, pesos, mat, curva=0.10, cima=Vector((0, 0, 1)), assim=0.0, ponta_red=1.0):
    """Pena: haste da raiz na direção `d`, vane que alarga até 30% e afina na ponta arredondada, arqueada para baixo;
    duas faces (frente e verso, separadas 0,6 mm) para ver dos dois lados. Todos os vértices com o peso da raiz."""
    d = d.normalized()
    lado = d.cross(cima).normalized()
    if lado.length < 1e-6:
        lado = Vector((0, 1, 0))
    normal = lado.cross(d).normalized()
    N = 2 if JOGO_Q else 6
    perfis = []
    for i in range(N + 1):
        t = i / N
        w = larg * (0.35 + 0.65 * math.sin(min(1.0, t / 0.3) * PI / 2)) * (1.0 - t ** 3 * 0.85 * ponta_red)
        z = -curva * comp * t * t                                      # arqueia para baixo
        p = raiz + d * comp * t + normal * z
        perfis.append((p, w * (1 - assim), w * (1 + assim), t))
    for s, dz in ((1, 0.0003), (-1, -0.0003)):
        linhas = []
        for p, wa, wb, t in perfis:
            if JOGO_Q:                          # sem a haste no meio: uma tira só por pena
                linhas.append([m.v(p + lado * wa + normal * dz, pesos), m.v(p - lado * wb + normal * dz, pesos)])
            else:
                linhas.append([m.v(p + lado * wa + normal * dz, pesos), m.v(p + normal * (dz + 0.0008 * s), pesos),
                               m.v(p - lado * wb + normal * dz, pesos)])
        larg_n = len(linhas[0]) - 1
        for i in range(N):
            for j in range(larg_n):
                q = [linhas[i][j], linhas[i][j + 1], linhas[i + 1][j + 1], linhas[i + 1][j]]
                u = [(j / larg_n, i / N), ((j + 1) / larg_n, i / N), ((j + 1) / larg_n, (i + 1) / N), (j / larg_n, (i + 1) / N)]
                if s < 0:
                    q, u = q[::-1], u[::-1]
                m.f(q, mat, u)


def montar_passaro(nome, especie, origem=Vector((0, 0, 0)), giro=0.0):
    P = dict(ESPECIES[especie])
    if JOGO_Q:            # no jogo o pássaro é pequeno na tela (e vem em bando): poucas penas, maiores
        P.update(primarias=max(4, P['primarias'] // 2), secundarias=max(4, P['secundarias'] // 2),
                 prim_larg=P['prim_larg'] * 1.6, sec_larg=P['sec_larg'] * 1.9, cauda_n=5)
    s = P['escala']
    h = P['altura'] * s
    arm_d = bpy.data.armatures.new(nome + '_esqueleto')
    arm = bpy.data.objects.new(nome, arm_d)
    sc.collection.objects.link(arm)
    arm.location = origem
    arm.rotation_euler = (0, 0, giro)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    ombro_y = 0.026 * s * P['largura']
    ombro = Vector((0.035 * s, ombro_y, h + 0.022 * s))
    meia = P['envergadura'] * s / 2 - ombro_y
    corte = meia * P['corte']

    def osso(n, a, b, pai=None):
        e = arm_d.edit_bones.new(n)
        e.head, e.tail, e.roll = Vector(a), Vector(b), 0.0
        if pai:
            e.parent = arm_d.edit_bones[pai]
    osso('corpo', (-0.02 * s, 0, h), (0.03 * s, 0, h))
    osso('cabeca', (0.075 * s, 0, h + 0.03 * s), (0.11 * s, 0, h + 0.045 * s), 'corpo')
    osso('cauda', (-0.07 * s, 0, h + 0.004 * s), (-0.12 * s, 0, h), 'corpo')
    osso('pernas', (0.0, 0, h - 0.03 * s), (0.0, 0, h - 0.06 * s), 'corpo')
    for lado, sg in (('e', 1), ('d', -1)):
        o = Vector((ombro.x, ombro.y * sg, ombro.z))
        osso(f'asa_{lado}1', o, o + Vector((0, corte * sg, 0)), 'corpo')
        osso(f'asa_{lado}2', o + Vector((0, corte * sg, 0)), o + Vector((0, meia * sg, 0)), f'asa_{lado}1')
        if P.get('lemes'):
            r = Vector((-0.085 * s, 0.014 * s * sg, h + 0.012 * s))
            osso(f'leme_{lado}', r, r + Vector((0, 0.04 * s * sg, 0)), 'corpo')
    bpy.ops.object.mode_set(mode='OBJECT')

    m = Malha()
    # ---- corpo + pescoço + cabeça: um tubo contínuo (seções x, ry, rz, z do centro)
    secs = [(-0.095, 0.010, 0.008, 0.006), (-0.08, 0.020, 0.016, 0.003), (-0.055, 0.031, 0.026, 0.0),
            (-0.02, 0.040, 0.036, -0.003), (0.015, 0.042, 0.039, -0.002), (0.045, 0.037, 0.035, 0.004),
            (0.068, 0.026, 0.026, 0.016), (0.080, 0.021, 0.021, 0.026), (0.092, 0.023, 0.023, 0.036),
            (0.110, 0.025, 0.024, 0.042), (0.126, 0.021, 0.020, 0.043), (0.137, 0.012, 0.012, 0.041), (0.142, 0.004, 0.004, 0.040)]
    LADOS = 8 if JOGO_Q else 18
    aneis = []
    for x, ry, rz, z in secs:
        ry *= s * (P['largura'] if x < 0.06 else 1.0)
        rz *= s
        x *= s
        z = h + z * s
        pz = mistura('corpo', 'cabeca', (x - 0.055 * s) / (0.03 * s))
        if x < -0.06 * s:
            pz = mistura('cauda', 'corpo', (x + 0.085 * s) / (0.03 * s))
        anel = []
        for i in range(LADOS):
            a = 2 * PI * i / LADOS
            ca, sa = math.cos(a), math.sin(a)
            r_extra = 1.0 + (0.12 * max(0.0, -sa) if -0.04 * s < x < 0.05 * s else 0.0)   # peito cheio embaixo
            co = Vector((x, ry * ca, z + rz * sa * r_extra))
            co += Vector((noise.noise(co * 50 / s), noise.noise(co * 50 / s + Vector((3, 1, 2))), noise.noise(co * 50 / s + Vector((7, 2, 5))))) * 0.0012 * s
            anel.append(m.v(co, pz))
        aneis.append(anel)
    for k, (a, b) in enumerate(zip(aneis, aneis[1:])):
        for i in range(LADOS):
            j = (i + 1) % LADOS
            sa = math.sin(2 * PI * (i + 0.5) / LADOS)
            xm = secs[k][0]
            peito = sa < -0.25 and -0.06 < xm < 0.075
            m.f((a[i], a[j], b[j], b[i]), I_PEITO if peito else I_CORPO)
    for anel, inv in ((aneis[0], True), (aneis[-1], False)):
        c = m.v(sum((v.co for v in anel), Vector()) / LADOS, m.pesos[anel[0]])
        for i in range(LADOS):
            j = (i + 1) % LADOS
            m.f((anel[j], anel[i], c) if inv else (anel[i], anel[j], c), I_CORPO)
    hc = Vector((0.115 * s, 0, h + 0.042 * s))
    cab = {'cabeca': 1.0}
    # bico (cone achatado), olhos, crista
    base_b = hc + Vector((0.018 * s, 0, -0.004 * s))
    ponta_b = base_b + Vector((P['bico'] * s, 0, -P['bico'] * 0.2 * s))
    anel = [m.v(base_b + Vector((0, math.cos(a) * P['bico_r'] * s, math.sin(a) * P['bico_r'] * s * 0.85)), cab)
            for a in [2 * PI * i / 10 for i in range(10)]]
    pv = m.v(ponta_b, cab)
    for i in range(10):
        m.f((anel[i], anel[(i + 1) % 10], pv), I_BICO)
    for sy in (1, -1):
        c0 = hc + Vector((0.008 * s, 0.0205 * s * sy, 0.006 * s))
        res = bmesh.ops.create_uvsphere(m.bm, u_segments=4 if JOGO_Q else 8, v_segments=3 if JOGO_Q else 6, radius=0.0042 * s)
        for vv in res['verts']:
            vv.co = c0 + Vector((vv.co.x * 0.9, vv.co.y * 0.6, vv.co.z))
            m.pesos[vv] = cab
        for fa in {f for vv in res['verts'] for f in vv.link_faces}:
            fa.material_index = I_OLHO
            fa.smooth = True
    if P.get('crista'):
        for k in range(2 if JOGO_Q else 4):
            t = k / 3
            pena(m, hc + Vector((-0.004 * s - 0.008 * s * t, 0, 0.020 * s)), Vector((-1, 0, 0.35 - 0.2 * t)),
                 (0.026 - 0.006 * t) * s, 0.0035 * s, cab, I_CRISTA if especie == 'pardelo' else I_PEITO, curva=-0.15)
    # ---- pernas
    for sy in (1, -1):
        y = 0.014 * s * sy
        joelho = Vector((0.006 * s, y, h - 0.028 * s))
        pe_ = Vector((0.012 * s, y, 0.003 * s))
        pena(m, joelho, pe_ - joelho, (pe_ - joelho).length, 0.0028 * s, {'pernas': 1.0}, I_PE, curva=0.0,
             cima=Vector((1, 0, 0)), ponta_red=0.0)
        for k, a in enumerate(() if JOGO_Q else (-0.5, 0.0, 0.5, PI)):
            dd = Vector((math.cos(a), math.sin(a) * 0.9, -0.08))
            pena(m, pe_, dd, (0.019 if k < 3 else 0.013) * s, 0.0017 * s, {'pernas': 1.0}, I_PE, curva=0.1)
    # ---- cauda: leque em camadas da base do dorso para trás
    nt_ = P['cauda_n']
    for k in range(nt_):
        u = k / (nt_ - 1) - 0.5
        a = u * P['leque']
        dd = Vector((-math.cos(a), math.sin(a), 0.04))
        raiz = Vector((-0.072 * s, u * 0.014 * s, h + 0.010 * s + 0.0012 * s * (1 - abs(u) * 2)))
        pena(m, raiz, dd, P['cauda_comp'] * s * (1 - 0.12 * abs(u)), 0.012 * s, {'cauda': 1.0}, I_PENA, curva=0.04)
    if P.get('fitas'):
        for sy in (1, -1):
            pena(m, Vector((-0.075 * s, 0.003 * s * sy, h + 0.013 * s)), Vector((-1, 0.07 * sy, -0.02)), 0.17 * s,
                 0.0045 * s, {'cauda': 1.0}, I_PENA, curva=0.08, ponta_red=0.2)
    # ---- asas: membrana do tronco ao punho + penas
    for lado, sg in (('e', 1), ('d', -1)):
        b1, b2 = f'asa_{lado}1', f'asa_{lado}2'

        def peso_span(y):                          # y = distância do ombro ao longo da envergadura
            if y < 0.25 * corte:
                return mistura('corpo', b1, y / (0.25 * corte))
            return mistura(b1, b2, (y - corte * 0.85) / (corte * 0.3))
        corda = P['corda'] * s

        def le(y):                                  # bordo de ataque (x local) ao longo da envergadura
            t = y / meia
            return 0.012 * s - 0.03 * s * t * t
        # membrana (patágio): placa grossa e arredondada que sai de dentro do corpo e afina até o punho
        n = 4 if JOGO_Q else 10
        topo, fundo = [], []
        for i in range(n + 1):
            y = -0.012 * s + (corte + 0.012 * s) * i / n
            t = max(0.0, y) / corte
            esp = 0.010 * s * (1 - 0.7 * t)
            w = corda * (0.55 - 0.25 * t)
            linha_t, linha_f = [], []
            for j in range(4):
                xj = le(max(0.0, y)) - w * j / 3
                zj = 0.006 * s * math.sin(PI * j / 3) - 0.003 * s
                p = Vector((ombro.x + xj, (ombro.y + y) * sg, ombro.z + zj))
                pw = peso_span(max(0.0, y))
                linha_t.append(m.v(p + Vector((0, 0, esp / 2)), pw))
                linha_f.append(m.v(p - Vector((0, 0, esp / 2)), pw))
            topo.append(linha_t)
            fundo.append(linha_f)
        for i in range(n):
            for j in range(3):
                q = [topo[i][j], topo[i + 1][j], topo[i + 1][j + 1], topo[i][j + 1]]
                q2 = [fundo[i][j], fundo[i][j + 1], fundo[i + 1][j + 1], fundo[i + 1][j]]
                if sg < 0:
                    q, q2 = q[::-1], q2[::-1]
                m.f(q, I_CORPO)
                m.f(q2, I_PEITO)
            for borda in ((topo[i][0], topo[i + 1][0], fundo[i + 1][0], fundo[i][0]),
                          (topo[i][3], fundo[i][3], fundo[i + 1][3], topo[i + 1][3])):
                m.f(borda if sg > 0 else borda[::-1], I_CORPO)
        ombro_w = Vector((ombro.x, ombro.y * sg, ombro.z))
        # secundárias (braço): nascem atrás do osso e apontam para trás
        ns = P['secundarias']
        for k in range(ns):
            y = corte * (0.08 + 0.92 * k / (ns - 1))
            raiz = ombro_w + Vector((le(y) - 0.012 * s, y * sg, -0.0015 * s * (k % 2)))
            dd = Vector((-1.0, 0.10 * sg * (k / ns), -0.02))
            pena(m, raiz, dd, P['sec_comp'] * s * (0.92 + 0.08 * k / ns), P['sec_larg'] * s, peso_span(y), I_PENA, curva=0.12)
        # primárias (mão): leque do punho até a ponta, cada vez mais para fora; planador: longas e separadas (dedos)
        npr = P['primarias']
        for k in range(npr):
            t = k / (npr - 1)
            y = corte + (meia - corte) * (0.05 + 0.80 * t)
            raiz = ombro_w + Vector((le(y) - 0.006 * s, y * sg, -0.001 * s * (k % 2)))
            ang = (-1.05 + 0.75 * t ** 1.3)            # rad a partir de "para fora": de trás-fora (punho) a quase para fora (ponta)
            dd = Vector((math.sin(ang) * 1.0, math.cos(ang) * sg, -0.02))
            comp = (P['prim_comp'][0] + (P['prim_comp'][1] - P['prim_comp'][0]) * math.sin(t * PI * 0.6)) * s
            larg = P['prim_larg'] * s * (0.8 if P.get('dedos') and t > 0.3 else 1.0)
            pena(m, raiz, dd, comp, larg, {b2: 1.0}, I_PENA, curva=0.10 if not P.get('dedos') else 0.18,
                 assim=0.35, ponta_red=0.6 if P.get('dedos') else 1.0)
        # coberteiras: duas fileiras curtas por cima, cobrindo a raiz das grandes
        for fila, (frac, alt) in enumerate(() if JOGO_Q else ((0.55, 0.004), (0.30, 0.0065))):
            nc = int((ns + npr) * (0.75 if JOGO_Q else 1.3))
            for k in range(nc):
                y = meia * (0.04 + 0.86 * k / (nc - 1))
                raiz = ombro_w + Vector((le(y) + 0.002 * s, y * sg, alt * s))
                dd = Vector((-1.0, (0.3 if y > corte else 0.08) * sg, -0.05))
                pena(m, raiz, dd, corda * frac * (1 - 0.35 * max(0, y - corte) / meia), P['sec_larg'] * s * 1.1,
                     peso_span(y), I_PENA if fila == 0 else I_CORPO, curva=0.15)
        if P.get('lemes'):                         # o estranho do planador: duas asinhas atrás
            for k in range(4):
                raiz = Vector((-0.07 * s, (0.012 + 0.004 * k) * s * sg, h + 0.012 * s))
                pena(m, raiz, Vector((-0.35, (0.9 - 0.15 * k) * sg, 0.02)), (0.045 - 0.006 * k) * s, 0.010 * s,
                     {f'leme_{lado}': 1.0}, I_PENA, curva=0.1)

    me = bpy.data.meshes.new(nome + '_malha')
    pesos = [m.pesos.get(v, {'corpo': 1.0}) for v in m.bm.verts]
    m.bm.to_mesh(me)
    m.bm.free()
    for mt in MAT[especie] + [M_BICO[especie], M_OLHO, M_PE, M_CRISTA]:
        me.materials.append(mt)
    o = bpy.data.objects.new(nome + '_corpo', me)
    sc.collection.objects.link(o)
    grupos = {}
    for i, pw in enumerate(pesos):
        for n_, w in pw.items():
            if n_ not in grupos:
                grupos[n_] = o.vertex_groups.new(name=n_)
            grupos[n_].add([i], w, 'REPLACE')
    o.parent = arm
    md = o.modifiers.new('esqueleto', 'ARMATURE')
    md.object = arm
    arm['especie'] = especie
    arm['escala_p'] = s
    return arm


# ------------------------------------------------------------------ poses
def _o(arm, n):
    pb = arm.pose.bones[n]
    pb.rotation_mode = 'XYZ'
    return pb


def pose_zero(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)


def asa(arm, lado, levanta, dobra=0.0, varre=0.0, torce=0.0, ponta=0.0):
    """Ângulos (rad): levanta (+ = ponta para cima), dobra (+ = mão para trás), varre (+ = asa para trás), torce,
    ponta (a mão levanta a mais). Osso para −y: o x local aponta para trás, então levantar já é simétrico."""
    sg = 1 if lado == 'e' else -1
    _o(arm, f'asa_{lado}1').rotation_euler = (levanta, torce * sg, varre * sg)
    _o(arm, f'asa_{lado}2').rotation_euler = (ponta, 0.0, dobra * sg)


def pose_pousar(arm, u):
    """Pousando (u 0..1; ao contrário = decolando): chega freando — asas altas e para a frente batendo curto, corpo de
    bico para cima, cauda aberta e pernas esticadas para o chão — e, já no chão, fecha as asas sobre o dorso."""
    pose_zero(arm)
    k = max(0.0, min(1.0, (u - 0.55) / 0.45))
    k = k * k * (3 - 2 * k)                                    # 0 = freando no ar, 1 = asas fechadas
    bat = math.cos(2 * PI * u * 2.5) * (1 - k)
    enc = 0.42 if arm.get('especie') == 'planador' else 0.6
    for lado in 'ed':
        asa(arm, lado, (0.55 + 0.45 * bat) * (1 - k) - 0.10 * k, dobra=-0.62 * k, varre=-0.35 * (1 - k) + 1.5 * k,
            torce=0.35 * (1 - k), ponta=0.3 * (1 - k) - 0.05 * k)
        _o(arm, f'asa_{lado}1').scale = (1.0, 1.0 - (1.0 - enc) * k, 1.0)
        mao = (0.62 if arm.get('especie') == 'planador' else 1.0) / enc
        _o(arm, f'asa_{lado}2').scale = (1.0, 1.0 + (mao - 1.0) * k, 1.0)
    _o(arm, 'corpo').rotation_euler = (0.35 * (1 - k), 0, 0)    # positivo = bico para cima (x local do osso = −y)
    _o(arm, 'cauda').rotation_euler = (-0.3 * (1 - k), 0, 0)
    _o(arm, 'corpo').location = (0, 0, 0.04 * (1 - k) * arm.get('escala_p', 1.0))
    lemes(arm, 1.0 - k)


def pose_parado(arm, u=0.0):
    """Pousado, olhando em volta: a cabeça vira de um lado para o outro em sacudidas curtas (u 0..1 = um laço)."""
    pose_pousado(arm)
    olha = [0.0, 0.0, 0.5, 0.5, 0.5, -0.4, -0.4, 0.0][int(u * 8) % 8]
    _o(arm, 'cabeca').rotation_euler = (0.0, 0.0, olha)       # z local da cabeça ≈ para cima: vira o bico para os lados
    _o(arm, 'cauda').rotation_euler = (0.08 * math.sin(2 * PI * u * 2), 0.0, 0.0)


def pose_bicar(arm, u):
    """Bicando no chão (u 0..1): duas bicadas rápidas por laço."""
    k = max(0.0, math.sin(2 * PI * u * 2)) ** 0.6
    pose_pousado(arm, 0.35 + 0.65 * k)


def lemes(arm, abre):
    if 'leme_e' in arm.pose.bones:
        for lado, sg in (('e', 1), ('d', -1)):
            _o(arm, f'leme_{lado}').rotation_euler = (0.0, 0.0, (1.0 - abre) * 1.1 * sg)


def pose_voo(arm, u):
    """Batida (u 0..1): desce forte e esticada, sobe dobrando a mão para trás."""
    pose_zero(arm)
    c = math.cos(2 * PI * u)
    sobe = max(0.0, -math.sin(2 * PI * u))
    for lado in 'ed':
        asa(arm, lado, 0.8 * c, dobra=0.7 * sobe, varre=0.15 * sobe, torce=0.08 * c, ponta=0.25 * c)
    _o(arm, 'corpo').location = (0, 0, -0.015 * c)
    _o(arm, 'pernas').rotation_euler = (0.0, 0.0, 0.0)
    _o(arm, 'pernas').scale = (1, 0.35, 1)
    lemes(arm, 0.5)


def pose_planar(arm, u=0.0):
    pose_zero(arm)
    for lado in 'ed':
        asa(arm, lado, 0.06 + 0.03 * math.sin(2 * PI * u), varre=-0.04, ponta=0.10)
    _o(arm, 'pernas').scale = (1, 0.35, 1)
    lemes(arm, 1.0)


def pose_pousado(arm, bica=0.0):
    """Asa fechada sobre o dorso: o braço varre para trás e encolhe (as secundárias se encavalam, como na dobra de
    verdade) e a mão segue para trás, com as primárias até a ponta da cauda."""
    pose_zero(arm)
    enc = 0.42 if arm.get('especie') == 'planador' else 0.6
    for lado in 'ed':
        # a mão gira para dentro o quanto as primárias abrem (~0,6 rad): elas ficam deitadas, paralelas ao corpo
        asa(arm, lado, -0.10, dobra=-0.62, varre=1.50, torce=0.0, ponta=-0.05)
        _o(arm, f'asa_{lado}1').scale = (1.0, enc, 1.0)
        _o(arm, f'asa_{lado}2').scale = (1.0, (0.62 if arm.get('especie') == 'planador' else 1.0) / enc, 1.0)
    lemes(arm, 0.0)
    if bica > 0.0:
        _o(arm, 'corpo').rotation_euler = (-0.5 * bica, 0, 0)     # x local do osso = −y: negativo baixa o bico
        _o(arm, 'cabeca').rotation_euler = (-0.75 * bica, 0, 0)
        _o(arm, 'cauda').rotation_euler = (0.35 * bica, 0, 0)


# ------------------------------------------------------------------ cena
pardelos = {
    'voo': montar_passaro('pardelo_voo', 'pardelo', Vector((0, 0, 0.45)), 0.0),
    'planar': montar_passaro('pardelo_planar', 'pardelo', Vector((1.2, 0, 0.45)), 0.0),
    'pousado': montar_passaro('pardelo_pousado', 'pardelo', Vector((0, 0.9, 0)), 0.35),
    'bicando': montar_passaro('pardelo_bicando', 'pardelo', Vector((0.45, 0.95, 0)), 2.3),
}
planadores = {
    'voo': montar_passaro('planador_voo', 'planador', Vector((6, 0, 1.4)), 0.0),
    'planar': montar_passaro('planador_planar', 'planador', Vector((6, 2.4, 1.4)), 0.0),
    'pousado': montar_passaro('planador_pousado', 'planador', Vector((7.6, -1.8, 0.3)), 0.6),
}
coloridos = {}
for i, n in enumerate(('cobrico', 'azulao', 'rubro')):
    coloridos[n + '_pousado'] = montar_passaro(n + '_pousado', n, Vector((2.6 + i * 0.32, -1.0, 0)), 0.5 + i * 0.4)
    coloridos[n + '_voo'] = montar_passaro(n + '_voo', n, Vector((2.6 + i * 0.5, -0.2, 0.45)), 0.2)
    pose_pousado(coloridos[n + '_pousado'], 1.0 if n == 'rubro' else 0.0)
    pose_voo(coloridos[n + '_voo'], 0.1 + i * 0.3)
pose_voo(pardelos['voo'], 0.0)
pose_planar(pardelos['planar'])
pose_pousado(pardelos['pousado'])
pose_pousado(pardelos['bicando'], 1.0)
pose_voo(planadores['voo'], 0.2)
pose_planar(planadores['planar'])
pose_pousado(planadores['pousado'])

base3d.M['chao'] = plumagem_mat('Chao', (0.20, 0.17, 0.12), (0.08, 0.07, 0.05), escala=6, aspereza=0.95)
base3d.M['pedra'] = liso_mat('Pedra', (0.25, 0.24, 0.22), 0.85)
bm = bmesh.new()
base3d.caixa(bm, (3, 0, -0.05), (30, 20, 0.10))
base3d.obj('EFEITO_chao', bm, 'chao')
bm = bmesh.new()
base3d.pedra(bm, (7.6, -1.8, 0.12), 0.45, 0.6)
base3d.obj('EFEITO_pedra', bm, 'pedra')

sol = bpy.data.lights.new('Sol', 'SUN'); sol.energy = 4.0; sol.angle = math.radians(2.5)
so = bpy.data.objects.new('Sol', sol); sc.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(-35))
sol2 = bpy.data.lights.new('Sol2', 'SUN'); sol2.energy = 1.4
so2 = bpy.data.objects.new('Sol2', sol2); sc.collection.objects.link(so2); so2.rotation_euler = (math.radians(-30), 0, math.radians(140))
mundo = bpy.data.worlds.new('Mundo'); sc.world = mundo
bg = mundo.node_tree.nodes['Background']; bg.inputs['Color'].default_value = (0.45, 0.48, 0.58, 1); bg.inputs['Strength'].default_value = 0.7
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
cam_d = bpy.data.cameras.new('Cam'); cam = bpy.data.objects.new('Cam', cam_d); sc.collection.objects.link(cam); sc.camera = cam


def mirar(pos, alvo, lente):
    cam.location = pos
    cam.rotation_euler = (Vector(alvo) - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
    cam_d.lens = lente


modo = _ARGS[0] if _ARGS else 'foto'
for k, d in (('pardelo', pardelos), ('planador', planadores)):
    o = next(c for c in d['voo'].children if c.type == 'MESH')
    print(f'PASSARO {k} tris={sum(len(p.vertices) - 2 for p in o.data.polygons)}')
if modo == 'foto':
    sc.cycles.samples = 64
    sc.render.resolution_x, sc.render.resolution_y = 1000, 700
    fotos = [('passaro_pardelo_voo', (0.5, -0.65, 0.68), (0.0, 0, 0.48), 50),
             ('passaro_pardelo_planar', (1.2, -0.05, 1.25), (1.2, 0, 0.45), 45),
             ('passaro_pardelo_chao', (0.55, 0.35, 0.2), (0.22, 0.92, 0.06), 45),
             ('passaro_planador_voo', (7.3, -2.0, 2.4), (6.0, 0, 1.45), 45),
             ('passaro_planador_planar', (6.0, 2.5, 3.5), (6.0, 2.4, 1.4), 40),
             ('passaro_planador_pousado', (8.9, -3.0, 0.9), (7.6, -1.8, 0.45), 45),
             ('passaro_coloridos_chao', (3.0, -1.75, 0.28), (2.95, -1.0, 0.06), 40),
             ('passaro_coloridos_voo', (3.1, -1.25, 0.75), (3.1, -0.2, 0.45), 40)]
    for nome, pos, alvo, lente in fotos:
        mirar(pos, alvo, lente)
        sc.render.filepath = os.path.join(AQUI, nome + '.png')
        bpy.ops.render.render(write_still=True)
    sc.render.resolution_x, sc.render.resolution_y = 420, 320
    voo = pardelos['voo']
    for o in sc.objects:
        if o.type == 'MESH' and o.parent is not voo:
            o.hide_render = True
    mirar((0.75, -0.25, 0.52), (0.0, 0, 0.47), 50)
    for k in range(6):
        pose_voo(voo, k / 6)
        bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(AQUI, f'passaro_pardelo_batida_{k}.png')
        bpy.ops.render.render(write_still=True)
    print('PASSAROS ok')
