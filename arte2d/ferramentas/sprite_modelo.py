# PlanetaFactory 2D: transforma um modelo 3D do jogo (glb) em folhas de sprite pixel art "realista e escuro".
# Só o modelo escurece (material); o fundo é transparente e a sombra sai numa folha à parte.
# blender -b --python sprite_modelo.py -- <projeto_jogo> <nome> <pasta_saida>
import bpy, sys, os, json, math, bmesh
import numpy as np
from mathutils import Vector, Matrix

JOGO, NOME, SAIDA = sys.argv[sys.argv.index('--') + 1:][:3]
TODOS = json.load(open(os.path.join(JOGO, 'dados', 'modelos.json')))
ARANHA = NOME == 'aranha_animada'          # aranha do jogo: corpo + 6 pernas (fêmur, tíbia) posadas como no aranha.gd
LARVA = NOME in ('larva_acida', 'cratera_larva')   # larva e cratera: montadas pelo estudo (arte/estudos/estudo_larva.py)
ESTUDO_LARVA = os.path.join(JOGO, '..', 'arte', 'estudos', 'estudo_larva.py')
PASSARO = NOME.startswith('passaro_')         # pássaros (patch fauna): montados pelo estudo (arte/estudos/estudo_passaro.py)
ESTUDO_PASSARO = os.path.join(JOGO, '..', 'arte', 'estudos', 'estudo_passaro.py')
if PASSARO:
    M = {'nome': NOME, 'categoria': 'fauna/passaros', 'tipo': 'veiculo', 'partes': []}
elif LARVA:
    M = {'nome': NOME, 'categoria': 'inimigos/larva', 'tipo': 'veiculo' if NOME == 'larva_acida' else 'estrutura', 'partes': []}
else:
    M = dict(TODOS['aranha_montada'], nome=NOME) if ARANHA else TODOS[NOME]
CAT = M.get('categoria', '')
GRUPO = CAT.split('/')[0]
PX = 4.6 / 160                     # metros por pixel (igual em todo o jogo)
EL = math.radians(35)              # câmera ortográfica de frente, meio de cima
SUPER = 4                          # passe de cor em 4x, reduzido pela média
FPS = 12

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def importar_peca(nome, rotulo):
    """Importa um glb e deixa uma malha só, com a origem do modelo do jogo na origem do mundo."""
    antes = set(sc.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(JOGO, TODOS[nome]['modelo'].replace('res://', '')))
    novos = [o for o in sc.objects if o not in antes]
    nomes_novos = [o.name for o in novos]
    ms = [o for o in novos if o.type == 'MESH']
    for o in ms:
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    bpy.ops.object.select_all(action='DESELECT')
    for o in ms:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ms[0]
    if len(ms) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    resto = [n for n in nomes_novos if n != ob.name and n in bpy.data.objects]
    for n in resto:
        bpy.data.objects.remove(bpy.data.objects[n])
    ob.name = rotulo
    return ob


if ARANHA:
    AR_CORPO = importar_peca('aranha_corpo', 'ar_corpo')
    AR_FEMUR = [importar_peca('aranha_femur', 'ar_femur0')]
    AR_TIBIA = [importar_peca('aranha_tibia', 'ar_tibia0')]
    for k in range(1, 6):
        for lista, rot in ((AR_FEMUR, 'ar_femur%d'), (AR_TIBIA, 'ar_tibia%d')):
            c = lista[0].copy(); c.data = lista[0].data.copy(); c.name = rot % k
            sc.collection.objects.link(c); lista.append(c)
elif PASSARO:
    # o estudo monta todos; fica só o pássaro da espécie (o "<espécie>_voo"), na origem, sem giro
    _argv = sys.argv
    sys.argv = [sys.argv[0], '--python', ESTUDO_PASSARO, '--', 'nada']
    sys.path.insert(0, os.path.dirname(ESTUDO_PASSARO))
    NS_P = {'__name__': '__main__', '__file__': ESTUDO_PASSARO}
    exec(compile(open(ESTUDO_PASSARO, encoding='utf-8').read(), ESTUDO_PASSARO, 'exec'), NS_P)
    sys.argv = _argv
    sc = bpy.context.scene
    ARM_P = sc.objects[NOME.split('_', 1)[1] + '_voo']
    for o in list(sc.objects):
        if not (o is ARM_P or o.parent is ARM_P):
            bpy.data.objects.remove(o, do_unlink=True)
    ARM_P.animation_data_clear()
    ARM_P.location = (0, 0, 0)
    ARM_P.rotation_euler = (0, 0, 0)
    ARM_P.scale = (0.75, 0.75, 0.75)          # = DesenhoPassaros.ESCALA (o tamanho do pássaro no jogo)
    bpy.context.view_layer.update()           # (senão o pivô abaixo herda a posição antiga, da cena do estudo)
    OSSOS = list(ARM_P.pose.bones)
elif LARVA:
    # o estudo monta a cena (materiais, esqueleto, poses); aqui fica só a peça pedida, na origem
    _argv = sys.argv
    sys.argv = [sys.argv[0], '--python', ESTUDO_LARVA, '--', 'nada']
    sys.path.insert(0, os.path.dirname(ESTUDO_LARVA))
    NS_LARVA = {'__name__': '__main__', '__file__': ESTUDO_LARVA}
    exec(compile(open(ESTUDO_LARVA, encoding='utf-8').read(), ESTUDO_LARVA, 'exec'), NS_LARVA)
    sys.argv = _argv
    sc = bpy.context.scene
    fica = (lambda n: n == 'larva' or (n.startswith('larva_') and not n.startswith('larva_cuspe'))) if NOME == 'larva_acida' \
        else (lambda n: n.startswith('cratera_'))
    for o in list(sc.objects):
        if not fica(o.name):
            bpy.data.objects.remove(o, do_unlink=True)
    if NOME == 'cratera_larva':
        for o in sc.objects:
            if o.parent is None:
                o.location.x -= NS_LARVA['CX']
        bpy.context.view_layer.update()
    else:
        sc.objects['larva'].animation_data_clear()
        OSSOS = list(sc.objects['larva'].pose.bones)
else:
    bpy.ops.import_scene.gltf(filepath=os.path.join(JOGO, M['modelo'].replace('res://', '')))
malhas = [o for o in sc.objects if o.type == 'MESH']
PARTES = {}
for o in sc.objects:
    if '_' in o.name:
        PARTES.setdefault(o.name.rsplit('_', 1)[-1].split('.')[0], o)
# árvores: a conversão do ambiente (commit 7a9643d) perdeu o material de folha e a copa veio cinza na textura;
# aqui a copa volta à cor de verão da espécie (cores do material P_Folha* dos modelos de 5951dc9, em sRGB)
FOLHA_SRGB = {'acacia': (0.44, 0.5, 0.24), 'betula': (0.44, 0.6, 0.28), 'carvalho': (0.3, 0.5, 0.22),
              'pinheiro': (0.12, 0.3, 0.2), 'salgueiro': (0.4, 0.56, 0.34)}
