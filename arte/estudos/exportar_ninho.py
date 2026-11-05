"""Ninhos para o jogo (patch fauna, fase 6): monta a taça e a bolsa na qualidade do jogo (estudo_ninho.py), assa a cor
dos materiais (procedurais) numa textura, troca por material simples e exporta (sem esqueleto). Depois acha, em cada
modelo de árvore do jogo, onde o ninho fica, e grava em jogo/dados/ninhos_arvores.json (coordenadas do modelo no
Godot: x, y para cima, z = −y do Blender):
  "taca":  [[x, y, z]]           a forquilha (onde o tronco se abre nos galhos); sem forquilha (pinheiro), encostada
                                 no tronco a ~60% da altura;
  "bolsa": [[x, y, z, giro, gx, gy, gz]…]  até 3, cada uma num lado, na beira de baixo da copa (pende para fora da
                                 folhagem); o raminho dela (−x do modelo) aponta para a ponta de galho (gx, gy, gz), de
                                 onde o jogo puxa um raminho fino até ela.
Uso: blender -b --python exportar_ninho.py"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import base3d
import estudo_ninho as E

JOGO = os.path.join(AQUI, '..', '..', 'jogo')
SAIDA = os.path.join(AQUI, '..', 'modelos', 'fauna', 'ninhos')
NOMES = {'taca': 'Ninho em taça (pardelo, rubro): gravetos e capim na forquilha da árvore',
         'bolsa': 'Ninho em bolsa tecida (cobrico, azulão): pende da ponta de um galho'}


def assar_e_exportar(o, nome):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 8
    me = o.data
    uv = me.uv_layers.new(name='bake')
    me.uv_layers.active = uv
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode='OBJECT')
    img = bpy.data.images.new(f'{nome}_cor', 256, 256)
    for m in me.materials:
        nt = m.node_tree
        tx = nt.nodes.new('ShaderNodeTexImage')
        tx.image = img
        nt.nodes.active = tx
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=3)
    img.pack()
    for u in [u for u in me.uv_layers if u.name != 'bake']:
        me.uv_layers.remove(u)
    mt = bpy.data.materials.new(f'{nome}_Tex')
    b = mt.node_tree.nodes['Principled BSDF']
    tx = mt.node_tree.nodes.new('ShaderNodeTexImage')
    tx.image = img
    mt.node_tree.links.new(tx.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.9
    me.materials.clear()
    me.materials.append(mt)
    pasta = os.path.join(SAIDA, nome)
    os.makedirs(pasta, exist_ok=True)
    glb = os.path.join(pasta, nome + '.glb')
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_yup=True, export_image_format='JPEG')
    pts = [o.matrix_world @ v.co for v in me.vertices]
    dims = [round(max(p[i] for p in pts) - min(p[i] for p in pts), 3) for i in range(3)]
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    json.dump({'nome': nome, 'categoria': 'fauna/ninhos', 'tipo': 'veiculo', 'area': [1, 1],
               'descricao': NOMES[nome.split('_')[1]] + ' (patch fauna, fase 6).', 'ocupa_canto': False,
               'partes': [{'nome': 'corpo', 'pai': None, 'pivo': [0.0, 0.0, 0.0]}], 'portas': [],
               'tris': tris, 'dims': dims, 'anima': False, 'estudo': 'estudo_ninho.py'},
              open(os.path.join(pasta, nome + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('NINHO_EXPORTADO', nome, tris, 'tris', dims)


for tipo in ('taca', 'bolsa'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = base3d.iniciar()
    M = E.materiais()
    if tipo == 'taca':
        o = E.objeto(sc, 'ninho_taca', E.ninho_taca(True), [M['graveto'], M['casca_taca'], M['forro']])
    else:
        o = E.objeto(sc, 'ninho_bolsa', E.ninho_bolsa(jogo=True), [M['graveto'], M['trama'], M['boca']])
    assar_e_exportar(o, 'ninho_' + tipo)


# ------------------------------------------------------------------ onde o ninho fica em cada árvore
def godot(v, giro=None):
    p = [round(v.x, 4), round(v.z, 4), round(-v.y, 4)]
    return p + [round(giro, 4)] if giro is not None else p


def pontos_da_arvore(arq):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=arq)
    malha = next(o for o in bpy.context.scene.objects if o.type == 'MESH')
    bpy.context.view_layer.update()
    mats = malha.data.materials
    casca_i = [i for i, m in enumerate(mats) if m is not None and 'Folha' not in m.name]
    vs = set()
    for p in malha.data.polygons:
        if p.material_index in casca_i or len(casca_i) == len(mats):
            vs.update(p.vertices)
    gs = [malha.matrix_world @ malha.data.vertices[i].co for i in vs]
    todos = [malha.matrix_world @ v.co for v in malha.data.vertices]
    alto = max(v.z for v in todos)
    base = [g for g in gs if g.z < 0.5] or gs
    eixo = sum(base, Vector()) / len(base)
    # taça: a forquilha
    z_abre = None
    for k in range(int(0.6 / 0.02), int(alto * 0.85 / 0.02)):
        z = k * 0.02
        fatia = [g for g in gs if abs(g.z - z) < 0.02]
        if fatia and max(Vector((g.x - eixo.x, g.y - eixo.y)).length for g in fatia) > 0.085:
            z_abre = z
            break
    if z_abre is not None:
        taca = Vector((eixo.x, eixo.y, z_abre - 0.01))
    else:                                                   # sem forquilha: encostada no tronco
        z = alto * 0.6
        fatia = [g for g in gs if abs(g.z - z) < 0.03] or gs
        dist = sorted(Vector((g.x - eixo.x, g.y - eixo.y)).length for g in fatia)
        r_tronco = dist[len(dist) // 4]                    # o tronco (os galhos em volta ficam mais longe)
        taca = Vector((eixo.x + r_tronco + 0.045, eixo.y, z - 0.01))
    # bolsas: na beira de baixo da copa (penduradas para fora da folhagem: aparecem o ano todo), cada uma num lado,
    # presas por um raminho fino que vem da ponta de galho mais perto daquele lado
    folha_i = [i for i, m in enumerate(mats) if m is not None and 'Folha' in m.name]
    fv = set()
    for p in malha.data.polygons:
        if p.material_index in folha_i:
            fv.update(p.vertices)
    folha = [malha.matrix_world @ malha.data.vertices[i].co for i in fv]
    z_min = (z_abre if z_abre is not None else alto * 0.5) + 0.05
    pontas = [g for g in gs if g.z > z_min and Vector((g.x - eixo.x, g.y - eixo.y)).length > 0.06]
    bolsas = []
    usados = []
    for k in range(8):                                      # lados bem separados primeiro (passos de ~137°)
        if len(bolsas) >= 3:
            break
        ang = -0.6 + k * 2.4
        d = Vector((math.cos(ang), math.sin(ang), 0))
        if any(math.cos(ang - u) > 0.5 for u in usados):
            continue
        if pontas:
            galho = max(pontas, key=lambda g: Vector((g.x - eixo.x, g.y - eixo.y, 0)).dot(d))
        else:                                               # sem galho modelado (pinheiro): do lado do tronco, a 60%
            zt = alto * 0.6
            fatia = [g for g in gs if abs(g.z - zt) < 0.04] or gs
            dist = sorted(Vector((g.x - eixo.x, g.y - eixo.y)).length for g in fatia)
            galho = Vector((eixo.x, eixo.y, zt)) + d * dist[len(dist) // 4]
        lado = [f for f in folha if Vector((f.x - eixo.x, f.y - eixo.y, 0)).normalized().dot(d) > 0.8] or folha
        z_baixo = min(f.z for f in lado) if lado else 0.0
        if folha and z_baixo > alto * 0.45:                 # copa alta: na beira de baixo dela, por fora
            r_copa = max(Vector((f.x - eixo.x, f.y - eixo.y)).length for f in lado)
            topo_b = Vector((eixo.x, eixo.y, 0)) + d * (r_copa * 0.92) + Vector((0, 0, z_baixo + 0.02))
            topo_b.z = min(topo_b.z, galho.z)
        else:                                               # copa até o chão (pinheiro, salgueiro) ou sem folha
            topo_b = galho + d * 0.05 - Vector((0, 0, 0.02))   # (fungo): pende da ponta do galho / do chapéu
        usados.append(ang)
        dx, dy = galho.x - topo_b.x, galho.y - topo_b.y      # o raminho do modelo (−x) aponta para o galho
        giro = math.atan2(-dy, -dx) if abs(dx) + abs(dy) > 1e-4 else 0.0   # R_y(θ)·(−1,0,0) = (dx, 0, −dy) no Godot
        bolsas.append(godot(topo_b, giro) + godot(galho))
    return {'taca': [godot(taca)], 'bolsa': bolsas, 'forquilha': z_abre is not None}


VEG = os.path.join(JOGO, 'assets', 'modelos', 'mapa', 'vegetacao')
arvores = sorted(f[:-4] for f in os.listdir(VEG) if f.endswith('.glb') and (f.startswith('arv_') or f in ('arvore_campina_a.glb', 'arvore_campina_b.glb')))
saida = {'_nota': 'fase 6 do patch fauna (exportar_ninho.py): onde fica o ninho em cada modelo de árvore, nas coordenadas do modelo no Godot. taca = a forquilha (ou encostada no tronco); bolsa = [x, y, z, giro] onde a bolsa é amarrada, perto da ponta de um galho (giro aponta o raminho dela para o galho).'}
for n in arvores:
    p = pontos_da_arvore(os.path.join(VEG, n + '.glb'))
    print('ARVORE', n, 'forquilha' if p.pop('forquilha') else 'tronco', p['taca'][0], len(p['bolsa']), 'bolsas')
    saida[n] = p
json.dump(saida, open(os.path.join(JOGO, 'dados', 'ninhos_arvores.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('NINHOS_OK', len(arvores))
