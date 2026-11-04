"""Pássaros para o jogo (glb com esqueleto), um por espécie: monta o estudo (estudo_passaro.py) na qualidade do jogo,
fica só o pássaro da espécie, assa a cor dos materiais (procedurais) numa textura, troca por material simples e
exporta com o esqueleto e as ações (24 quadros/s):
  "voo"     — 12 quadros: uma batida de asa (o jogo toca em laço; o planador mais devagar);
  "planar"  — 24 quadros: asas abertas, balanço leve;
  "parado"  — 48 quadros: pousado, olhando em volta;
  "bicando" — 24 quadros: duas bicadas no chão (comer e pegar semente);
  "pousar"  — 24 quadros: chega freando e fecha as asas (ao contrário = decolar).
Uso: blender -b --python exportar_passaro.py -- <especie> [<especie>…]"""
import bpy, math, os, sys, json

AQUI = os.path.dirname(os.path.abspath(__file__))
ESTUDO = os.path.join(AQUI, 'estudo_passaro.py')
ESPECIES = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else ['pardelo']
NOMES = {'pardelo': 'Pardelo', 'cobrico': 'Cobrico', 'azulao': 'Azulão', 'rubro': 'Rubro', 'planador': 'Planador-cinza'}

for esp in ESPECIES:
    sys.argv = [sys.argv[0], '--python', ESTUDO, '--', 'nada', 'jogo']
    sys.path.insert(0, AQUI)
    NS = {'__name__': '__main__', '__file__': ESTUDO}
    exec(compile(open(ESTUDO, encoding='utf-8').read(), ESTUDO, 'exec'), NS)
    sc = bpy.context.scene
    arm = sc.objects[esp + '_voo']
    for o in list(sc.objects):
        if not (o is arm or o.parent is arm):
            bpy.data.objects.remove(o, do_unlink=True)
    arm.animation_data_clear()
    arm.location = (0, 0, 0)
    arm.rotation_euler = (0, 0, 0)
    NS['pose_zero'](arm)
    bpy.context.view_layer.update()
    corpo = next(o for o in arm.children if o.type == 'MESH')
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
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.006)
    bpy.ops.object.mode_set(mode='OBJECT')
    img = bpy.data.images.new(f'passaro_{esp}_cor', 512, 512)
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
    mt = bpy.data.materials.new(f'passaro_{esp}_Tex')
    b = mt.node_tree.nodes['Principled BSDF']
    tx = mt.node_tree.nodes.new('ShaderNodeTexImage')
    tx.image = img
    mt.node_tree.links.new(tx.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.75
    me.materials.clear()
    me.materials.append(mt)

    # ---------------------------------------------------------------- ações
    def acao(nome, quadros, posar):
        arm.animation_data_create()
        act = bpy.data.actions.new(nome)
        arm.animation_data.action = act
        for q in range(quadros + 1):
            posar(q / quadros)
            for pb in arm.pose.bones:
                pb.keyframe_insert('location', frame=q + 1)
                pb.keyframe_insert('rotation_euler', frame=q + 1)
                pb.keyframe_insert('scale', frame=q + 1)
        act.use_fake_user = True
        tr = arm.animation_data.nla_tracks.new()
        tr.name = nome
        tr.strips.new(nome, 1, act)
        arm.animation_data.action = None
    acao('voo', 12, lambda u: NS['pose_voo'](arm, u))
    acao('planar', 24, lambda u: NS['pose_planar'](arm, u))
    acao('parado', 48, lambda u: NS['pose_parado'](arm, u))
    acao('bicando', 24, lambda u: NS['pose_bicar'](arm, u))
    acao('pousar', 24, lambda u: NS['pose_pousar'](arm, u))     # tocada ao contrário = decolar
    NS['pose_zero'](arm)
    sc.render.fps = 24
    saida = os.path.join(AQUI, '..', 'modelos', 'fauna', 'passaros', f'passaro_{esp}')
    os.makedirs(saida, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    corpo.select_set(True)
    glb = os.path.join(saida, f'passaro_{esp}.glb')
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_yup=True, export_animations=True,
                              export_animation_mode='NLA_TRACKS', export_skins=True, export_image_format='JPEG')
    pts = [corpo.matrix_world @ v.co for v in corpo.data.vertices]
    dims = [round(max(p[i] for p in pts) - min(p[i] for p in pts), 3) for i in range(3)]
    tris = sum(len(p.vertices) - 2 for p in corpo.data.polygons)
    json.dump({'nome': f'passaro_{esp}', 'categoria': 'fauna/passaros', 'tipo': 'veiculo', 'area': [1, 1],
               'descricao': f'{NOMES.get(esp, esp)}: pássaro nativo (patch fauna); voo, planar, parado e bicando.',
               'ocupa_canto': False, 'partes': [{'nome': 'corpo', 'pai': None, 'pivo': [0.0, 0.0, 0.0]}], 'portas': [],
               'tris': tris, 'dims': dims, 'anima': True, 'estudo': 'estudo_passaro.py'},
              open(os.path.join(saida, f'passaro_{esp}.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('PASSARO_EXPORTADO', esp, tris, 'tris', dims)
    bpy.ops.wm.read_factory_settings(use_empty=True)
