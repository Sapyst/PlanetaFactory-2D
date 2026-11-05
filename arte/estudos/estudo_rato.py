"""Estudo isolado (fora do jogo): ROEDORES do planeta (patch fauna, fase 5; pedido de Sapyst: ratos que vivem no mato
e nos arbustos, comem frutas e enterram sementes). Fauna nativa de um mundo alienígena, mas crível: anatomia de roedor
de verdade, com um detalhe estranho cada (como a crista óssea do pardelo).
  A) RATO-PARDO — roedor de mato (~0,15 m sem a cauda): dorso pardo-agouti, barriga creme, orelhas redondas, cauda
     pelada; o estranho: uma fileira de espinhos ósseos claros ao longo da espinha (o mesmo osso da crista do pardelo).
  B) SALTADOR — roedor de campo aberto (~0,12 m sem a cauda), anda aos pulos: pernas de trás longas, braços curtos,
     orelhas grandes, cauda longa com tufo escuro e ponta clara; o estranho: anel claro e largo em volta do olho.
MODELO: UMA malha só, deformada pelo esqueleto (corpo, peito, cabeça, cauda em 3, pernas em 2 ossos cada).
Poses: andar (passo), correr (galope ou pulo), farejar (parado), comer (sentado com o fruto nas mãos) e cavar.

Uso: blender -b --python estudo_rato.py -- foto
     blender -b --python estudo_rato.py -- nada
"""
import bpy, bmesh, math, os, sys, random
from mathutils import Vector, Matrix, Quaternion, noise

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import base3d

PI = math.pi
random.seed(31)
_ARGS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
JOGO_Q = 'jogo' in _ARGS

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = base3d.iniciar()


# ------------------------------------------------------------------ materiais
def pelo_mat(nome, claro, escuro, escala=900.0, aspereza=0.78):
    """Pelo curto: pontinhos finos entre o claro e o escuro (agouti, cada pelo com a ponta de outra cor), fosco."""
    m = bpy.data.materials.new(nome)
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = escala; nz.inputs['Detail'].default_value = 8.0
    nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    rp = nt.nodes.new('ShaderNodeValToRGB')
    rp.color_ramp.elements[0].position = 0.42; rp.color_ramp.elements[0].color = (*escuro, 1)
    rp.color_ramp.elements[1].position = 0.58; rp.color_ramp.elements[1].color = (*claro, 1)
    nt.links.new(nz.outputs['Fac'], rp.inputs['Fac'])
    nt.links.new(rp.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = aspereza
    b.inputs['Sheen Weight'].default_value = 0.4
    return m


def liso_mat(nome, cor, aspereza=0.5, brilho=0.0):
    m = bpy.data.materials.new(nome)
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*cor, 1)
    b.inputs['Roughness'].default_value = aspereza
    b.inputs['Coat Weight'].default_value = brilho
    return m


