"""Fauna grande e peixes para o jogo (glb com esqueleto), um por espécie (patch fauna, fase 9): monta o estudo
(estudo_fauna_grande.py ou estudo_peixe.py) na qualidade do jogo, assa a cor dos materiais (procedurais) numa textura
256², troca por material simples e exporta com o esqueleto e as ações (24 quadros/s, uma trilha NLA por ação):
  herbívoros (galhudo, corcova): "andar" 12 · "correr" 12 · "pastar" 24 · "alerta" 24 · "morto" 2
  predadores (uivador, espreitador): "andar" 12 · "correr" 12 · "espreitar" 12 · "morder" 12 · "comer" 24 ·
                                     "deitado" 24 · "morto" 2
  peixes (couraca, couraca_rubra): "nadar" 12 · "pulo" 12 · "morto" 2
"andar", "correr" e "espreitar": um ciclo; o pé de apoio desliza para trás no ritmo do bicho andando (CICLO_M abaixo:
metros andados por ciclo, para o jogo acompanhar a distância sem escorregar o pé).
Uso: blender -b --python exportar_fauna.py -- <id> [<id>…]"""
import bpy, math, os, sys, json

AQUI = os.path.dirname(os.path.abspath(__file__))
IDS = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else ['galhudo']
SAIDAS = {   # id: (estudo, categoria, nome do modelo, descrição)
    'galhudo': ('estudo_fauna_grande.py', 'fauna/herbivoros', 'herbivoro_galhudo',
                'Galhudo: herbívoro nativo de manada (patch fauna, fase 9), ungulado esguio com duas placas ósseas na testa '
                'e nódulos na nuca'),
    'corcova': ('estudo_fauna_grande.py', 'fauna/herbivoros', 'herbivoro_corcova',
                'Corcova: herbívoro nativo pesado (patch fauna, fase 9), bovídeo de corcova com chifres curtos e nódulos de osso'),
    'uivador': ('estudo_fauna_grande.py', 'fauna/predadores', 'predador_uivador',
                'Uivador: predador nativo de matilha (patch fauna, fase 9), canídeo com crista curta de placas ósseas'),
    'espreitador': ('estudo_fauna_grande.py', 'fauna/predadores', 'predador_espreitador',
                    'Espreitador: predador nativo solitário (patch fauna, fase 9), felino pintado com esporões ósseos nos pulsos'),
    'couraca': ('estudo_peixe.py', 'fauna/peixes', 'peixe_couraca',
                'Couraça: peixe nativo dos lagos (patch fauna, fase 9), com placas ósseas na cabeça'),
    'couraca_rubra': ('estudo_peixe.py', 'fauna/peixes', 'peixe_couraca_rubra',
                      'Couraça-rubra: peixe nativo dos lagos (patch fauna, fase 9), placas ósseas na cabeça e nadadeiras vermelhas'),
}

