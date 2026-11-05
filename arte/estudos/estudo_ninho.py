"""Estudo (patch fauna, fase 6): NINHOS dos pássaros pequenos, escolhidos por Sapyst entre as candidatas (os dois, por
espécie). Feitos na escala do jogo (o pássaro do jogo é o do estudo × 0,75):
  TAÇA  (pardelo, rubro) — gravetos curvos deitados em volta, uns espetados para fora, forro de capim fino; fica na
        forquilha da árvore, onde o tronco se abre nos galhos (discreta: aparece de verdade quando a folha cai).
  BOLSA (cobrico, azulão) — bolsa comprida tecida de capim, fina no alto e com bojo embaixo, entrada escura de lado
        no alto do bojo, fios soltos; pende de um raminho na ponta de um galho (aparece o ano todo, embaixo da copa).
Duas qualidades: a do estudo (muitos gravetos, para a foto) e a do jogo (forma de casca com a trama assada na textura
e poucos gravetos soltos, ~300 triângulos).

Uso: blender -b --python estudo_ninho.py -- foto"""
import bpy, bmesh, math, os, sys, random
from mathutils import Vector, Matrix, noise

AQUI = os.path.dirname(os.path.abspath(__file__))
PI = math.pi
ESC = 0.75                       # o pássaro do jogo é o do estudo × 0,75: o ninho dele também
rnd = random.Random(61)