ESPECIES = {
    # corpo: seções (x, meia largura, meia altura, z do centro) em m, da anca ao focinho
    'pardo': dict(
        dorso=((0.085, 0.06, 0.035), (0.03, 0.022, 0.015)), barriga=((0.30, 0.25, 0.18), (0.18, 0.14, 0.10)),
        pele=(0.25, 0.16, 0.14), espinho=(0.62, 0.56, 0.44),
        secs=[(-0.078, 0.008, 0.008, 0.040), (-0.070, 0.022, 0.021, 0.042), (-0.050, 0.031, 0.029, 0.045),
              (-0.020, 0.033, 0.031, 0.046), (0.010, 0.029, 0.027, 0.046), (0.032, 0.021, 0.021, 0.046),
              (0.047, 0.019, 0.019, 0.048), (0.062, 0.018, 0.017, 0.047), (0.076, 0.012, 0.011, 0.043),
              (0.086, 0.007, 0.006, 0.040), (0.092, 0.002, 0.002, 0.039)],
        anca=(-0.045, 0.022, 0.043), ombro=(0.022, 0.016, 0.040),
        coxa=0.030, canela=0.026, pe=0.022, braco=0.020, mao=0.014, r_coxa=0.014, r_braco=0.0065,
        orelha=(0.052, 0.014, 0.060, 0.010), olho=(0.068, 0.0125, 0.052, 0.0042), anel=0.0,
        cauda=(0.14, 0.0055), tufo=None, espinhos=True),
    'saltador': dict(
        dorso=((0.24, 0.17, 0.09), (0.10, 0.07, 0.04)), barriga=((0.55, 0.50, 0.42), (0.38, 0.34, 0.28)),
        pele=(0.32, 0.22, 0.18), espinho=None,
        secs=[(-0.060, 0.008, 0.008, 0.052), (-0.052, 0.022, 0.022, 0.054), (-0.035, 0.030, 0.030, 0.058),
              (-0.010, 0.028, 0.028, 0.062), (0.012, 0.022, 0.022, 0.066), (0.028, 0.018, 0.018, 0.070),
              (0.042, 0.019, 0.019, 0.076), (0.056, 0.018, 0.017, 0.076), (0.068, 0.012, 0.011, 0.072),
              (0.077, 0.007, 0.006, 0.069), (0.082, 0.002, 0.002, 0.068)],
        anca=(-0.032, 0.022, 0.052), ombro=(0.020, 0.014, 0.060),
        coxa=0.040, canela=0.040, pe=0.036, braco=0.018, mao=0.011, r_coxa=0.017, r_braco=0.0045,
        orelha=(0.044, 0.013, 0.092, 0.017), olho=(0.058, 0.0135, 0.081, 0.0055), anel=0.0028,
        cauda=(0.17, 0.0045), tufo=((0.06, 0.05, 0.04), (0.85, 0.82, 0.75)), espinhos=False),
}
MAT = {}
for _n, P_ in ESPECIES.items():
    MAT[_n] = [pelo_mat(_n + 'Dorso', *P_['dorso']), pelo_mat(_n + 'Barriga', *P_['barriga'], escala=700),
               liso_mat(_n + 'Pele', P_['pele'], 0.55), liso_mat('Olho', (0.008, 0.008, 0.008), 0.08, 1.0),
               liso_mat(_n + 'Osso', P_['espinho'] or (0.7, 0.66, 0.56), 0.45, 0.15),
               pelo_mat(_n + 'Tufo', *(P_['tufo'] or ((0.1, 0.1, 0.1), (0.8, 0.8, 0.8))), escala=20),
               liso_mat(_n + 'Anel', P_['barriga'][0], 0.7)]
I_DORSO, I_BARRIGA, I_PELE, I_OLHO, I_OSSO, I_TUFO, I_ANEL = range(7)


# ------------------------------------------------------------------ montagem: uma malha, pesos por regra
class Malha:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap')
        self.pesos = {}

    def v(self, co, pesos):
        vv = self.bm.verts.new(co)
        self.pesos[vv] = pesos
        return vv

    def f(self, vs, mat):
        try:
            fa = self.bm.faces.new(vs)
        except ValueError:
            return None
        fa.material_index = mat
        fa.smooth = True
        return fa


def mistura(a, b, t):
    t = max(0.0, min(1.0, t))
    t = t * t * (3 - 2 * t)
    if t <= 0.0:
        return {a: 1.0}
    if t >= 1.0:
        return {b: 1.0}
    return {a: 1.0 - t, b: t}


def tubo(m, pts, raios, pesos_de, mat, lados=6, fecha=True):
    """Tubo por uma linha de pontos, raio por ponto; `pesos_de(i)` dá os pesos de cada anel."""
    aneis = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        u = d.cross(Vector((0, 0, 1)))
        if u.length < 1e-4:
            u = d.cross(Vector((0, 1, 0)))
        u.normalize()
        w = d.cross(u).normalized()
        aneis.append([m.v(p + (u * math.cos(2 * PI * k / lados) + w * math.sin(2 * PI * k / lados)) * raios[i], pesos_de(i))
                      for k in range(lados)])
    for a, b in zip(aneis, aneis[1:]):
        for k in range(lados):
            j = (k + 1) % lados
            m.f((a[k], a[j], b[j], b[k]), mat)
    if fecha:
        for anel, inv, p, i in ((aneis[0], True, pts[0], 0), (aneis[-1], False, pts[-1], len(pts) - 1)):
            c = m.v(p, pesos_de(i))
            for k in range(lados):
                j = (k + 1) % lados
                m.f((anel[j], anel[k], c) if inv else (anel[k], anel[j], c), mat)
    return aneis