for esp in IDS:
    estudo, categoria, nome, desc = SAIDAS[esp]
    ESTUDO = os.path.join(AQUI, estudo)
    sys.argv = [sys.argv[0], '--python', ESTUDO, '--', 'nada', 'jogo']
    sys.path.insert(0, AQUI)
    NS = {'__name__': '__main__', '__file__': ESTUDO}
    exec(compile(open(ESTUDO, encoding='utf-8').read(), ESTUDO, 'exec'), NS)
    sc = bpy.context.scene
    arm = NS['montar'](nome, esp)
    corpo = next(o for o in arm.children if o.type == 'MESH')
    corpo.name = nome + '_corpo'
    NS['pose_zero'](arm)
    bpy.context.view_layer.update()
    if 'ESPECIES' in NS and esp in NS['ESPECIES'] and 'grupo' in NS['ESPECIES'][esp]:
        P = NS['ESPECIES'][esp]
        acoes = NS['ACOES'][P['grupo']]
        ciclos = {k: P[k]['ciclo'] for k in ('andar', 'correr', 'espreitar') if k in P}
    else:
        acoes = NS['ACOES']
        ciclos = {}
    # ---------------------------------------------------------------- assa a cor numa textura (UV nova, "bake")
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 8
    me = corpo.data
    novo_uv = me.uv_layers.new(name='bake')
    me.uv_layers.active = novo_uv
    bpy.ops.object.select_all(action='DESELECT')
    corpo.select_set(True)
    bpy.context.view_layer.objects.active = corpo
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.008)
    bpy.ops.object.mode_set(mode='OBJECT')
    img = bpy.data.images.new(f'{nome}_cor', 256, 256)
    for m in me.materials:
        nt = m.node_tree
        p = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        p.inputs['Metallic'].default_value = 0.0
        tx = nt.nodes.new('ShaderNodeTexImage')
        tx.image = img
        nt.nodes.active = tx
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=3)
    img.pack()
    me.uv_layers.remove(me.uv_layers['UVMap'])
    for at in ('zona',):                       # atributos que só serviam ao estudo (cor por vértice, partes)
        if at in me.color_attributes:
            me.color_attributes.remove(me.color_attributes[at])
    mt = bpy.data.materials.new(f'{nome}_Tex')
    b = next(n for n in mt.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    tx = mt.node_tree.nodes.new('ShaderNodeTexImage')
    tx.image = img
    mt.node_tree.links.new(tx.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.8
    mt.use_backface_culling = False            # nadadeiras e orelhas finas aparecem dos dois lados
    me.materials.clear()
    me.materials.append(mt)

    # ---------------------------------------------------------------- ações (a pose de cada quadro vem do estudo)
    zmins = {}

    def acao(nome_a, quadros, posar):
        """Calcula todas as poses primeiro (sem ação ativa e com as trilhas já gravadas mudas: senão o Blender reavalia
        a animação e troca a pose do primeiro quadro pela da ação anterior) e só depois grava as chaves."""
        arm.animation_data_create()
        for tr in arm.animation_data.nla_tracks:
            tr.mute = True
        arm.animation_data.action = None
        quadros_pose, antes, zs = [], {}, []
        for q in range(quadros + 1):
            posar(arm, (q % quadros) / quadros)
            bpy.context.view_layer.update()
            pose = {}
            for pb in arm.pose.bones:
                qa = pb.rotation_quaternion.copy()
                if pb.name in antes and qa.dot(antes[pb.name]) < 0.0:      # mesmo hemisfério: interpola pelo caminho curto
                    qa = -qa
                antes[pb.name] = qa
                pose[pb.name] = (pb.location.copy(), qa, pb.scale.copy())
            quadros_pose.append(pose)
            ev = corpo.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mm = ev.to_mesh()
            zs.append(min((ev.matrix_world @ v.co).z for v in mm.vertices))
            ev.to_mesh_clear()
        zmins[nome_a] = (round(min(zs), 4), round(max(zs), 4))
        act = bpy.data.actions.new(nome_a)
        arm.animation_data.action = act
        for q, pose in enumerate(quadros_pose):
            for pb in arm.pose.bones:
                loc, qa, esc = pose[pb.name]
                pb.location, pb.rotation_quaternion, pb.scale = loc, qa, esc
                pb.keyframe_insert('location', frame=q + 1)
                pb.keyframe_insert('rotation_quaternion', frame=q + 1)
                pb.keyframe_insert('scale', frame=q + 1)
        act.use_fake_user = True
        arm.animation_data.action = None
        tr = arm.animation_data.nla_tracks.new()
        tr.name = nome_a
        tr.strips.new(nome_a, 1, act)
        tr.mute = True
    for nome_a, nq, posar in acoes:
        acao(nome_a, nq, posar)
    for tr in arm.animation_data.nla_tracks:
        tr.mute = False
    NS['pose_zero'](arm)
    if 'parte' in me.attributes:
        me.attributes.remove(me.attributes['parte'])
    sc.render.fps = 24
    saida = os.path.join(AQUI, '..', 'modelos', *categoria.split('/'), nome)
    os.makedirs(saida, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    corpo.select_set(True)
    glb = os.path.join(saida, f'{nome}.glb')
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_yup=True, export_animations=True,
                              export_animation_mode='NLA_TRACKS', export_skins=True, export_image_format='JPEG')
    bpy.context.view_layer.update()
    pts = [corpo.matrix_world @ v.co for v in corpo.data.vertices]
    dims = [round(max(p[i] for p in pts) - min(p[i] for p in pts), 3) for i in range(3)]
    tris = sum(len(p.vertices) - 2 for p in corpo.data.polygons)
    lista = ', '.join(f'{a} ({n})' for a, n, _ in acoes)
    passo = ('; metros por ciclo: ' + ', '.join(f'{k} {v:g}' for k, v in ciclos.items())) if ciclos else ''
    json.dump({'nome': nome, 'categoria': categoria, 'tipo': 'veiculo', 'area': [1, 1],
               'descricao': f'{desc}; ações: {lista}{passo}.',
               'ocupa_canto': False, 'partes': [{'nome': 'corpo', 'pai': None, 'pivo': [0.0, 0.0, 0.0]}], 'portas': [],
               'tris': tris, 'dims': dims, 'anima': True, 'estudo': estudo},
              open(os.path.join(saida, f'{nome}.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('FAUNA_EXPORTADA', esp, nome, tris, 'tris', dims, 'ciclos', ciclos, 'zmin por ação', zmins)
    bpy.ops.wm.read_factory_settings(use_empty=True)