# ------------------------------------------------------------------ materiais
def mat_ruido(nome, claro, escuro, escala=60.0, aspereza=0.9, faixa=(0.35, 0.7)):
    m = bpy.data.materials.new(nome)
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = escala; nz.inputs['Detail'].default_value = 8.0
    nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    rmp = nt.nodes.new('ShaderNodeValToRGB')
    rmp.color_ramp.elements[0].position = faixa[0]; rmp.color_ramp.elements[0].color = (*escuro, 1)
    rmp.color_ramp.elements[1].position = faixa[1]; rmp.color_ramp.elements[1].color = (*claro, 1)
    nt.links.new(nz.outputs['Fac'], rmp.inputs['Fac'])
    nt.links.new(rmp.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = aspereza
    return m


def mat_fios(nome, claro, escuro, escala=70.0, cruzado=True):
    """Fios (graveto deitado em volta, ou capim tecido): ondas finas em volta (e cruzadas, na trama) + ruído."""
    m = bpy.data.materials.new(nome)
    nt = m.node_tree
    b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    w1 = nt.nodes.new('ShaderNodeTexWave'); w1.inputs['Scale'].default_value = escala; w1.inputs['Distortion'].default_value = 7
    w1.bands_direction = 'Z'
    w2 = nt.nodes.new('ShaderNodeTexWave'); w2.inputs['Scale'].default_value = escala * 0.8; w2.inputs['Distortion'].default_value = 9
    w2.bands_direction = 'DIAGONAL'
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = escala * 2; nz.inputs['Detail'].default_value = 6
    for n in (w1, w2, nz):
        nt.links.new(tc.outputs['Object'], n.inputs['Vector'])
    mx = nt.nodes.new('ShaderNodeMath'); mx.operation = 'MULTIPLY' if cruzado else 'ADD'
    nt.links.new(w1.outputs['Fac'], mx.inputs[0]); nt.links.new(w2.outputs['Fac'], mx.inputs[1])
    ad = nt.nodes.new('ShaderNodeMath'); ad.operation = 'MULTIPLY_ADD'; ad.inputs[1].default_value = 0.6
    nt.links.new(mx.outputs[0], ad.inputs[0]); nt.links.new(nz.outputs['Fac'], ad.inputs[2])
    rmp = nt.nodes.new('ShaderNodeValToRGB')
    rmp.color_ramp.elements[0].position = 0.45; rmp.color_ramp.elements[0].color = (*escuro, 1)
    rmp.color_ramp.elements[1].position = 0.95; rmp.color_ramp.elements[1].color = (*claro, 1)
    nt.links.new(ad.outputs[0], rmp.inputs['Fac'])
    nt.links.new(rmp.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.92
    return m


def materiais():
    return {'graveto': mat_ruido('Graveto', (0.24, 0.19, 0.14), (0.07, 0.055, 0.045), 80, 0.9),
            'casca_taca': mat_fios('CascaTaca', (0.27, 0.21, 0.15), (0.06, 0.045, 0.035), 90, cruzado=False),
            'forro': mat_ruido('Forro', (0.36, 0.30, 0.22), (0.10, 0.08, 0.06), 220, 0.95),
            'trama': mat_fios('Trama', (0.52, 0.45, 0.30), (0.17, 0.14, 0.09), 90),
            'boca': mat_ruido('Boca', (0.02, 0.016, 0.012), (0.005, 0.004, 0.003), 50, 0.95)}


# ------------------------------------------------------------------ peças
def tubo(bm, pts, r0, r1, lados=5, mat=0):
    """Tubo afinando ao longo da polilinha (graveto, fio de capim)."""
    aneis = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized()
        b = d.cross(a)
        r = r0 + (r1 - r0) * i / max(1, len(pts) - 1)
        aneis.append([bm.verts.new(p + (a * math.cos(2 * PI * k / lados) + b * math.sin(2 * PI * k / lados)) * r)
                      for k in range(lados)])
    for a, b in zip(aneis, aneis[1:]):
        for k in range(lados):
            f = bm.faces.new((a[k], a[(k + 1) % lados], b[(k + 1) % lados], b[k]))
            f.material_index = mat
            f.smooth = True


def torno(bm, perfil, lados, mat_fora, mat_dentro=None, ruido=0.0, fechar_fundo=False, descendo=False):
    """Superfície de revolução em volta de z: `perfil` = [(raio, z)…]. A face olha para fora quando o perfil sobe;
    `descendo` = o perfil vai do alto para baixo (a bolsa): vira as faces para continuarem olhando para fora."""
    aneis = []
    for i, (r, z) in enumerate(perfil):
        anel = []
        for k in range(lados):
            a = 2 * PI * k / lados
            p = Vector((r * math.cos(a), r * math.sin(a), z))
            if ruido > 0.0 and r > 0.001:
                p += Vector((noise.noise(p * 70 + Vector((3, 1, 0))), noise.noise(p * 70 + Vector((0, 5, 2))), 0)) * ruido
            anel.append(bm.verts.new(p))
        aneis.append(anel)
    for i, (a, b) in enumerate(zip(aneis, aneis[1:])):
        for k in range(lados):
            q = (a[k], a[(k + 1) % lados], b[(k + 1) % lados], b[k])
            f = bm.faces.new(q[::-1] if descendo else q)
            f.material_index = mat_dentro if (mat_dentro is not None and i >= len(perfil) // 2) else mat_fora
            f.smooth = True
    if fechar_fundo:
        f = bm.faces.new(list(reversed(aneis[-1])))
        f.material_index = mat_fora
    return aneis


def ninho_taca(jogo=True):
    """TAÇA (≈10 cm de fora no jogo). Indices de material: 0 graveto, 1 casca (fios em volta), 2 forro."""
    bm = bmesh.new()
    R, r, H = 0.068, 0.040, 0.050
    if jogo:
        # casca: de fora (base → borda) e de dentro (borda → fundo do forro), num perfil só
        perfil = [(0.030, 0.000), (0.055, 0.008), (R, 0.026), (R * 0.98, H), (r * 1.15, H + 0.004), (r, H - 0.006),
                  (r * 0.8, H - 0.024), (0.0, H - 0.032)]
        torno(bm, perfil, 10, 1, 2, ruido=0.004)
        for k in range(14):                                  # gravetos soltos, espetados para fora
            a0 = 2 * PI * k / 14 + rnd.uniform(-0.2, 0.2)
            z0 = rnd.uniform(0.006, H - 0.004)
            L = rnd.uniform(0.04, 0.08)
            d = Vector((math.cos(a0 + rnd.uniform(0.6, 1.2)), math.sin(a0 + rnd.uniform(0.6, 1.2)), rnd.uniform(-0.3, 0.3)))
            p0 = Vector((R * 0.9 * math.cos(a0), R * 0.9 * math.sin(a0), z0))
            tubo(bm, [p0, p0 + d * L * 0.5 + Vector((0, 0, 0.003)), p0 + d * L], 0.0022, 0.0010, 3, 0)
    else:
        for k in range(150):
            a0 = rnd.uniform(0, 2 * PI)
            rr = rnd.uniform(r * 1.05, R * 1.08)
            z0 = rnd.uniform(0.004, H)
            L = rnd.uniform(0.07, 0.15)
            incl = rnd.uniform(-0.25, 0.25)
            fora = rnd.random() < 0.12
            pts = []
            for i in range(6):
                t = i / 5
                a = a0 + (t * 0.3 if fora else t * L / rr)
                rad = rr + t * L * 0.7 if fora else rr * (1 + 0.06 * math.sin(t * 5 + k))
                z = min(max(z0 + t * L * incl, 0.0), H + 0.008)
                p = Vector((rad * math.cos(a), rad * math.sin(a), z))
                p += Vector((noise.noise(p * 60), noise.noise(p * 60 + Vector((5, 2, 1))), 0)) * 0.004
                pts.append(p)
            tubo(bm, pts, rnd.uniform(0.0016, 0.003), 0.0009, 5, 0)
        res = bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=10, radius=r)
        for v in res['verts']:
            v.co.z = min(v.co.z, 0.0) * 0.75 + H - 0.004
        for f in {f for v in res['verts'] for f in v.link_faces}:
            f.material_index = 2
    bmesh.ops.scale(bm, vec=(ESC, ESC, ESC), verts=bm.verts)
    return bm


def ninho_bolsa(comp=0.38, jogo=True):
    """BOLSA (≈29 cm no jogo), com o raminho de onde pende: a origem é a ponta do galho; o raminho vai para −x (para
    dentro da copa) e sobe. Indices: 0 graveto, 1 trama, 2 boca."""
    bm = bmesh.new()
    N, LADOS = (12, 8) if jogo else (22, 14)
    perfil = []
    for i in range(N + 1):
        t = i / N
        rad = 0.010 + 0.040 * math.sin(min(1.0, t * 1.15) * PI * 0.5) ** 2.2 * (1.0 - 0.55 * max(0.0, t - 0.82) / 0.18)
        if t > 0.97:
            rad *= 0.6
        perfil.append((rad, -0.012 - comp * t))
    aneis = torno(bm, perfil, LADOS, 1, ruido=0.003, fechar_fundo=True, descendo=True)
    for anel, (rad, z) in zip(aneis, perfil):                # leve barriga para um lado
        t = -(z + 0.012) / comp
        for v in anel:
            v.co.x += 0.012 * math.sin(t * PI)
    # entrada: um anel escuro no alto do bojo, de lado (+x)
    ze = -0.012 - comp * 0.62
    res = bmesh.ops.create_circle(bm, cap_ends=True, segments=8, radius=0.016)
    for v in res['verts']:
        v.co = Vector((0.050 + 0.0135, v.co.x, ze + v.co.y * 1.25))
    for fa in {f for v in res['verts'] for f in v.link_faces}:
        fa.material_index = 2
    for k in range(6 if jogo else 26):                       # fios soltos pendurados
        t = rnd.uniform(0.15, 0.95)
        a = rnd.uniform(0, 2 * PI)
        rad = 0.010 + 0.040 * math.sin(min(1.0, t * 1.15) * PI * 0.5) ** 2.2
        p0 = Vector((rad * math.cos(a) * 0.95, rad * math.sin(a) * 0.95, -0.012 - comp * t))
        L = rnd.uniform(0.03, 0.09)
        tubo(bm, [p0 + Vector((math.cos(a) * 0.004 * i, math.sin(a) * 0.004 * i, -L * i / 2)) for i in range(3)],
             0.0012, 0.0005, 3, 1)
    # amarrado e raminho até o galho
    tubo(bm, [Vector((0, 0, -0.016)), Vector((0, 0, 0.0))], 0.004, 0.003, 4, 1)
    tubo(bm, [Vector((0.0, 0, 0.0)), Vector((-0.035, 0, 0.018)), Vector((-0.07, 0, 0.03))], 0.0025, 0.0055, 5, 0)
    bmesh.ops.scale(bm, vec=(ESC, ESC, ESC), verts=bm.verts)
    return bm


def objeto(sc, nome, bm, mats, pos=(0, 0, 0)):
    me = bpy.data.meshes.new(nome)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    o = bpy.data.objects.new(nome, me)
    sc.collection.objects.link(o)
    o.location = pos
    return o


if __name__ == '__main__' and '--' in sys.argv and 'foto' in sys.argv[sys.argv.index('--') + 1:]:
    sys.path.insert(0, AQUI)
    import base3d
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = base3d.iniciar()
    M = materiais()
    for i, jogo in enumerate((False, True)):
        objeto(sc, f'taca_{i}', ninho_taca(jogo), [M['graveto'], M['casca_taca'], M['forro']], (i * 0.3, 0, 0.0))
        objeto(sc, f'bolsa_{i}', ninho_bolsa(jogo=jogo), [M['graveto'], M['trama'], M['boca']], (i * 0.3, 0.4, 0.4))
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 64
    cam_d = bpy.data.cameras.new('Cam'); cam = bpy.data.objects.new('Cam', cam_d); sc.collection.objects.link(cam); sc.camera = cam
    cam.location = (0.15, -0.9, 0.55)
    cam.rotation_euler = (Vector((0.15, 0.2, 0.15)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sol = bpy.data.lights.new('Sol', 'SUN'); sol.energy = 3.5
    so = bpy.data.objects.new('Sol', sol); sc.collection.objects.link(so); so.rotation_euler = (math.radians(45), 0, math.radians(-30))
    sc.render.resolution_x, sc.render.resolution_y = 1000, 700
    sc.render.filepath = os.path.join(AQUI, 'ninho_estudo_jogo.png')
    bpy.ops.render.render(write_still=True)
    print('NINHO_FOTO ok')