def montar_rato(nome, especie, origem=Vector((0, 0, 0)), giro=0.0):
    P = ESPECIES[especie]
    arm_d = bpy.data.armatures.new(nome + '_esqueleto')
    arm = bpy.data.objects.new(nome, arm_d)
    sc.collection.objects.link(arm)
    arm.location = origem
    arm.rotation_euler = (0, 0, giro)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    secs = P['secs']
    z_meio = secs[3][3]

    def osso(n, a, b, pai=None):
        e = arm_d.edit_bones.new(n)
        e.head, e.tail, e.roll = Vector(a), Vector(b), 0.0
        if pai:
            e.parent = arm_d.edit_bones[pai]
    anca, ombro = Vector(P['anca']), Vector(P['ombro'])
    osso('corpo', (anca.x, 0, z_meio), (0.0, 0, z_meio))
    osso('peito', (0.0, 0, z_meio), (ombro.x + 0.012, 0, secs[5][3]), 'corpo')
    osso('cabeca', (secs[5][0], 0, secs[6][3]), (secs[-1][0], 0, secs[-1][3]), 'peito')
    cauda0 = Vector((secs[0][0], 0, secs[0][3]))
    cl, cr = P['cauda']
    osso('cauda1', cauda0, cauda0 + Vector((-cl / 3, 0, -0.02)), 'corpo')
    osso('cauda2', cauda0 + Vector((-cl / 3, 0, -0.02)), cauda0 + Vector((-2 * cl / 3, 0, -0.035)), 'cauda1')
    osso('cauda3', cauda0 + Vector((-2 * cl / 3, 0, -0.035)), cauda0 + Vector((-cl, 0, -0.04)), 'cauda2')
    pernas = {}
    for lado, sg in (('e', 1), ('d', -1)):
        a = Vector((anca.x, anca.y * sg, anca.z))
        joelho = a + Vector((P['coxa'] * 0.55, 0.006 * sg, -P['coxa'] * 0.75))
        tornozelo = joelho + Vector((-P['canela'] * 0.75, 0, -P['canela'] * 0.55))
        tornozelo.z = max(tornozelo.z, 0.006)
        dedo = Vector((tornozelo.x + P['pe'], tornozelo.y, 0.002))
        osso(f'coxa_{lado}', a, joelho, 'corpo')
        osso(f'canela_{lado}', joelho, tornozelo, f'coxa_{lado}')
        osso(f'pe_{lado}', tornozelo, dedo, f'canela_{lado}')
        o = Vector((ombro.x, ombro.y * sg, ombro.z))
        cotovelo = o + Vector((-0.004, 0.003 * sg, -P['braco'] * 0.95))
        pulso = Vector((cotovelo.x + P['mao'] * 0.3, cotovelo.y, 0.004))
        mao = pulso + Vector((P['mao'] * 0.6, 0, -0.002))
        osso(f'braco_{lado}', o, cotovelo, 'peito')
        osso(f'mao_{lado}', cotovelo, mao, f'braco_{lado}')
        pernas[lado] = (a, joelho, tornozelo, dedo, o, cotovelo, pulso, mao)
    bpy.ops.object.mode_set(mode='OBJECT')

    m = Malha()
    LADOS = 8 if JOGO_Q else 16
    aneis = []
    for k, (x, ry, rz, z) in enumerate(secs):
        if x < 0.0:
            pz = mistura('corpo', 'corpo', 0)
            if x < secs[1][0] + 0.004:
                pz = mistura('cauda1', 'corpo', (x - secs[0][0]) / 0.01)
        elif x < secs[5][0]:
            pz = mistura('corpo', 'peito', x / 0.02)
        else:
            pz = mistura('peito', 'cabeca', (x - secs[5][0]) / 0.015)
        anel = []
        for i in range(LADOS):
            a = 2 * PI * i / LADOS
            ca, sa = math.cos(a), math.sin(a)
            co = Vector((x, ry * ca, z + rz * sa))
            co += Vector((noise.noise(co * 200), noise.noise(co * 200 + Vector((3, 1, 2)))
                          , noise.noise(co * 200 + Vector((7, 2, 5))))) * 0.0006
            anel.append(m.v(co, pz))
        aneis.append(anel)
    for k, (a, b) in enumerate(zip(aneis, aneis[1:])):
        for i in range(LADOS):
            j = (i + 1) % LADOS
            sa = math.sin(2 * PI * (i + 0.5) / LADOS)
            m.f((a[i], a[j], b[j], b[i]), I_BARRIGA if sa < -0.35 else I_DORSO)
    for anel, inv in ((aneis[0], True), (aneis[-1], False)):
        c = m.v(sum((v.co for v in anel), Vector()) / LADOS, m.pesos[anel[0]])
        for i in range(LADOS):
            j = (i + 1) % LADOS
            m.f((anel[j], anel[i], c) if inv else (anel[i], anel[j], c), I_PELE if not inv else I_DORSO)
    cab = {'cabeca': 1.0}
    # orelhas: concha redonda (leque de triângulos com a borda virada para a frente), dos dois lados
    ox, oy, oz, orr = P['orelha']
    for sg in (1, -1):
        c0 = Vector((ox, oy * sg, oz))
        n_ = Vector((0.75, 0.55 * sg, 0.1)).normalized()
        u = Vector((0, 0, 1)).cross(n_).normalized()
        w = n_.cross(u).normalized()
        borda = []
        for k in range(10):
            a = 2 * PI * k / 10
            p = c0 + (u * math.cos(a) * 0.8 + w * (math.sin(a) + 0.35)) * orr + n_ * 0.003 * (1 - math.sin(a))
            borda.append(m.v(p, cab))
        cc = m.v(c0 + w * 0.25 * orr - n_ * 0.003, cab)
        for k in range(10):
            j = (k + 1) % 10
            m.f((borda[k], borda[j], cc), I_PELE)
            m.f((borda[j], borda[k], cc), I_DORSO)
    # olhos (e o anel claro do saltador)
    ex, ey, ez, er = P['olho']
    for sg in (1, -1):
        if P['anel'] > 0:
            res = bmesh.ops.create_uvsphere(m.bm, u_segments=8, v_segments=5, radius=er + P['anel'])
            for vv in res['verts']:
                vv.co = vv.co * Vector((0.6, 0.35, 1.0)) + Vector((ex - 0.001, (ey - 0.0005) * sg, ez))
                m.pesos[vv] = cab
            for fa in {f for vv in res['verts'] for f in vv.link_faces}:
                fa.material_index = I_ANEL
        res = bmesh.ops.create_uvsphere(m.bm, u_segments=8, v_segments=6, radius=er)
        for vv in res['verts']:
            vv.co += Vector((ex, ey * sg, ez))
            m.pesos[vv] = cab
        for fa in {f for vv in res['verts'] for f in vv.link_faces}:
            fa.material_index = I_OLHO
    # pernas: tubos com o peso do osso de cada trecho
    for lado, sg in (('e', 1), ('d', -1)):
        a, joelho, tornozelo, dedo, o, cotovelo, pulso, mao = pernas[lado]
        coxa_pts = [a + Vector((0, -0.004 * sg, 0.004)), (a + joelho) / 2, joelho]
        tubo(m, coxa_pts, [P['r_coxa'], P['r_coxa'] * 0.85, P['r_coxa'] * 0.45],
             lambda i: {f'coxa_{lado}': 1.0} if i < 2 else mistura(f'coxa_{lado}', f'canela_{lado}', 0.5), I_DORSO, 6)
        tubo(m, [joelho, tornozelo, dedo], [P['r_coxa'] * 0.42, P['r_coxa'] * 0.3, P['r_coxa'] * 0.2],
             lambda i: [{f'canela_{lado}': 1.0}, mistura(f'canela_{lado}', f'pe_{lado}', 0.5), {f'pe_{lado}': 1.0}][i], I_PELE, 5)
        tubo(m, [o, cotovelo], [P['r_braco'], P['r_braco'] * 0.7],
             lambda i: {f'braco_{lado}': 1.0}, I_DORSO, 5)
        tubo(m, [cotovelo, pulso, mao], [P['r_braco'] * 0.6, P['r_braco'] * 0.45, P['r_braco'] * 0.35],
             lambda i: {f'mao_{lado}': 1.0}, I_PELE, 5)
    # cauda: tubo afinando, deitada e um pouco em S; o saltador tem tufo no fim
    pts, raios = [], []
    for k in range(10):
        t = k / 9
        pts.append(cauda0 + Vector((-cl * t, 0.012 * math.sin(t * PI * 1.3), -0.04 * min(1.0, t * 1.8) + 0.004 * t)))
        raios.append(cr * (1.0 - 0.7 * t))
    tubo(m, pts, raios, lambda i: {['cauda1', 'cauda2', 'cauda3'][min(2, i * 3 // 10)]: 1.0}, I_PELE, 5)
    if P['tufo']:
        for k in range(9):
            t = 0.7 + 0.3 * k / 8
            base = cauda0 + Vector((-cl * t, 0.012 * math.sin(t * PI * 1.3), -0.04 + 0.004 * t))
            for a in range(4):
                ang = 2 * PI * a / 4 + k
                d = Vector((-0.6, math.cos(ang), math.sin(ang) * 0.7 + 0.2)).normalized() * (0.012 + 0.008 * (t - 0.7) / 0.3)
                v1 = m.v(base, {'cauda3': 1.0})
                v2 = m.v(base + d + Vector((0, 0, 0.002)), {'cauda3': 1.0})
                v3 = m.v(base + d * 0.9 + Vector((-0.004, 0, -0.002)), {'cauda3': 1.0})
                m.f((v1, v2, v3), I_TUFO)
                m.f((v1, v3, v2), I_TUFO)
    # o estranho do rato-pardo: espinhos ósseos claros na espinha
    if P['espinhos']:
        for k in range(9):
            x = -0.055 + 0.085 * k / 8
            zt = 0.0
            for (x0, ry0, rz0, z0), (x1, ry1, rz1, z1) in zip(secs, secs[1:]):
                if x0 <= x <= x1:
                    u = (x - x0) / (x1 - x0)
                    zt = (z0 + rz0) * (1 - u) + (z1 + rz1) * u
            h = 0.003 + 0.003 * math.sin(PI * k / 8)
            pz = {'corpo': 1.0} if x < 0.0 else mistura('corpo', 'peito', x / 0.02)
            b0 = [m.v(Vector((x + 0.003 * math.cos(a), 0.0025 * math.sin(a), zt - 0.001)), pz) for a in (0, 2.1, 4.2)]
            topo = m.v(Vector((x - 0.003, 0, zt + h)), pz)
            for i in range(3):
                m.f((b0[i], b0[(i + 1) % 3], topo), I_OSSO)

    me = bpy.data.meshes.new(nome + '_malha')
    pesos = [m.pesos.get(v, {'corpo': 1.0}) for v in m.bm.verts]
    m.bm.to_mesh(me)
    m.bm.free()
    for mt in MAT[especie]:
        me.materials.append(mt)
    o_ = bpy.data.objects.new(nome + '_corpo', me)
    sc.collection.objects.link(o_)
    grupos = {}
    for i, pw in enumerate(pesos):
        for n_, w in pw.items():
            if n_ not in grupos:
                grupos[n_] = o_.vertex_groups.new(name=n_)
            grupos[n_].add([i], w, 'REPLACE')
    o_.parent = arm
    md = o_.modifiers.new('esqueleto', 'ARMATURE')
    md.object = arm
    arm['especie'] = especie
    return arm


# ------------------------------------------------------------------ poses
def _o(arm, n):
    pb = arm.pose.bones[n]
    pb.rotation_mode = 'QUATERNION'
    return pb


def pose_zero(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)


def gira(arm, n, pitch=0.0, yaw=0.0, rola=0.0):
    """Gira o osso em volta dos eixos do bicho (não os do osso): pitch em volta do eixo do lado (+ = a ponta de um
    osso que vai para a frente desce; a de um osso que desce vai para trás), yaw em volta do eixo de cima (+ = para a
    esquerda), rola em volta do eixo da frente."""
    pb = _o(arm, n)
    inv = pb.bone.matrix_local.to_3x3().inverted()
    q = Quaternion(inv @ Vector((0, 0, 1)), yaw) @ Quaternion(inv @ Vector((0, 1, 0)), pitch) @ Quaternion(inv @ Vector((1, 0, 0)), rola)
    pb.rotation_quaternion = q


def pose_andar(arm, u):
    """Passo (u 0..1): pernas em diagonal (trás esquerda com frente direita), a cabeça balança pouco, a cauda arrasta."""
    pose_zero(arm)
    for lado, fase in (('e', 0.0), ('d', 0.5)):
        c = math.sin(2 * PI * (u + fase))
        gira(arm, f'coxa_{lado}', 0.4 * c)
        gira(arm, f'canela_{lado}', -0.35 * max(0.0, -c))
        gira(arm, f'braco_{lado}', -0.4 * c)
        gira(arm, f'mao_{lado}', 0.3 * max(0.0, c))
    gira(arm, 'cabeca', 0.05 * math.sin(4 * PI * u))
    gira(arm, 'cauda1', 0.0, 0.12 * math.sin(2 * PI * u))


def pose_correr(arm, u):
    """Galope (rato-pardo) ou pulo (saltador): as pernas de trás juntas empurram e as da frente pegam o chão."""
    pose_zero(arm)
    c = math.sin(2 * PI * u)
    salta = arm.get('especie') == 'saltador'
    for lado in 'ed':
        gira(arm, f'coxa_{lado}', (0.9 if salta else 0.6) * c)
        gira(arm, f'canela_{lado}', -0.6 * max(0.0, c))
        gira(arm, f'pe_{lado}', 0.5 * max(0.0, c))
        gira(arm, f'braco_{lado}', -0.7 * c if not salta else -0.5)
    gira(arm, 'corpo', 0.12 * c)
    _o(arm, 'corpo').location = (0, 0, (0.03 if salta else 0.008) * max(0.0, -c))   # z do osso ≈ para cima
    gira(arm, 'cauda1', -0.25 * c if salta else 0.0)


def pose_farejar(arm, u=0.0):
    """Parado, focinho para cima farejando, virado um pouco."""
    pose_zero(arm)
    gira(arm, 'peito', -0.12)
    gira(arm, 'cabeca', -0.25 + 0.06 * math.sin(2 * PI * u * 6), 0.25)


def pose_comer(arm, u=0.0):
    """Sentado nas ancas, o peito erguido e as mãos com o fruto junto ao focinho."""
    pose_zero(arm)
    gira(arm, 'corpo', -0.7)
    _o(arm, 'corpo').location = (0, 0, -0.016)        # as ancas descem até o chão
    gira(arm, 'cabeca', 0.75 + 0.05 * math.sin(2 * PI * u * 4))
    for lado in 'ed':
        gira(arm, f'coxa_{lado}', -0.2)                # a coxa vai para a frente (sentado)
        gira(arm, f'canela_{lado}', 1.1)
        gira(arm, f'pe_{lado}', 0.0)
        sg = 1 if lado == 'e' else -1
        gira(arm, f'braco_{lado}', -0.95)
        gira(arm, f'mao_{lado}', -0.6, -0.35 * sg)        # as duas mãos se encontram no fruto
    gira(arm, 'cauda1', 0.55)
    maos_no_focinho(arm)
    assentar(arm)


def _mundo_de(arm, osso, ponta=True):
    pb = arm.pose.bones[osso]
    return arm.matrix_world @ (pb.tail if ponta else pb.head)


def assentar(arm):
    """Desce (ou sobe) o corpo até o ponto mais baixo da malha deformada encostar no chão (z = 0)."""
    bpy.context.view_layer.update()
    corpo = next(c for c in arm.children if c.type == 'MESH')
    ev = corpo.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = ev.to_mesh()
    zmin = min((ev.matrix_world @ v.co).z for v in me.vertices)
    ev.to_mesh_clear()
    pb = _o(arm, 'corpo')
    pb.location = (pb.location[0], pb.location[1], pb.location[2] - (zmin - arm.location.z))
    bpy.context.view_layer.update()


def maos_no_focinho(arm):
    """Comendo: procura os ângulos do braço e do antebraço que põem as duas mãos logo abaixo do focinho."""
    if 'maos' in arm:                                      # já achou (as ações repetem a pose a cada quadro)
        b, mm = arm['maos']
        for lado in 'ed':
            sg = 1 if lado == 'e' else -1
            gira(arm, f'braco_{lado}', b)
            gira(arm, f'mao_{lado}', mm, -0.35 * sg)
        return
    bpy.context.view_layer.update()
    focinho = _mundo_de(arm, 'cabeca')
    frente = (arm.matrix_world.to_3x3() @ Vector((1, 0, 0))).normalized()
    alvo = focinho - Vector((0, 0, 0.012)) - frente * 0.006
    melhor = (1e9, 0.0, 0.0)
    for i in range(19):
        b = -2.2 + 0.14 * i
        for j in range(21):
            mm = -2.4 + 0.14 * j
            for lado in 'ed':
                sg = 1 if lado == 'e' else -1
                gira(arm, f'braco_{lado}', b)
                gira(arm, f'mao_{lado}', mm, -0.35 * sg)
            bpy.context.view_layer.update()
            d = (_mundo_de(arm, 'mao_e') - alvo).length + (_mundo_de(arm, 'mao_d') - alvo).length
            if d < melhor[0]:
                melhor = (d, b, mm)
    for lado in 'ed':
        sg = 1 if lado == 'e' else -1
        gira(arm, f'braco_{lado}', melhor[1])
        gira(arm, f'mao_{lado}', melhor[2], -0.35 * sg)
    bpy.context.view_layer.update()
    arm['maos'] = (melhor[1], melhor[2])
    return melhor


def pose_morto(arm):
    """Morto: deitado de lado, as pernas meio esticadas e duras, a cauda solta no chão."""
    pose_zero(arm)
    gira(arm, 'corpo', 0.0, 0.0, PI / 2 * 0.92)
    for lado, sg in (('e', 1), ('d', -1)):
        gira(arm, f'coxa_{lado}', -0.5 * sg)
        gira(arm, f'canela_{lado}', 0.3)
        gira(arm, f'braco_{lado}', -0.6)
        gira(arm, f'mao_{lado}', 0.4)
    gira(arm, 'cabeca', 0.25)
    gira(arm, 'cauda1', 0.0, 0.3)
    gira(arm, 'cauda2', 0.0, -0.4)
    assentar(arm)


def pose_cavar(arm, u):
    """Cavando (enterrar a semente): focinho baixo, as mãos raspam o chão para trás, depressa."""
    pose_zero(arm)
    gira(arm, 'peito', 0.2)
    gira(arm, 'cabeca', 0.2)
    for lado, fase in (('e', 0.0), ('d', 0.5)):
        c = math.sin(2 * PI * (u * 3 + fase))
        gira(arm, f'braco_{lado}', -0.2 + 0.6 * c)
        gira(arm, f'mao_{lado}', 0.4 * max(0.0, c))


# ------------------------------------------------------------------ cena
ratos = {}
for k, esp in enumerate(('pardo', 'saltador')):
    y = k * 0.5
    ratos[esp] = {
        'andar': montar_rato(f'{esp}_andar', esp, Vector((0, y, 0)), 0.0),
        'comer': montar_rato(f'{esp}_comer', esp, Vector((0.32, y + 0.04, 0)), 2.4),
        'correr': montar_rato(f'{esp}_correr', esp, Vector((-0.34, y - 0.02, 0)), -0.4),
        'morto': montar_rato(f'{esp}_morto', esp, Vector((0.25, y - 0.25, 0)), 0.8),
    }
    pose_andar(ratos[esp]['andar'], 0.2)
    pose_comer(ratos[esp]['comer'])
    pose_correr(ratos[esp]['correr'], 0.75)
    pose_morto(ratos[esp]['morto'])

base3d.M['chao'] = pelo_mat('Chao', (0.20, 0.17, 0.12), (0.08, 0.07, 0.05), escala=6, aspereza=0.95)
base3d.M['bolota'] = liso_mat('Bolota', (0.42, 0.28, 0.10), 0.45, 0.2)
base3d.M['grama'] = liso_mat('Grama', (0.12, 0.22, 0.05), 0.7)
bm = bmesh.new()
base3d.caixa(bm, (0, 0.25, -0.05), (6, 4, 0.10))
base3d.obj('EFEITO_chao', bm, 'chao')
bpy.context.view_layer.update()
for k in range(2):                                     # a bolota nas mãos de quem come
    arm = ratos[('pardo', 'saltador')[k]]['comer']
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=7, radius=0.011)
    for vv in bm.verts:
        vv.co = vv.co * Vector((1.0, 1.0, 1.3))
    o = base3d.obj(f'EFEITO_bolota_{k}', bm, 'bolota')
    hc = arm.matrix_world @ arm.pose.bones['mao_e'].tail
    o.location = arm.matrix_world @ (arm.pose.bones['mao_e'].tail * 0.5 + arm.pose.bones['mao_d'].tail * 0.5)
# capim de escala (tufos de ~25 cm, como no jogo)
bm = bmesh.new()
for t in range(14):
    c = Vector((random.uniform(-0.6, 0.7), random.uniform(-0.3, 0.9), 0))
    if abs(c.x) < 0.45 and -0.15 < c.y < 0.65:
        continue
    for f_ in range(5):
        a = random.uniform(0, 2 * PI)
        b = c + Vector((math.cos(a), math.sin(a), 0)) * 0.01
        h = random.uniform(0.18, 0.3)
        lado = Vector((-math.sin(a), math.cos(a), 0)) * 0.006
        topo = b + Vector((math.cos(a) * 0.05, math.sin(a) * 0.05, h))
        vs = [bm.verts.new(b - lado), bm.verts.new(b + lado), bm.verts.new(topo)]
        bm.faces.new(vs)
base3d.obj('EFEITO_capim', bm, 'grama')

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
for esp, d in ratos.items():
    o = next(c for c in d['andar'].children if c.type == 'MESH')
    print(f'RATO {esp} tris={sum(len(p.vertices) - 2 for p in o.data.polygons)}')
if modo == 'foto':
    sc.cycles.samples = 64
    sc.render.resolution_x, sc.render.resolution_y = 1000, 700
    for esp, y in (('pardo', 0.0), ('saltador', 0.5)):
        cm = ratos[esp]['comer']
        bpy.context.view_layer.update()
        cabeca = cm.matrix_world @ cm.pose.bones['cabeca'].head
        frente = cm.matrix_world.to_3x3() @ Vector((1, 0, 0))
        lado_c = cabeca + frente * 0.25 + frente.cross(Vector((0, 0, 1))) * 0.2 + Vector((0, 0, 0.03))
        for nome, pos, alvo, lente in ((f'rato_{esp}_lado', (0.0, y - 0.55, 0.12), (0.0, y, 0.05), 60),
                                       (f'rato_{esp}_jogo', (0.55, y - 0.6, 0.62), (0.0, y, 0.04), 45),
                                       (f'rato_{esp}_comer', tuple(lado_c), tuple(cabeca - Vector((0, 0, 0.02))), 60),
                                       (f'rato_{esp}_morto', (0.45, y - 0.55, 0.22), (0.25, y - 0.25, 0.02), 60)):
            mirar(pos, alvo, lente)
            sc.render.filepath = os.path.join(AQUI, nome + '.png')
            bpy.ops.render.render(write_still=True)
    mirar((0.0, -1.2, 0.9), (0.0, 0.25, 0.04), 40)
    sc.render.filepath = os.path.join(AQUI, 'rato_escala.png')
    bpy.ops.render.render(write_still=True)
    print('RATOS ok')