esp = NOME.split('_')[1] if NOME.startswith('arv_') else ''
if esp in FOLHA_SRGB:
    mf = bpy.data.materials.new('folha_' + esp); mf.use_nodes = True
    next(n for n in mf.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs['Base Color'].default_value = (*[c ** 2.2 for c in FOLHA_SRGB[esp]], 1)
    for o in malhas:
        me = o.data
        tex = next((n.image for m in me.materials if m for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image), None)
        if tex is None or not me.uv_layers:
            continue
        tw, th = tex.size
        px = np.empty(tw * th * 4, dtype=np.float32); tex.pixels.foreach_get(px); px = px.reshape(th, tw, 4)
        me.materials.append(mf); idx = len(me.materials) - 1
        uv = me.uv_layers.active.data; n_folha = 0
        for pl in me.polygons:
            u = sum(uv[l].uv.x for l in pl.loop_indices) / pl.loop_total
            v = sum(uv[l].uv.y for l in pl.loop_indices) / pl.loop_total
            c = px[min(th - 1, max(0, int(v * th))), min(tw - 1, max(0, int(u * tw))), :3]
            if c.max() - c.min() < 0.05 and c.max() < 0.5:
                pl.material_index = idx; n_folha += 1
        print('FOLHA', o.name, n_folha, 'de', len(me.polygons))

# pivô único na origem: girar a construção inteira
PIVO = bpy.data.objects.new('PIVO', None); sc.collection.objects.link(PIVO)
for o in list(sc.objects):
    if o.parent is None and o is not PIVO:
        mw = o.matrix_world.copy(); o.parent = PIVO; o.matrix_world = mw
sc.frame_set(1)

# ------------------------------------------------------------------ o que animar e quantas linhas (rotações/direções)
acao = next((a for a in bpy.data.actions if a.name.split('.')[0] in ('trabalho', 'chegada')), None)
nomes_p = {p['nome'] for p in M.get('partes', [])}
ROTS = [0, 1, 2, 3]
if GRUPO in ('mapa', 'itens') or CAT.endswith('aranha') and M.get('tipo') == 'segmento' or NOME in ('aranha_corpo',):
    ROTS = [0]
VARIANTES = ['base']
QUADROS = 1
DIRECOES = 0                        # >0: cada linha é uma direção (gira o modelo/canhão em vez da construção)
if acao is not None:
    QUADROS = 48
if 'giro' in nomes_p and 'canhao' in nomes_p:                     # torre: a cabeça mira em 16 direções
    DIRECOES = 16; ROTS = [0]; QUADROS = 1
    if GRUPO == 'defesa':                                          # e a animação do tiro: o cano recua e volta
        QUADROS = 6; VARIANTES = ['base', 'tiro']
RECUO = {'torre_metralhadora': 0.05, 'torre_defesa': 0.08, 'torre_foguetes': 0.06, 'artilharia': 0.28, 'drone_defesa': 0.04}.get(NOME, 0.06)
PERFIL_RECUO = [1.0, 0.75, 0.5, 0.28, 0.12, 0.0, 0.0, 0.0]
if NOME.startswith(('locomotiva', 'vagao')):                       # trem: 16 direções (curvas)
    DIRECOES = 16; ROTS = [0]
if GRUPO == 'drones' and M.get('tipo') == 'veiculo':               # drone: 8 direções, hélices girando
    DIRECOES = 8; ROTS = [0]; QUADROS = 8
    if 'canhao' in nomes_p:                                        # drone de defesa: e o tiro (o cano recua e volta)
        VARIANTES = ['base', 'tiro']
if NOME == 'aranha_montada':
    DIRECOES = 8; ROTS = [0]
if PASSARO:                                 # 16 direções; voo, planar, parado, bicando e pousar (ao contrário = decolar), 8 quadros
    DIRECOES = 16; ROTS = [0]; QUADROS = 8; VARIANTES = ['voo', 'planar', 'parado', 'bicando', 'pousar']
if NOME == 'larva_acida':                   # 16 direções; andar (laço: a massa contrai e estica) e cuspe, 12 quadros cada
    DIRECOES = 16; ROTS = [0]; QUADROS = 12; VARIANTES = ['andar', 'cuspe']
if ARANHA:                                  # 16 direções; andar (laço), ataque (laço) e morte (uma vez), 12 quadros cada
    DIRECOES = 16; ROTS = [0]; QUADROS = 12; VARIANTES = ['andar', 'ataque', 'morte']
if {'rotor', 'helice', 'antena', 'cristal'} & nomes_p and QUADROS == 1:
    QUADROS = 48
LONA = {'P_Esteira': 1, 'P_EsteiraRapida': 2, 'P_EsteiraExpressa': 3, 'P_EsteiraQuantica': 4}
mats_lona = [m for m in bpy.data.materials if m.name.split('.')[0] in LONA]
if mats_lona and QUADROS == 1:
    QUADROS = 16                                                   # lona: laço de 16 quadros
BRACO = 'braco1' in nomes_p
if BRACO:
    QUADROS = 28
    VARIANTES = ['atras', 'esquerda', 'direita']
QUANTICO = 'lanca1' in nomes_p
if 'canhao' in nomes_p and 'giro' not in nomes_p and GRUPO == 'drones':
    pass

# ------------------------------------------------------------------ luz e câmera
try:
    sc.render.engine = 'BLENDER_EEVEE'
except TypeError:
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'
sol = bpy.data.lights.new('Sol', 'SUN'); sol.energy = 4.2; sol.angle = math.radians(0.3); sol.color = (1.0, 0.9, 0.78)
so = bpy.data.objects.new('Sol', sol); sc.collection.objects.link(so)
so.rotation_euler = (math.radians(55), 0, math.radians(-50))
mundo = bpy.data.worlds.new('M'); mundo.use_nodes = True; sc.world = mundo
bg = next(n for n in mundo.node_tree.nodes if n.type == 'BACKGROUND')
bg.inputs['Color'].default_value = (0.35, 0.42, 0.55, 1); bg.inputs['Strength'].default_value = 0.16
ee = sc.eevee
ee.taa_render_samples = 1
for at, v in (('shadow_resolution_scale', 1.0), ('shadow_ray_count', 1), ('shadow_step_count', 16)):
    if hasattr(ee, at):
        setattr(ee, at, v)
if hasattr(sol, 'shadow_jitter'):
    sol.shadow_jitter = False
sc.render.filter_size = 0.0
cam_d = bpy.data.cameras.new('Cam'); cam_d.type = 'ORTHO'
cam = bpy.data.objects.new('Cam', cam_d); sc.collection.objects.link(cam); sc.camera = cam
DIR_CAM = Vector((0.0, -math.cos(EL), math.sin(EL)))
cam.rotation_euler = (-DIR_CAM).to_track_quat('-Z', 'Y').to_euler()
bpy.context.view_layer.update()
DIR_SOL = (so.matrix_world.to_3x3() @ Vector((0, 0, 1))).normalized()      # para onde a luz vem
print('DIR_SOL', tuple(round(c, 3) for c in DIR_SOL))

# ------------------------------------------------------------------ peças finas: cilindro magenta (vira linha de 1 px)
m_cabo = bpy.data.materials.new('cabo'); m_cabo.use_nodes = True
nt = m_cabo.node_tree
for n in list(nt.nodes):
    if n.type != 'OUTPUT_MATERIAL':
        nt.nodes.remove(n)
em = nt.nodes.new('ShaderNodeEmission'); em.inputs['Color'].default_value = (1, 0, 1, 1)
nt.links.new(em.outputs[0], next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL').inputs['Surface'])
CABOS = []
for o in list(malhas) if NOME not in ('ninho_aranha', 'larva_acida', 'cratera_larva') else []:      # a toca: fio fino é seda clara, não cabo escuro
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.verts.ensure_lookup_table(); mw = o.matrix_world
    vistos = set(); apagar = []
    for v0 in bm.verts:
        if v0.index in vistos:
            continue
        pilha = [v0]; parte = []; vistos.add(v0.index)
        while pilha:
            v = pilha.pop(); parte.append(v)
            for e in v.link_edges:
                w = e.other_vert(v)
                if w.index not in vistos:
                    vistos.add(w.index); pilha.append(w)
        if len(parte) > 64:
            continue
        cs = [mw @ v.co for v in parte]
        a, b = max(((p, q) for p in cs[::max(1, len(cs) // 16)] for q in cs), key=lambda pq: (pq[0] - pq[1]).length)
        L = (a - b).length
        if L < 0.3:
            continue
        eixo = (b - a).normalized()
        raio = max(((c - a) - eixo * (c - a).dot(eixo)).length for c in cs)
        if raio < 0.014:
            CABOS.append((o, a, b))
            apagar.extend({f for v in parte for f in v.link_faces})
    if apagar:
        bmesh.ops.delete(bm, geom=list(set(apagar)), context='FACES_ONLY')
        bm.to_mesh(o.data)
    bm.free()
for o, a, b in CABOS:
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.02, depth=(b - a).length, location=(a + b) / 2)
    cil = bpy.context.object
    cil.rotation_euler = (b - a).to_track_quat('Z', 'Y').to_euler()
    cil.data.materials.append(m_cabo)
    bpy.context.view_layer.update()
    mwc = cil.matrix_world.copy(); cil.parent = o; cil.matrix_world = mwc
    malhas.append(cil)

# item na garra do braço
ITEM = None
if BRACO and 'garra' in PARTES:
    bpy.ops.mesh.primitive_cube_add(size=0.13)
    ITEM = bpy.context.object
    mi = bpy.data.materials.new('item'); mi.use_nodes = True
    next(n for n in mi.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs['Base Color'].default_value = (0.62, 0.30, 0.12, 1)
    ITEM.data.materials.append(mi)
    ITEM.parent = PARTES['garra']; ITEM.location = (0, 0, -float(M.get('garra', {}).get('item', 0.06)))
    malhas.append(ITEM)

# ------------------------------------------------------------------ material "realista e escuro" (só o modelo)
for im in list(bpy.data.images):
    if im.size[0] > 128:
        im.scale(128, 128)
FAIXAS = [(0.0, (0.10, 0.11, 0.14)), (0.03, (0.24, 0.24, 0.28)), (0.12, (0.45, 0.44, 0.45)), (0.3, (0.72, 0.69, 0.66)), (0.6, (0.92, 0.86, 0.76))]
BRILHOS = []          # (nó de emissão, força base, tipo)
OFFSETS = []          # (nó valor, velocidade) da lona


TEIA_PNG = os.path.join(JOGO, 'assets', 'texturas', 'teia.png')


def teia(m):
    """Véu de seda (P_Teia, P_TeiaSuja): a textura dos fios com recorte de alfa, como no jogo."""
    nt = m.node_tree
    p = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    tx = nt.nodes.new('ShaderNodeTexImage')
    tx.image = bpy.data.images.load(TEIA_PNG, check_existing=True)
    tx.interpolation = 'Closest'
    mx = nt.nodes.new('ShaderNodeMix'); mx.data_type = 'RGBA'; mx.blend_type = 'MULTIPLY'
    mx.inputs['Factor'].default_value = 1.0
    mx.inputs['B'].default_value = tuple(p.inputs['Base Color'].default_value)
    nt.links.new(tx.outputs['Color'], mx.inputs['A'])
    nt.links.new(mx.outputs['Result'], p.inputs['Base Color'])
    al = nt.nodes.new('ShaderNodeMath'); al.operation = 'GREATER_THAN'; al.inputs[1].default_value = 0.3
    nt.links.new(tx.outputs['Alpha'], al.inputs[0])
    nt.links.new(al.outputs[0], p.inputs['Alpha'])
    if hasattr(m, 'surface_render_method'):
        m.surface_render_method = 'DITHERED'
    if hasattr(m, 'blend_method'):
        m.blend_method = 'CLIP'
    m.use_backface_culling = False


def converter(m):
    if LARVA:                                       # gosma translúcida (baba, escorrido, ovo melado): no sprite, cor opaca
        pr = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        t = pr and (pr.inputs.get('Transmission Weight') or pr.inputs.get('Transmission'))
        if t is not None:
            t.default_value = 0.0
    if m.name.split('.')[0] in ('P_Teia', 'P_TeiaSuja'):
        teia(m)                                     # seda fica clara e com recorte (sem o escurecer dos modelos)
        return
    nt = m.node_tree
    p = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if not p:
        return
    base_nome = m.name.split('.')[0]
    for n in nt.nodes:
        if n.type == 'TEX_IMAGE':
            n.interpolation = 'Closest'
    cor_lig = p.inputs['Base Color'].links[0].from_socket if p.inputs['Base Color'].is_linked else None
    cor_val = tuple(p.inputs['Base Color'].default_value)
    emi_cor = tuple(p.inputs['Emission Color'].default_value)
    emi_for = float(p.inputs['Emission Strength'].default_value)
    emi_lig = p.inputs['Emission Color'].links[0].from_socket if p.inputs['Emission Color'].is_linked else None
    out = next(n for n in nt.nodes if n.type == 'OUTPUT_MATERIAL')
    hs = nt.nodes.new('ShaderNodeHueSaturation')
    hs.inputs['Saturation'].default_value = 0.78; hs.inputs['Value'].default_value = 0.72
    if cor_lig:
        nt.links.new(cor_lig, hs.inputs['Color'])
    else:
        hs.inputs['Color'].default_value = cor_val
    cor = hs.outputs['Color']
    if base_nome in LONA:                         # ranhuras transversais andando (4 por metro), como no shader do jogo
        # distância ao longo do fluxo pela geometria (a lona não tem UV próprio): reta = −y; curva = arco
        tc = nt.nodes.new('ShaderNodeTexCoord')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ'); nt.links.new(tc.outputs['Object'], sep.inputs[0])
        def mat(op, a, b):
            n = nt.nodes.new('ShaderNodeMath'); n.operation = op
            for i, v in enumerate((a, b)):
                if isinstance(v, (int, float)):
                    n.inputs[i].default_value = v
                else:
                    nt.links.new(v, n.inputs[i])
            return n.outputs[0]
        if 'curva_dir' in NOME or 'curva_esq' in NOME:
            cx = 0.5 if 'curva_dir' in NOME else -0.5
            th = mat('ARCTAN2', mat('ADD', sep.outputs['Y'], 0.5), mat('SUBTRACT', sep.outputs['X'], cx))
            dist = mat('MULTIPLY', mat('SUBTRACT', th, math.pi), 0.5) if cx > 0 else mat('MULTIPLY', th, -0.5)
        else:
            dist = mat('MULTIPLY', sep.outputs['Y'], -1.0)
        off = nt.nodes.new('ShaderNodeValue'); off.outputs[0].default_value = 0.0
        soma = nt.nodes.new('ShaderNodeMath'); soma.operation = 'ADD'
        nt.links.new(dist, soma.inputs[0]); nt.links.new(off.outputs[0], soma.inputs[1])
        vez = nt.nodes.new('ShaderNodeMath'); vez.operation = 'MULTIPLY'; vez.inputs[1].default_value = 4.0
        nt.links.new(soma.outputs[0], vez.inputs[0])
        fr = nt.nodes.new('ShaderNodeMath'); fr.operation = 'FRACT'; nt.links.new(vez.outputs[0], fr.inputs[0])
        st = nt.nodes.new('ShaderNodeMath'); st.operation = 'GREATER_THAN'; st.inputs[1].default_value = 0.82
        nt.links.new(fr.outputs[0], st.inputs[0])
        k = nt.nodes.new('ShaderNodeMapRange'); k.inputs['To Min'].default_value = 1.0; k.inputs['To Max'].default_value = 1.9
        nt.links.new(st.outputs[0], k.inputs['Value'])
        mlt = nt.nodes.new('ShaderNodeMix'); mlt.data_type = 'RGBA'; mlt.blend_type = 'MULTIPLY'
        mlt.inputs['Factor'].default_value = 1.0
        nt.links.new(cor, mlt.inputs['A'])
        cv = nt.nodes.new('ShaderNodeCombineXYZ')
        for c in 'XYZ':
            nt.links.new(k.outputs[0], cv.inputs[c])
        nt.links.new(cv.outputs[0], mlt.inputs['B'])
        cor = mlt.outputs['Result']
        OFFSETS.append((off, LONA[base_nome]))
    dif = nt.nodes.new('ShaderNodeBsdfDiffuse'); s2r = nt.nodes.new('ShaderNodeShaderToRGB')
    rampa = nt.nodes.new('ShaderNodeValToRGB'); cr = rampa.color_ramp; cr.interpolation = 'CONSTANT'
    cr.elements[0].position = FAIXAS[0][0]; cr.elements[0].color = (*FAIXAS[0][1], 1)
    cr.elements[1].position = FAIXAS[1][0]; cr.elements[1].color = (*FAIXAS[1][1], 1)
    for pos, c in FAIXAS[2:]:
        e = cr.elements.new(pos); e.color = (*c, 1)
    mult = nt.nodes.new('ShaderNodeMix'); mult.data_type = 'RGBA'; mult.blend_type = 'MULTIPLY'
    mult.inputs['Factor'].default_value = 1.0
    nt.links.new(cor, mult.inputs['A'])
    nt.links.new(dif.outputs[0], s2r.inputs[0]); nt.links.new(s2r.outputs['Color'], rampa.inputs['Fac'])
    nt.links.new(rampa.outputs['Color'], mult.inputs['B'])
    gl = nt.nodes.new('ShaderNodeBsdfGlossy'); gl.inputs['Roughness'].default_value = 0.3
    s2g = nt.nodes.new('ShaderNodeShaderToRGB'); nt.links.new(gl.outputs[0], s2g.inputs[0])
    rg = nt.nodes.new('ShaderNodeValToRGB'); rg.color_ramp.interpolation = 'CONSTANT'
    rg.color_ramp.elements[0].color = (0, 0, 0, 1); rg.color_ramp.elements[1].position = 0.55
    rg.color_ramp.elements[1].color = (0, 0, 0, 1) if GRUPO == 'mapa' or LARVA or PASSARO else (0.32, 0.30, 0.27, 1)   # natureza não brilha como metal
    nt.links.new(s2g.outputs['Color'], rg.inputs['Fac'])
    soma = nt.nodes.new('ShaderNodeMix'); soma.data_type = 'RGBA'; soma.blend_type = 'ADD'; soma.inputs['Factor'].default_value = 1.0
    nt.links.new(mult.outputs['Result'], soma.inputs['A']); nt.links.new(rg.outputs['Color'], soma.inputs['B'])
    emi = nt.nodes.new('ShaderNodeEmission'); nt.links.new(soma.outputs['Result'], emi.inputs['Color'])
    br = nt.nodes.new('ShaderNodeEmission')
    if emi_lig:
        nt.links.new(emi_lig, br.inputs['Color'])
    else:
        br.inputs['Color'].default_value = emi_cor
    forca = min(emi_for, 2.0)
    if base_nome == 'P_Cristal' and forca <= 0.0:                  # cristal brilha fraco trabalhando
        br.inputs['Color'].default_value = (*cor_val[:3], 1); forca = 0.6
    br.inputs['Strength'].default_value = forca
    if forca > 0:
        BRILHOS.append((br, forca, base_nome))
    tot = nt.nodes.new('ShaderNodeAddShader')
    nt.links.new(emi.outputs[0], tot.inputs[0]); nt.links.new(br.outputs[0], tot.inputs[1])
    nt.links.new(tot.outputs[0], out.inputs['Surface'])


for m in {m for o in malhas for m in o.data.materials if m and m is not m_cabo}:
    converter(m)
for o in malhas:
    for pl in o.data.polygons:
        pl.use_smooth = False

# ------------------------------------------------------------------ ação do glb: grava as poses e desliga a ação
OBJS_ACAO = [o for o in sc.objects if o.animation_data and o.animation_data.action]
CACHE = {}
if acao is not None:
    f0, f1 = acao.frame_range
    for q in range(QUADROS):
        fs = int(round(f0 + (f1 - f0) * q / QUADROS))
        if fs not in CACHE:
            sc.frame_set(fs)
            CACHE[fs] = {o.name: o.matrix_basis.copy() for o in OBJS_ACAO}
    for o in OBJS_ACAO:
        o.animation_data.action = None
sc.frame_set(1)

# ------------------------------------------------------------------ animação (mesma lógica do animador.gd)
BASE = {n: o.matrix_basis.copy() for n, o in PARTES.items()}


def pos_rot(n, eixo, ang):
    b = BASE[n]
    PARTES[n].matrix_basis = Matrix.Translation(b.translation) @ Matrix.Rotation(ang, 4, eixo) @ b.to_3x3().to_4x4()


def pos_desloca(n, d):
    b = BASE[n]
    PARTES[n].matrix_basis = Matrix.Translation(b.translation + Vector(d)) @ b.to_3x3().to_4x4()


GIRO_ORIGEM = {'atras': math.pi, 'esquerda': math.pi / 2, 'direita': -math.pi / 2}
IK = {}
if BRACO:
    piv = {p['nome']: Vector((float(p['pivo'][1]), float(p['pivo'][2]))) for p in M['partes']}
    sh = piv.get('braco1', Vector((0, 0.36))); el = piv.get('braco2', Vector((0.1, 0.66))); wr = piv.get('garra', Vector((0.3, 0.32)))
    IK = {'sh': sh, 'l1': (el - sh).length, 'l2': (wr - el).length, 'f1': math.atan2(*(el - sh).yx),
          'f2': math.atan2(*(wr - el).yx), 'dz': float(M.get('garra', {}).get('pulso_dz', 0.0))}
    if 'camisa' in piv and 'haste' in piv:
        IK['pino'] = piv['camisa']; IK['olhal'] = piv['haste']; IK['th0'] = math.atan2(*(piv['haste'] - piv['camisa']).yx)
    alc = 1.0
    if 'estagio2' in nomes_p:
        alc = 2.0
    PEGA = SOLTA = Vector((alc, 0.42))


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def resolver(r, h):
    t = Vector((r, h)) - IK['sh']; l1, l2 = IK['l1'], IK['l2']
    d = min(max(t.length, abs(l1 - l2) + 0.01), l1 + l2 - 0.005)
    a1 = math.atan2(t.y, t.x) + math.acos(min(1, max(-1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
    a2 = a1 - (math.pi - math.acos(min(1, max(-1, (l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2)))))
    r1 = a1 - IK['f1']
    return r1, (a2 - IK['f2']) - r1, 0.0


def resolver_tele(r, h):
    l1 = IK['l1']
    f1 = math.radians(85) + (math.radians(15) - math.radians(85)) * min(1, max(0, (r - 0.36) / 1.64))
    elb = IK['sh'] + Vector((math.cos(f1), math.sin(f1))) * l1
    v = Vector((r, h)) - elb
    l2a = min(max(v.length, IK['l2']), IK['l2'] + 0.8)
    r1 = f1 - IK['f1']
    return r1, (math.atan2(v.y, v.x) - IK['f2']) - r1, l2a - IK['l2']


def pose_braco(fase, origem):
    ida = fase < 0.5
    x = (fase if ida else fase - 0.5) * 2.0
    de, para = (PEGA, SOLTA) if ida else (SOLTA, PEGA)
    alto = max(de.y, para.y) + 0.2
    sobe = smooth(0.0, 0.2, x); desce = smooth(0.8, 1.0, x); gira = smooth(0.15, 0.85, x)
    h = de.y + (alto - de.y) * sobe if x < 0.5 else alto + (para.y - alto) * desce
    r = de.x + (para.x - de.x) * gira
    g = GIRO_ORIGEM[origem]
    pos_rot('giro', 'Z', g * (1.0 - gira) if ida else g * gira)
    s1, s2, ext = (resolver_tele if 'estagio2' in nomes_p else resolver)(r, h + IK['dz'])
    pos_rot('braco1', 'X', s1); pos_rot('braco2', 'X', s2)
    for st in ('estagio2', 'estagio3'):
        if st in PARTES:
            pos_desloca(st, (0, ext * 0.5, 0))
    if 'camisa' in PARTES and 'haste' in PARTES and 'pino' in IK:
        sh = IK['sh']; ol = IK['olhal']; pino = IK['pino']
        d = ol - sh; c, s_ = math.cos(s1), math.sin(s1)
        p = sh + Vector((d.x * c - d.y * s_, d.x * s_ + d.y * c))
        th = math.atan2(*(p - pino).yx) - IK['th0']
        pos_rot('camisa', 'X', th); pos_rot('haste', 'X', th - s1)
    if 'garra' in PARTES:
        pos_rot('garra', 'X', -(s1 + s2))
    if ITEM is not None:
        ITEM.scale = (1, 1, 1) if ida else (0.001, 0.001, 0.001)


animados = list({o.name: o for o in list(PARTES.values()) + [PIVO] + OBJS_ACAO + ([ITEM] if ITEM else [])}.values())


# ------------------------------------------------------------------ aranha: a mesma conta do jogo (marcha_aranha.gd, aranha.gd)
# Tudo no espaço do Godot (x, y para cima, z para o sul) e convertido para o Blender no fim (x, −z, y).
G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
QUADRIL_Z, FEMUR_L, TIBIA_L = 0.55, 0.70, 0.90
QUADRIS = [(0.42, 0.35), (-0.42, 0.35), (0.42, 0.0), (-0.42, 0.0), (0.42, -0.35), (-0.42, -0.35)]
TRIPODE = [0, 1, 1, 0, 0, 1]                # [[0, 3, 4], [1, 2, 5]]
PASSO_FRENTE, PASSO_TRAS, ALTURA_PASSO = 0.26, 0.29, 0.25   # o pé pousa 0,26 m à frente da casa e sai 0,29 m atrás
UP = Vector((0, 1, 0))


def _no_blender(t):
    return G2B @ t @ G2B.inverted()


def _segmento(a, b):
    x = (b - a).normalized()
    z = x.cross(UP)
    z = Vector((0, 0, 1)) if z.length < 1e-4 else z.normalized()
    y = z.cross(x).normalized()
    m = Matrix.Identity(4)
    for r in range(3):
        m[r][0], m[r][1], m[r][2], m[r][3] = x[r], y[r], z[r], a[r]
    return m


def _ik(qd, pe):
    alvo = pe - qd
    d = min(max(alvo.length, abs(FEMUR_L - TIBIA_L) + 0.001), FEMUR_L + TIBIA_L - 0.001)
    hz = Vector((alvo.x, 0, alvo.z))
    dh = hz.normalized() if hz.length > 1e-6 else Vector((1, 0, 0))
    ca = min(1, max(-1, (FEMUR_L ** 2 + d * d - TIBIA_L ** 2) / (2 * FEMUR_L * d)))
    el = math.atan2(alvo.y, hz.length) + math.acos(ca)
    return qd + dh * FEMUR_L * math.cos(el) + UP * FEMUR_L * math.sin(el)


def pose_aranha(q, variante, rumo):
    R = Matrix.Rotation(rumo, 3, UP)
    frente = R @ Vector((0, 0, -1))
    quadril = [R @ Vector((x, QUADRIL_Z, -y)) for x, y in QUADRIS]
    casa = [R @ (Vector((x, 0, -y)) + Vector((x, 0, -y)).normalized()) for x, y in QUADRIS]
    u = q / QUADROS
    t = q / FPS
    pes = list(casa)
    corpo_y, corpo_rz = 0.0, 0.0
    if variante == 'andar':                 # trípode alternado: o pé plantado recua com o corpo, o outro trípode no ar
        corpo_y = 0.02 * math.sin(4 * math.pi * u)
        for i in range(6):
            s_ = (u - 0.5 * TRIPODE[i]) % 1.0
            fr, tr = casa[i] + frente * PASSO_FRENTE, casa[i] - frente * PASSO_TRAS
            if s_ < 0.5:
                f = s_ / 0.5; k = f * f * (3 - 2 * f)
                pes[i] = tr.lerp(fr, k) + UP * math.sin(f * math.pi) * ALTURA_PASSO
            else:
                pes[i] = fr.lerp(tr, (s_ - 0.5) / 0.5)
    elif variante == 'ataque':              # o par da frente golpeia alternado (2 golpes por segundo)
        for i in (0, 1):
            lado = (R @ Vector((QUADRIS[i][0], 0, 0))).normalized()
            f = 0.5 + 0.5 * math.sin(4 * math.pi * t + i * math.pi)
            pes[i] = Vector((quadril[i].x, 0, quadril[i].z)) + frente * (0.95 + 0.25 * f) + lado * 0.25 + UP * (0.15 + 0.55 * (1 - f))
    if variante == 'morte':                 # morrer(): em 0,6 s a barriga cai no chão (0,2 m), tomba 0,22 rad e os pés abrem 0,35 m
        k = min(t / 0.6, 1.0); g = k * k
        corpo_y, corpo_rz = -0.2 * g, 0.22 * g
        for i in range(6):
            fora = Vector((casa[i].x - quadril[i].x, 0, casa[i].z - quadril[i].z)).normalized()
            quadril[i] = quadril[i] + Vector((0, -0.2 * g, 0))
            pes[i] = casa[i] + fora * 0.35 * k
    segs = []
    for i in range(6):
        jo = _ik(quadril[i], pes[i])
        segs.append((_segmento(quadril[i], jo), _segmento(jo, pes[i])))
    corpo = Matrix.Rotation(rumo, 4, UP) @ Matrix.Translation((0, corpo_y, 0)) @ Matrix.Rotation(corpo_rz, 4, Vector((0, 0, 1)))
    AR_CORPO.matrix_world = _no_blender(corpo)
    for i in range(6):
        AR_FEMUR[i].matrix_world = _no_blender(segs[i][0])
        AR_TIBIA[i].matrix_world = _no_blender(segs[i][1])


def pose(q, variante, linha):
    """q = quadro (0..QUADROS-1), linha = rotação/direção."""
    u = q / QUADROS                                             # 0..1 no laço
    if PASSARO:
        # o estudo monta o pássaro olhando para +X; no jogo a linha 0 é olhando para o norte (+Y aqui, para cima
        # na tela): +90° (o 3D faz o mesmo girando o modelo)
        PIVO.matrix_basis = Matrix.Rotation(2 * math.pi * linha / DIRECOES + math.pi / 2, 4, 'Z')
        {'voo': NS_P['pose_voo'], 'planar': NS_P['pose_planar'], 'parado': NS_P['pose_parado'],
         'bicando': NS_P['pose_bicar'], 'pousar': lambda a, u: NS_P['pose_pousar'](a, q / (QUADROS - 1))}[variante](ARM_P, q / QUADROS)
        return
    if NOME == 'larva_acida':                 # (o estudo também monta a larva olhando para +X: +90°, como o pássaro)
        PIVO.matrix_basis = Matrix.Rotation(2 * math.pi * linha / DIRECOES + math.pi / 2, 4, 'Z')
        arm = bpy.data.objects['larva']
        if variante == 'andar':
            NS_LARVA['pose_rastejar'](arm, q / QUADROS, 1)
        else:                                   # cuspe: ergue e abre (0..0,5 s), segura, solta e volta
            k = min(1.0, q / 5.0) if q < 8 else max(0.0, 1.0 - (q - 7) / 4.0)
            NS_LARVA['pose_cuspe'](arm, None, k)
        return
    if ARANHA:
        PIVO.matrix_basis = Matrix.Identity(4)
        pose_aranha(q, variante, 2 * math.pi * linha / DIRECOES)
        return
    if acao is not None:
        f0, f1 = acao.frame_range
        for nm, mb in CACHE[int(round(f0 + (f1 - f0) * u))].items():
            bpy.data.objects[nm].matrix_basis = mb
    if BRACO:
        pose_braco(u, variante)
    if 'rotor' in PARTES:
        pos_rot('rotor', 'Z', 2 * math.pi * 2 * u)
    if variante == 'tiro' and 'canhao' in PARTES:
        pos_desloca('canhao', (0, -RECUO * PERFIL_RECUO[q % len(PERFIL_RECUO)], 0))
        if 'tambor' in PARTES:
            pos_rot('tambor', 'Y', math.radians(60) * q)
    elif 'canhao' in PARTES and variante == 'base' and DIRECOES:
        pos_desloca('canhao', (0, 0, 0))
    for k in range(4):
        if 'rotor%d' % k in PARTES:
            pos_rot('rotor%d' % k, 'Z', 2 * math.pi * u * (1 if k % 2 else -1) + k)
    if 'antena' in PARTES:
        pos_rot('antena', 'Z', 2 * math.pi * u)
    if 'helice' in PARTES:
        pos_rot('helice', Vector((0, -1, 0)), 2 * math.pi * 2 * u)
    if 'cristal' in PARTES:
        s = 1.0 + 0.06 * math.sin(2 * math.pi * 2 * u)
        b = BASE['cristal']; PARTES['cristal'].matrix_basis = b @ Matrix.Scale(s, 4)
    for no, base, tipo in BRILHOS:
        if QUADROS > 1:
            if tipo == 'P_Fogo':
                ch = 0.5 * math.sin(2 * math.pi * 7 * u + 0.4) + 0.3 * math.sin(2 * math.pi * 13 * u + 1.9) + 0.2 * math.sin(2 * math.pi * 29 * u + 3.1)
                no.inputs['Strength'].default_value = base * (1.1 + 0.4 * ch)
            elif tipo == 'P_Cristal':
                no.inputs['Strength'].default_value = base * (1.0 + 0.5 * math.sin(2 * math.pi * 2 * u))
    for off, vel in OFFSETS:
        off.outputs[0].default_value = 0.25 * vel * u               # vel = períodos de ranhura por laço
    # linha: rotação da construção ou direção
    if DIRECOES:
        ang = 2 * math.pi * linha / DIRECOES
        if 'giro' in PARTES and 'canhao' in PARTES:
            pos_rot('giro', 'Z', ang); PIVO.matrix_basis = Matrix.Identity(4)
        else:
            PIVO.matrix_basis = Matrix.Rotation(ang, 4, 'Z')
    else:
        PIVO.matrix_basis = Matrix.Rotation(math.pi / 2 * ROTS[linha], 4, 'Z')


LINHAS = DIRECOES if DIRECOES else len(ROTS)

# o que está abaixo do chão (broca, bomba, base enterrada) não aparece: plano "holdout" no nível do chão
# (só para o que fica no chão; drone e aranha voam ou andam e não são cortados)
CORTA_CHAO = (GRUPO not in ('drones', 'inimigos') and NOME != 'nucleo_queda') or ARANHA   # a aranha morta afunda
# ------------------------------------------------------------------ enquadramento: tudo de todas as linhas e quadros + sombra
bpy.context.view_layer.update()
R_cam = cam.rotation_euler.to_matrix()
ex, ey = R_cam @ Vector((1, 0, 0)), R_cam @ Vector((0, 1, 0))
xs, ys = [], []
amostras = list(range(0, QUADROS, 1 if os.environ.get("TODAS") else max(1, QUADROS // 16)))         # mede em até 16 quadros do laço
for var in VARIANTES:
    for li in range(LINHAS):
        for q in amostras:
            pose(q, var, li); bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            for o in malhas:
                oe = o.evaluated_get(dg); me = oe.to_mesh(); mw = o.matrix_world
                co = np.empty(len(me.vertices) * 3, dtype=np.float32); me.vertices.foreach_get('co', co)
                oe.to_mesh_clear()
                if not len(co):
                    continue
                P = co.reshape(-1, 3)
                P = (np.array(mw)[:3, :3] @ P.T).T + np.array(mw.translation)
                if CORTA_CHAO:
                    P[:, 2] = np.maximum(P[:, 2], 0.0)       # o que fica embaixo do chão não aparece
                # pássaro: só ele (a sombra das asas erguidas no ar seria de metros; no jogo a sombra vai para o chão)
                for pts in ((P,) if PASSARO else (P, P - np.outer(np.maximum(P[:, 2], 0) / max(DIR_SOL.z, 0.2), np.array(DIR_SOL)))):
                    xs.extend([float((pts @ np.array(ex)).min()), float((pts @ np.array(ex)).max())])
                    ys.extend([float((pts @ np.array(ey)).min()), float((pts @ np.array(ey)).max())])
if os.environ.get('DBG_ENQ'):
    print('ENQ', min(xs), max(xs), min(ys), max(ys), [o.name for o in malhas])
    sys.exit(0)
MARG = 3
W = int(math.ceil((max(xs) - min(xs)) / PX)) + 2 * MARG
H = int(math.ceil((max(ys) - min(ys)) / PX)) + 2 * MARG
W += W % 2; H += H % 2
cx = (max(xs) + min(xs)) / 2; cy = (max(ys) + min(ys)) / 2
centro = ex * cx + ey * cy
cam.location = centro + DIR_CAM * 30
cam_d.ortho_scale = max(W, H) * PX
cam_d.clip_end = 100
sc.render.resolution_x, sc.render.resolution_y = W, H
# âncora: o centro do tile (origem) em pixels, de cima para baixo
p0 = Vector((0, 0, 0)) - centro
ANCORA = [round(W / 2 + p0.dot(ex) / PX, 1), round(H / 2 - p0.dot(ey) / PX, 1)]

# ------------------------------------------------------------------ boca do cano por direção (torre, drone de defesa)
# a ponta da peça "canhao" (e filhas) mais à frente na mira, em coordenadas do Godot relativas à origem do modelo:
# os efeitos do 2D (clarão, traçante, cápsula) saem dali, e não do meio da torre
BOCA = []
if DIRECOES and 'canhao' in PARTES:
    can = PARTES['canhao']
    def _desce_de(o, pai):
        while o is not None:
            if o is pai:
                return True
            o = o.parent
        return False
    pecas_can = [o for o in malhas if _desce_de(o, can)]
    for li in range(LINHAS):
        pose(0, 'base', li); bpy.context.view_layer.update()
        frente = Matrix.Rotation(2 * math.pi * li / DIRECOES, 3, 'Z') @ Vector((0, 1, 0))
        dg = bpy.context.evaluated_depsgraph_get()
        pts = []
        for o in pecas_can:
            oe = o.evaluated_get(dg); me = oe.to_mesh()
            pts += [o.matrix_world @ v.co for v in me.vertices]
            oe.to_mesh_clear()
        if not pts:
            break
        dmax = max(p.dot(frente) for p in pts)
        ponta = [p for p in pts if p.dot(frente) > dmax - 0.012]
        c = sum(ponta, Vector()) / len(ponta)
        BOCA.append([round(c.x, 3), round(c.z, 3), round(-c.y, 3)])
    pose(0, VARIANTES[0], 0); bpy.context.view_layer.update()

# ------------------------------------------------------------------ chão da sombra (só aparece no passe S)
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0.0))
CHAO = bpy.context.object
mch = bpy.data.materials.new('chao'); mch.use_nodes = True
pch = next(n for n in mch.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
pch.inputs['Base Color'].default_value = (0.8, 0.8, 0.8, 1); pch.inputs['Roughness'].default_value = 1.0
CHAO.data.materials.append(mch)
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -0.005))
CORTE = bpy.context.object
CORTE.is_holdout = True

# ------------------------------------------------------------------ keyframes de toda a sequência (variante, linha, quadro)
SEQ = [(var, li, q) for var in VARIANTES for li in range(LINHAS) for q in range(QUADROS)]
for o in animados:
    o.rotation_mode = 'QUATERNION'
cristal_rot = 'cristal' in PARTES
for i, (var, li, q) in enumerate(SEQ):
    pose(q, var, li)
    fr = 1000 + i
    for o in animados:
        o.keyframe_insert('location', frame=fr); o.keyframe_insert('rotation_quaternion', frame=fr); o.keyframe_insert('scale', frame=fr)
    for pb in (OSSOS if NOME == 'larva_acida' or PASSARO else []):
        pb.keyframe_insert('location', frame=fr); pb.keyframe_insert('rotation_euler', frame=fr); pb.keyframe_insert('scale', frame=fr)
    for no, _, _ in BRILHOS:
        no.inputs['Strength'].keyframe_insert('default_value', frame=fr)
    for off, _ in OFFSETS:
        off.outputs[0].keyframe_insert('default_value', frame=fr)
for o in sc.objects:
    ad = o.animation_data
    if ad and ad.action:
        for fc in getattr(ad.action, 'fcurves', []) or []:
            for kp in fc.keyframe_points:
                kp.interpolation = 'CONSTANT'
for mt in bpy.data.materials:
    ad = mt.node_tree.animation_data if mt.node_tree else None
    if ad and ad.action:
        for fc in getattr(ad.action, 'fcurves', []) or []:
            for kp in fc.keyframe_points:
                kp.interpolation = 'CONSTANT'
sc.frame_start, sc.frame_end = 1000, 1000 + len(SEQ) - 1

# ------------------------------------------------------------------ três passes
TMP = os.path.join(SAIDA, '_tmp'); os.makedirs(TMP, exist_ok=True)


def passe(nome, escala, transparente, chao):
    em.inputs['Color'].default_value = (1, 0, 1, 1) if nome == 'B' else (0.09, 0.07, 0.06, 1)
    sc.render.resolution_x, sc.render.resolution_y = W * escala, H * escala
    sc.render.film_transparent = transparente
    CHAO.hide_render = not chao
    CORTE.hide_render = chao or not CORTA_CHAO
    for o in malhas:
        o.visible_camera = not chao
    sc.render.filepath = os.path.join(TMP, nome + '_')
    sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
    bpy.ops.render.render(animation=True)


passe('A', SUPER, True, False)
passe('B', 1, True, False)
passe('S', 2, False, True)


def ler(caminho):
    im = bpy.data.images.load(caminho)
    w, h = im.size
    a = np.empty(w * h * 4, dtype=np.float32); im.pixels.foreach_get(a)
    bpy.data.images.remove(im)
    return a.reshape(h, w, 4)[::-1]                   # de cima para baixo


def reduzir(a, k):
    h, w = a.shape[0] // k, a.shape[1] // k
    a = a[:h * k, :w * k].reshape(h, k, w, k, 4)
    al = a[..., 3].mean(axis=(1, 3))
    cor = (a[..., :3] * a[..., 3:4]).sum(axis=(1, 3)) / np.maximum(a[..., 3].sum(axis=(1, 3)), 1e-6)[..., None]
    return np.concatenate([cor, al[..., None]], axis=2)


def salvar(arr, caminho):
    h, w = arr.shape[:2]
    im = bpy.data.images.new('s', w, h, alpha=True)
    im.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).astype(np.float32).ravel())
    im.filepath_raw = caminho; im.file_format = 'PNG'; im.save()
    bpy.data.images.remove(im)


COR_CABO = np.array([0.09, 0.07, 0.06]); COR_BORDA = np.array([0.035, 0.028, 0.03])
quadros_cor = []; quadros_sombra = []
avisos = []
for i in range(len(SEQ)):
    fr = 1000 + i
    A = reduzir(ler(os.path.join(TMP, 'A_%04d.png' % fr)), SUPER)
    B = ler(os.path.join(TMP, 'B_%04d.png' % fr))
    S = reduzir(ler(os.path.join(TMP, 'S_%04d.png' % fr)), 2)
    cabo = (B[..., 0] > 0.85) & (B[..., 1] < 0.2) & (B[..., 2] > 0.85) & (B[..., 3] > 0.5)
    corpo = (B[..., 3] > 0.5) | (A[..., 3] > 0.5)
    cor = np.where((A[..., 3] > 0.2)[..., None], A[..., :3], B[..., :3])
    cor[cabo] = COR_CABO
    out = np.zeros((H, W, 4), dtype=np.float32)
    out[corpo, :3] = cor[corpo]; out[corpo, 3] = 1.0
    m = corpo
    viz = np.zeros_like(m)
    viz[1:] |= m[:-1]; viz[:-1] |= m[1:]; viz[:, 1:] |= m[:, :-1]; viz[:, :-1] |= m[:, 1:]
    borda = viz & ~m
    if NOME == 'cratera_larva':
        # a cratera sai do chão: sem contorno escuro; a beira some em pontilhado (5 px) para o chão corroído aparecer
        dist = np.zeros(m.shape, dtype=np.float32)
        dentro = m.copy()
        for passo in range(1, 6):
            v = np.zeros_like(dentro)
            v[1:] |= ~dentro[:-1]; v[:-1] |= ~dentro[1:]; v[:, 1:] |= ~dentro[:, :-1]; v[:, :-1] |= ~dentro[:, 1:]
            anel = dentro & v
            dist[anel] = passo
            dentro = dentro & ~anel
        dist[dentro] = 6
        bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0
        lim = np.tile(bayer, (H // 4 + 1, W // 4 + 1))[:H, :W]
        some = m & (dist / 6.0 < lim + 0.05)
        out[some, 3] = 0.0
    else:
        out[borda, :3] = COR_BORDA; out[borda, 3] = 1.0
    if m[0].any() or m[-1].any() or m[:, 0].any() or m[:, -1].any():
        avisos.append('cortado no quadro %d' % i)
    lum = S[..., :3].mean(axis=2)
    claro = np.percentile(lum, 95)
    sombra = (lum < claro * 0.72)
    so_ = np.zeros((H, W, 4), dtype=np.float32); so_[sombra, 3] = 0.5
    quadros_cor.append(out); quadros_sombra.append(so_)

# folhas: uma por variante; linhas = rotações/direções, colunas = quadros
os.makedirs(SAIDA, exist_ok=True)
meta = {'nome': NOME, 'categoria': CAT, 'quadro': [W, H], 'ancora': ANCORA, 'fps': FPS, 'quadros': QUADROS,
        'linhas': LINHAS, 'tipo_linha': ('direcao' if DIRECOES else 'rotacao'),
        'angulos_graus': [round(360 * li / DIRECOES, 2) for li in range(DIRECOES)] if DIRECOES else [90 * r for r in ROTS],
        'variantes': VARIANTES, 'metros_por_pixel': PX, 'camera_elevacao_graus': 35, 'cabos': len(CABOS),
        'animacao': ('passaro' if PASSARO else 'larva' if NOME == 'larva_acida' else 'aranha' if ARANHA else 'trabalho' if acao is not None else 'braco' if BRACO else 'pecas' if QUADROS > 1 else 'parado'),
        'avisos': avisos}
if BOCA:
    meta['boca'] = BOCA
for vi, var in enumerate(VARIANTES):
    for tipo, lista in (('', quadros_cor), ('_sombra', quadros_sombra)):
        folha = np.zeros((H * LINHAS, W * QUADROS, 4), dtype=np.float32)
        for li in range(LINHAS):
            for q in range(QUADROS):
                folha[li * H:(li + 1) * H, q * W:(q + 1) * W] = lista[(vi * LINHAS + li) * QUADROS + q]
        suf = '' if var == 'base' else '_' + var
        salvar(folha, os.path.join(SAIDA, NOME + suf + tipo + '.png'))
json.dump(meta, open(os.path.join(SAIDA, NOME + '.json'), 'w'), indent=1, ensure_ascii=False)
import shutil
shutil.rmtree(TMP, ignore_errors=True)
print('SPRITE_OK', NOME, W, H, 'linhas', LINHAS, 'quadros', QUADROS, 'variantes', len(VARIANTES), 'cabos', len(CABOS), 'avisos', len(avisos))
