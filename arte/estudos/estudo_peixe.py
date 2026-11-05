"""Estudo isolado (fora do jogo): PEIXE dos lagos do planeta (patch fauna, fase 9; pedido de Sapyst: peixes que pulam
nos lagos e, na água poluída, aparecem mortos boiando). Fauna nativa, mas crível: um peixe de verdade (~0,35 m,
fusiforme), com o detalhe estranho de osso do resto da fauna nativa.
  A) COURAÇA — dorso oliva, flancos prateados, barriga clara; o estranho: a cabeça coberta por placas ósseas (uma placa
     no alto da cabeça e uma em cada bochecha/opérculo, com a costura de pele entre elas), cor de osso.
  B) COURAÇA-RUBRA — a mesma forma, com as nadadeiras avermelhadas.
MODELO: UMA malha só, deformada pelo esqueleto: corpo (cabeça e frente), coluna em 3 e cauda (a nadadeira). Olha para
+X; 1 unidade = 1 m; o ponto mais baixo encosta em z = 0 (o gerador de sprites corta abaixo de z = 0).
AÇÕES: nadar (onda que corre da cabeça para a cauda), pulo (o corpo arqueia e desarqueia; o jogo leva o peixe no arco do
salto), morto (barriga para cima, duro; vai boiar).

Uso: blender -b --python estudo_peixe.py -- foto [saida=<pasta>]
     blender -b --python estudo_peixe.py -- conferir [jogo]
     blender -b --python estudo_peixe.py -- nada [jogo]
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix, Quaternion, noise
from mathutils.bvhtree import BVHTree

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import base3d

PI = math.pi
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


# ------------------------------------------------------------------ materiais
def escamas_mat(nome, dorso, flanco, barriga):
    """Pele do peixe: a cor sai do atributo 'zona' (R: 0 = dorso, 0,5 = flanco, 1 = barriga), com um pontilhado escuro
    fino no dorso e um brilho prateado leve (assado como cor: o jogo usa só a textura)."""
    m = bpy.data.materials.new(nome)
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    at = nt.nodes.new('ShaderNodeAttribute')
    at.attribute_name = 'zona'
    sep = nt.nodes.new('ShaderNodeSeparateColor')
    nt.links.new(at.outputs['Color'], sep.inputs[0])
    rp = nt.nodes.new('ShaderNodeValToRGB')
    el = rp.color_ramp.elements
    el[0].position, el[0].color = 0.08, (*dorso, 1)
    el[1].position, el[1].color = 0.55, (*flanco, 1)
    e3 = el.new(0.9)
    e3.color = (*barriga, 1)
    nt.links.new(sep.outputs[0], rp.inputs['Fac'])
    tc = nt.nodes.new('ShaderNodeTexCoord')
    vo = nt.nodes.new('ShaderNodeTexVoronoi')
    vo.inputs['Scale'].default_value = 140.0
    nt.links.new(tc.outputs['Object'], vo.inputs['Vector'])
    mr = nt.nodes.new('ShaderNodeMapRange')
    mr.inputs['From Min'].default_value = 0.0
    mr.inputs['From Max'].default_value = 0.5
    mr.inputs['To Min'].default_value = 0.8
    mr.inputs['To Max'].default_value = 1.05
    nt.links.new(vo.outputs['Distance'], mr.inputs['Value'])
    mx = nt.nodes.new('ShaderNodeMix')
    mx.data_type = 'RGBA'
    mx.blend_type = 'MULTIPLY'
    mx.inputs[0].default_value = 1.0
    nt.links.new(rp.outputs['Color'], mx.inputs[6])
    nt.links.new(mr.outputs['Result'], mx.inputs[7])
    nt.links.new(mx.outputs[2], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.35
    b.inputs['Coat Weight'].default_value = 0.3
    m.diffuse_color = (*flanco, 1)
    return m


def liso_mat(nome, cor, aspereza=0.5, brilho=0.0):
    m = bpy.data.materials.new(nome)
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (*cor, 1)
    b.inputs['Roughness'].default_value = aspereza
    b.inputs['Coat Weight'].default_value = brilho
    m.diffuse_color = (*cor, 1)
    return m


ESPECIES = {
    'couraca': dict(nome='Couraça', nadadeira=(0.16, 0.17, 0.10)),
    'couraca_rubra': dict(nome='Couraça-rubra', nadadeira=(0.42, 0.075, 0.035)),
}
PELE = escamas_mat('PeixePele', (0.075, 0.09, 0.03), (0.50, 0.52, 0.52), (0.78, 0.77, 0.72))
MAT = {e: [PELE, liso_mat(e + 'Nadadeira', P['nadadeira'], 0.55), liso_mat('PeixeOlho', (0.01, 0.01, 0.01), 0.1, 1.0),
           liso_mat('PeixeOsso', OSSO_COR, 0.45, 0.2), liso_mat('PeixeIris', (0.45, 0.36, 0.12), 0.4, 0.5)]
       for e, P in ESPECIES.items()}
for _e in MAT:
    MAT[_e][1].use_backface_culling = False
I_PELE, I_NAD, I_OLHO, I_OSSO, I_IRIS = range(5)
P_CORPO, P_NAD, P_OSSO, P_OLHO = 1, 2, 3, 4

# corpo: seções (x, meia-largura, meia-altura em cima, meia-altura embaixo, z do centro) do focinho à cauda
SECOES = [(0.150, 0.004, 0.004, 0.004, -0.004), (0.141, 0.015, 0.017, 0.015, -0.003), (0.122, 0.024, 0.029, 0.025, 0.0),
          (0.097, 0.029, 0.037, 0.031, 0.002), (0.062, 0.031, 0.042, 0.035, 0.004), (0.022, 0.029, 0.040, 0.033, 0.004),
          (-0.020, 0.025, 0.034, 0.028, 0.003), (-0.060, 0.019, 0.025, 0.020, 0.002), (-0.095, 0.012, 0.016, 0.013, 0.001),
          (-0.122, 0.0075, 0.0095, 0.0085, 0.0), (-0.135, 0.006, 0.011, 0.011, 0.0)]
H0 = 0.05            # altura do eixo na montagem (depois tudo desce até o ponto mais baixo encostar em z = 0)
OSSOS = [('corpo', 0.03, 0.12, None), ('coluna1', 0.03, -0.035, 'corpo'), ('coluna2', -0.035, -0.085, 'coluna1'),
         ('coluna3', -0.085, -0.128, 'coluna2'), ('cauda', -0.128, -0.20, 'coluna3')]


def pesos_x(x):
    """Pesos ao longo do corpo: cada trecho no seu osso, misturando perto das juntas."""
    for (n, a, b, pai), (n2, a2, b2, _) in zip(OSSOS, OSSOS[1:]):
        if x > b - 0.012:
            if n == 'corpo':
                return mistura('coluna1', 'corpo', (x - (a - 0.015)) / 0.03)
            return mistura(n2, n, (x - (b - 0.012)) / 0.024)
    return {'cauda': 1.0}


class Malha:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new('UVMap')
        self.lparte = self.bm.faces.layers.int.new('parte')
        self.pesos, self.zona = {}, {}

    def v(self, co, pesos, zona=0.5):
        vv = self.bm.verts.new(co)
        self.pesos[vv] = pesos
        self.zona[vv] = zona
        return vv

    def f(self, vs, mat, parte):
        try:
            fa = self.bm.faces.new(vs)
        except ValueError:
            return None
        fa.material_index = mat
        fa.smooth = True
        fa[self.lparte] = parte
        return fa


def nadadeira(m, pts, pesos_de, zona=0.5):
    """Nadadeira fina (uma face dos dois lados, sem espessura: o material não esconde o verso)."""
    vs = [m.v(p, pesos_de(p), zona) for p in pts]
    for i in range(1, len(vs) - 1):
        m.f((vs[0], vs[i], vs[i + 1]), I_NAD, P_NAD)
    return vs


def montar(nome, especie, origem=Vector((0, 0, 0)), giro=0.0):
    arm_d = bpy.data.armatures.new(nome + '_esqueleto')
    arm = bpy.data.objects.new(nome, arm_d)
    sc.collection.objects.link(arm)
    arm.location = origem
    arm.rotation_euler = (0, 0, giro)
    bpy.context.view_layer.objects.active = arm
    m = Malha()
    L = 8 if JOGO_Q else 16
    aneis = []
    for k, (x, ry, ru, rd, dz) in enumerate(SECOES):
        anel = []
        for i in range(L):
            a = 2 * PI * i / L
            ca, sa = math.cos(a), math.sin(a)
            r = ru if sa >= 0 else rd
            p = Vector((x, ry * ca, H0 + dz + r * sa))
            anel.append(m.v(p, pesos_x(x), 0.5 - 0.5 * sa))
        aneis.append(anel)
    for a, b in zip(aneis, aneis[1:]):
        for i in range(L):
            j = (i + 1) % L
            m.f((a[i], a[j], b[j], b[i]), I_PELE, P_CORPO)
    c0 = m.v(Vector((SECOES[0][0] + 0.003, 0, H0 + SECOES[0][4])), pesos_x(0.15), 0.5)
    for i in range(L):
        m.f((aneis[0][(i + 1) % L], aneis[0][i], c0), I_PELE, P_CORPO)
    cf = m.v(Vector((SECOES[-1][0] - 0.004, 0, H0)), {'cauda': 1.0}, 0.5)
    for i in range(L):
        m.f((aneis[-1][i], aneis[-1][(i + 1) % L], cf), I_PELE, P_CORPO)
    # couraça: placas ósseas sobre a cabeça (uma no alto e uma em cada opérculo), com a costura de pele entre elas
    for (a0, a1, sec0, sec1, esp, na) in ((0.62, 2.52, 1, 4, 0.0018, 4), (-0.70, 0.40, 2, 4, 0.0016, 3),
                                          (2.74, 3.84, 2, 4, 0.0016, 3)):
        n_a = na if JOGO_Q else 2 * na
        cima, base = [], []
        for k in range(sec0, sec1 + 1):
            x, ry, ru, rd, dz = SECOES[k]
            if k == sec1:
                x += 0.004
            lin_c, lin_b = [], []
            for j in range(n_a + 1):
                a = a0 + (a1 - a0) * j / n_a
                ca, sa = math.cos(a), math.sin(a)
                r = ru if sa >= 0 else rd
                p = Vector((x, ry * ca, H0 + dz + r * sa))
                nrm = Vector((0, ry * ca, r * sa)).normalized()
                lin_c.append(m.v(p + nrm * esp, pesos_x(x), 0.5))
                lin_b.append(m.v(p - nrm * 0.0015, pesos_x(x), 0.5))
            cima.append(lin_c)
            base.append(lin_b)
        for i in range(len(cima) - 1):
            for j in range(n_a):
                m.f((cima[i][j], cima[i + 1][j], cima[i + 1][j + 1], cima[i][j + 1]), I_OSSO, P_OSSO)
        bordas = [[c[0] for c in cima], [c[-1] for c in cima], cima[0], cima[-1]]
        bbase = [[c[0] for c in base], [c[-1] for c in base], base[0], base[-1]]
        for bc, bb in zip(bordas, bbase):
            for i in range(len(bc) - 1):
                m.f((bc[i], bb[i], bb[i + 1], bc[i + 1]), I_OSSO, P_OSSO)
    # olhos: um disco claro (íris) rente à pele e o olho escuro por cima, logo acima da linha da boca
    for sg in (1, -1):
        c = Vector((0.118, 0.0238 * sg, H0 + 0.012))
        nrm = Vector((0.15, sg, 0.1)).normalized()
        u_ = nrm.cross(Z).normalized()
        w_ = nrm.cross(u_).normalized()
        cc = m.v(c + nrm * 0.0012, {'corpo': 1.0})
        bord = [m.v(c + (u_ * math.cos(2 * PI * k / 6) + w_ * math.sin(2 * PI * k / 6)) * 0.0072 + nrm * 0.0004,
                    {'corpo': 1.0}) for k in range(6)]
        for k in range(6):
            m.f((bord[k], bord[(k + 1) % 6], cc), I_IRIS, P_OLHO)
        res = bmesh.ops.create_uvsphere(m.bm, u_segments=6 if JOGO_Q else 12, v_segments=3 if JOGO_Q else 8, radius=0.0052)
        for vv in res['verts']:
            vv.co = Vector((vv.co.x, vv.co.y * 0.62, vv.co.z)) + c + Vector((0, 0.0012 * sg, 0))
            m.pesos[vv] = {'corpo': 1.0}
            m.zona[vv] = 0.5
        for fa in {f for vv in res['verts'] for f in vv.link_faces}:
            fa.material_index = I_OLHO
            fa.smooth = True
            fa[m.lparte] = P_OLHO
    # nadadeiras: caudal (bifurcada), dorsal, anal, peitorais e pélvicas
    pc = lambda p: {'cauda': 1.0}
    nadadeira(m, [Vector((-0.128, 0, H0 + 0.009)), Vector((-0.20, 0, H0 + 0.050)), Vector((-0.188, 0, H0 + 0.022)),
                  Vector((-0.172, 0, H0)), Vector((-0.188, 0, H0 - 0.022)), Vector((-0.20, 0, H0 - 0.048)),
                  Vector((-0.128, 0, H0 - 0.009))], pc)
    pd = lambda p: pesos_x(p.x)
    nadadeira(m, [Vector((0.045, 0, H0 + 0.040)), Vector((0.02, 0, H0 + 0.072)), Vector((-0.012, 0, H0 + 0.060)),
                  Vector((-0.04, 0, H0 + 0.040)), Vector((-0.02, 0, H0 + 0.036))], pd)
    nadadeira(m, [Vector((-0.045, 0, H0 - 0.024)), Vector((-0.06, 0, H0 - 0.046)), Vector((-0.09, 0, H0 - 0.030)),
                  Vector((-0.095, 0, H0 - 0.012)), Vector((-0.07, 0, H0 - 0.019))], pd)
    for sg in (1, -1):
        nadadeira(m, [Vector((0.056, 0.029 * sg, H0 - 0.010)), Vector((0.016, 0.043 * sg, H0 - 0.021)),
                      Vector((0.012, 0.037 * sg, H0 - 0.027)), Vector((0.045, 0.027 * sg, H0 - 0.019))],
                  lambda p: {'corpo': 1.0})
        nadadeira(m, [Vector((0.012, 0.012 * sg, H0 - 0.030)), Vector((-0.022, 0.019 * sg, H0 - 0.043)),
                      Vector((-0.03, 0.013 * sg, H0 - 0.040)), Vector((-0.005, 0.008 * sg, H0 - 0.031))], pd)
    # monta: tudo desce até o ponto mais baixo encostar em z = 0
    zmin = min(v.co.z for v in m.bm.verts)
    for v in m.bm.verts:
        v.co.z -= zmin
    bpy.ops.object.mode_set(mode='EDIT')
    for n, a, b, pai in OSSOS:
        e = arm_d.edit_bones.new(n)
        e.head, e.tail, e.roll = Vector((a, 0, H0 - zmin)), Vector((b, 0, H0 - zmin)), 0.0
        if pai:
            e.parent = arm_d.edit_bones[pai]
    bpy.ops.object.mode_set(mode='OBJECT')
    me = bpy.data.meshes.new(nome + '_malha')
    pesos = [m.pesos.get(v, {'corpo': 1.0}) for v in m.bm.verts]
    zonas = [m.zona.get(v, 0.5) for v in m.bm.verts]
    m.bm.to_mesh(me)
    m.bm.free()
    for mt in MAT[especie]:
        me.materials.append(mt)
    at = me.color_attributes.new('zona', 'FLOAT_COLOR', 'POINT')
    for i, z_ in enumerate(zonas):
        at.data[i].color = (z_, 0.0, 0.0, 1.0)
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
    return arm


# ------------------------------------------------------------------ poses
def corpo_de(arm):
    return next(c for c in arm.children if c.type == 'MESH')


def pose_zero(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)


def gira(arm, n, pitch=0.0, yaw=0.0, rola=0.0):
    """Gira em volta dos eixos do peixe (yaw: para os lados; pitch: + = a ponta de um osso que vai para a frente desce)."""
    pb = arm.pose.bones[n]
    pb.rotation_mode = 'QUATERNION'
    inv = pb.bone.matrix_local.to_3x3().inverted()
    pb.rotation_quaternion = Quaternion(inv @ Z, yaw) @ Quaternion(inv @ Y, pitch) @ Quaternion(inv @ X, rola)


def _zmin(arm):
    bpy.context.view_layer.update()
    o = corpo_de(arm)
    oe = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
    me = oe.to_mesh()
    mw = arm.matrix_world.inverted() @ oe.matrix_world
    z = min((mw @ v.co).z for v in me.vertices)
    oe.to_mesh_clear()
    return z


def assentar(arm):
    """Sobe/desce o corpo até o ponto mais baixo encostar em z = 0 (nada cortado pelo gerador de sprites)."""
    pb = arm.pose.bones['corpo']
    for _ in range(3):
        dz = _zmin(arm)
        # o y local do osso 'corpo' aponta para +X do peixe; o z local, para cima
        pb.location = (pb.location[0], pb.location[1], pb.location[2] - dz)


def pose_nadar(arm, u):
    """Nado (u 0..1): uma onda lateral corre da cabeça para a cauda, crescendo para trás; a cabeça balança pouco."""
    pose_zero(arm)
    w = 2 * PI * u
    gira(arm, 'corpo', yaw=0.05 * math.sin(w + 0.6))
    for k, (n, amp) in enumerate((('coluna1', 0.10), ('coluna2', 0.17), ('coluna3', 0.24), ('cauda', 0.32))):
        gira(arm, n, yaw=amp * math.sin(w - 0.95 * (k + 1)))
    assentar(arm)


def pose_pulo(arm, u):
    """Pulo (u 0..1): fora d'água o corpo arqueia (cabeça e cauda para baixo, o lombo para cima) e desarqueia, com uma
    batida de cauda no começo (o impulso); o jogo leva o peixe no arco do salto."""
    pose_zero(arm)
    arco = math.sin(PI * u)
    bat = math.sin(2 * PI * u * 2) * (1.0 - suave(u / 0.5))
    gira(arm, 'corpo', pitch=0.24 * arco)                 # a frente (e a cabeça) desce...
    for k, n in enumerate(('coluna1', 'coluna2', 'coluna3', 'cauda')):   # ...e a coluna dobra a cauda para baixo: ∩
        gira(arm, n, pitch=-(0.11 + 0.04 * k) * arco, yaw=0.25 * (k + 1) / 4 * bat)
    assentar(arm)


def pose_morto(arm, u=0.0):
    """Morto: de barriga para cima, duro (uma curva leve, a cauda um pouco caída); boia na água."""
    pose_zero(arm)
    gira(arm, 'corpo', rola=PI)
    for n, a in (('coluna1', 0.03), ('coluna2', 0.05), ('coluna3', 0.05), ('cauda', 0.08)):
        gira(arm, n, pitch=-a)
    assentar(arm)


ACOES = (('nadar', 12, pose_nadar), ('pulo', 12, pose_pulo), ('morto', 2, pose_morto))


def conferir(arm, log):
    ruins = 0
    for nome, nq, posar in ACOES:
        for q in range(nq):
            posar(arm, q / nq)
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
            t1 = BVHTree.FromPolygons(co, polys[P_NAD])
            t2 = BVHTree.FromPolygons(co, polys[P_OSSO])
            t3 = BVHTree.FromPolygons(co, polys[P_CORPO])
            # nadadeira x placa, e nadadeira caudal x corpo (a dobra da cauda não pode passar pela pele)
            cruz = len(t1.overlap(t2))
            if zmin < -0.0015 or abs(zmin) > 0.0015 or cruz:
                ruins += 1
                log.append(f'  {nome} q{q}: zmin={zmin:.4f} nadadeira x placa={cruz}')
    return ruins


# ------------------------------------------------------------------ cena
modo = _ARGS[0] if _ARGS else 'foto'
if modo == 'conferir':
    for esp in ESPECIES:
        arm = montar('conf_' + esp, esp)
        o = corpo_de(arm)
        tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
        log = []
        n = conferir(arm, log)
        pose_zero(arm)
        bpy.context.view_layer.update()
        pts = [o.matrix_world @ v.co for v in o.data.vertices]
        dims = [round(max(p[i] for p in pts) - min(p[i] for p in pts), 3) for i in range(3)]
        print(f'PEIXE {esp} tris={tris} dims={dims} quadros_ruins={n}')
        for l in log:
            print(l)
elif modo in ('foto', 'quadros'):
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
    cam_d = bpy.data.cameras.new('Cam'); cam = bpy.data.objects.new('Cam', cam_d); sc.collection.objects.link(cam)
    sc.camera = cam

    def mirar(pos, alvo, lente=None, orto=None):
        cam.location = pos
        cam.rotation_euler = (Vector(alvo) - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
        if orto:
            cam_d.type, cam_d.ortho_scale = 'ORTHO', orto
        else:
            cam_d.type, cam_d.lens = 'PERSP', lente

    def rotulo(texto, tam=0.022, pos=None):
        if pos is None:                     # canto de cima à esquerda, pela lente atual
            hw = 18.0 / cam_d.lens
            pos = (-hw * 0.93, hw * 0.68 * 0.82)
        cu = bpy.data.curves.new('rot', 'FONT')
        cu.body = texto
        cu.size = tam
        o = bpy.data.objects.new('ROT_' + texto[:10], cu)
        sc.collection.objects.link(o)
        mt = bpy.data.materials.new('RotuloMat')
        b = next(n for n in mt.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        b.inputs['Base Color'].default_value = (0, 0, 0, 1)
        b.inputs['Emission Color'].default_value = (1, 1, 1, 1)
        b.inputs['Emission Strength'].default_value = 1.0
        mt.diffuse_color = (1, 1, 1, 1)
        o.data.materials.append(mt)
        o.parent = cam
        o.location = (pos[0], pos[1], -1.0)
        o.visible_shadow = False
        return o
    os.makedirs(SAIDA, exist_ok=True)
    if modo == 'foto':
        # pranchas das candidatas: de lado e de 3/4 (nadando), sobre seixos, com régua de 10 cm
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
        sc.cycles.samples = 96
        sc.view_settings.view_transform = 'AgX'
        sc.view_settings.look = 'AgX - Medium High Contrast'
        sc.view_settings.exposure = -0.2
        sc.render.resolution_x, sc.render.resolution_y = 1000, 680
        base3d.M['chao'] = liso_mat('Seixos', (0.22, 0.21, 0.18), 0.8)
        bm = bmesh.new()
        base3d.caixa(bm, (0, 0, -0.05), (10, 10, 0.10))
        base3d.obj('EFEITO_chao', bm, 'chao')
        base3d.M['rb'] = liso_mat('ReguaB', (0.8, 0.8, 0.78), 0.6)
        base3d.M['rp'] = liso_mat('ReguaP', (0.02, 0.02, 0.02), 0.6)
        arqs = []
        for k, (esp, letra) in enumerate((('couraca', 'A'), ('couraca_rubra', 'B'))):
            y = k * 3.0
            lado = montar(esp + '_lado', esp, Vector((0, y, 0)), 0.0)
            pose_nadar(lado, 0.0)
            nada = montar(esp + '_nada', esp, Vector((0, y + 1.2, 0)), 0.75)
            pose_nadar(nada, 0.3)
            for j in range(4):                       # régua: 4 faixas de 10 cm, alternadas, deitada no chão
                bm = bmesh.new()
                base3d.caixa(bm, (-0.15 + 0.1 * j, y + 0.09, 0.003), (0.1, 0.012, 0.006))
                base3d.obj(f'EFEITO_regua{k}{j}', bm, 'rb' if j % 2 == 0 else 'rp')
            mirar((0.0, y - 0.72, 0.10), (0.0, y, 0.045), 50)
            r = rotulo(f'{letra} — {esp}  ({ESPECIES[esp]["nome"]})')
            sc.render.filepath = os.path.join(SAIDA, f'_{esp}_lado.png')
            bpy.ops.render.render(write_still=True)
            arqs.append(sc.render.filepath)
            mirar((0.34, y + 1.2 - 0.42, 0.26), (0.0, y + 1.2, 0.035), 50)
            sc.render.filepath = os.path.join(SAIDA, f'_{esp}_34.png')
            bpy.ops.render.render(write_still=True)
            arqs.append(sc.render.filepath)
            bpy.data.objects.remove(r, do_unlink=True)
        import numpy as np
        imgs = [bpy.data.images.load(f) for f in arqs]
        w, h = imgs[0].size
        big = np.zeros((h * 2, w * 2, 4), dtype=np.float32)
        for i, im in enumerate(imgs):
            px = np.empty(w * h * 4, dtype=np.float32)
            im.pixels.foreach_get(px)
            c, l = i % 2, i // 2
            big[(1 - l) * h:(2 - l) * h, c * w:(c + 1) * w] = px.reshape(h, w, 4)
        out = bpy.data.images.new('prancha', w * 2, h * 2, alpha=False)
        out.pixels.foreach_set(big.ravel())
        out.filepath_raw = os.path.join(SAIDA, 'peixes.png')
        out.file_format = 'PNG'
        out.save()
        for f in arqs:
            os.remove(f)
        print('PRANCHA peixes')
