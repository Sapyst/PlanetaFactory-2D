"""Ratos para o jogo (glb com esqueleto), um por espécie: monta o estudo (estudo_rato.py) na qualidade do jogo, fica
só o rato da espécie, assa a cor dos materiais (procedurais) numa textura, troca por material simples e exporta com o
esqueleto e as ações (24 quadros/s):
  "andar"   — 12 quadros: um passo (o jogo acompanha a distância andada);
  "correr"  — 12 quadros: galope (rato-pardo) ou pulo (saltador);
  "farejar" — 24 quadros: parado, focinho para cima, cabeça farejando;
  "comer"   — 24 quadros: sentado com as mãos no fruto, roendo;
  "cavar"   — 12 quadros: as mãos raspando o chão (enterrar a semente);
  "morto"   — 2 quadros: deitado de lado (a carcaça).
Uso: blender -b --python exportar_rato.py -- <especie> [<especie>…]   (pardo, saltador)"""
import bpy, math, os, sys, json

AQUI = os.path.dirname(os.path.abspath(__file__))
ESTUDO = os.path.join(AQUI, 'estudo_rato.py')
ESPECIES = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else ['pardo']
NOMES = {'pardo': 'Rato-pardo', 'saltador': 'Saltador'}

for esp in ESPECIES:
    sys.argv = [sys.argv[0], '--python', ESTUDO, '--', 'nada', 'jogo']
    sys.path.insert(0, AQUI)
    NS = {'__name__': '__main__', '__file__': ESTUDO}
    exec(compile(open(ESTUDO, encoding='utf-8').read(), ESTUDO, 'exec'), NS)
    sc = bpy.context.scene
    arm = sc.objects[esp + '_andar']
    for o in list(sc.objects):
        if not (o is arm or o.parent is arm):
            bpy.data.objects.remove(o, do_unlink=True)
    arm.animation_data_clear()
    arm.location = (0, 0, 0)
    arm.rotation_euler = (0, 0, 0)
    NS['pose_zero'](arm)
    bpy.context.view_layer.update()
    corpo = next(o for o in arm.children if o.type == 'MESH')
    # ---------------------------------------------------------------- assa a cor numa textura
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
    img = bpy.data.images.new(f'rato_{esp}_cor', 256, 256)
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
    mt = bpy.data.materials.new(f'rato_{esp}_Tex')
    b = mt.node_tree.nodes['Principled BSDF']
    tx = mt.node_tree.nodes.new('ShaderNodeTexImage')
    tx.image = img
    mt.node_tree.links.new(tx.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.8
    me.materials.clear()
    me.materials.append(mt)

    # ---------------------------------------------------------------- ações
    def acao(nome, quadros, posar):
        """Calcula todas as poses primeiro (sem ação ativa e com as trilhas já gravadas mudas) e só depois grava as
        chaves: trocar a ação ativa faz o Blender reavaliar a animação na próxima atualização da cena, e as poses que
        medem a malha (comer, morto: assentar) trocavam o 1º quadro pela pose da trilha anterior."""
        arm.animation_data_create()
        for tr in arm.animation_data.nla_tracks:
            tr.mute = True
        arm.animation_data.action = None
        poses = []
        for q in range(quadros + 1):
            posar(q / quadros)
            poses.append({pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy())
                          for pb in arm.pose.bones})
        act = bpy.data.actions.new(nome)
        arm.animation_data.action = act
        for q, pose in enumerate(poses):
            for pb in arm.pose.bones:
                pb.location, pb.rotation_quaternion, pb.scale = pose[pb.name]
                pb.keyframe_insert('location', frame=q + 1)
                pb.keyframe_insert('rotation_quaternion', frame=q + 1)
                pb.keyframe_insert('scale', frame=q + 1)
        act.use_fake_user = True
        tr = arm.animation_data.nla_tracks.new()
        tr.name = nome
        tr.strips.new(nome, 1, act)
        tr.mute = True
        arm.animation_data.action = None
    acao('andar', 12, lambda u: NS['pose_andar'](arm, u))
    acao('correr', 12, lambda u: NS['pose_correr'](arm, u))
    acao('farejar', 24, lambda u: NS['pose_farejar'](arm, u))
    acao('comer', 24, lambda u: NS['pose_comer'](arm, u))
    acao('cavar', 12, lambda u: NS['pose_cavar'](arm, u))
    acao('morto', 2, lambda u: NS['pose_morto'](arm))
    for tr in arm.animation_data.nla_tracks:      # todas de volta para o exportador
        tr.mute = False
    NS['pose_zero'](arm)
    sc.render.fps = 24
    saida = os.path.join(AQUI, '..', 'modelos', 'fauna', 'ratos', f'rato_{esp}')
    os.makedirs(saida, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    corpo.select_set(True)
    glb = os.path.join(saida, f'rato_{esp}.glb')
    bpy.ops.export_scene.gltf(filepath=glb, use_selection=True, export_yup=True, export_animations=True,
                              export_animation_mode='NLA_TRACKS', export_skins=True, export_image_format='JPEG')
    pts = [corpo.matrix_world @ v.co for v in corpo.data.vertices]
    dims = [round(max(p[i] for p in pts) - min(p[i] for p in pts), 3) for i in range(3)]
    tris = sum(len(p.vertices) - 2 for p in corpo.data.polygons)
    json.dump({'nome': f'rato_{esp}', 'categoria': 'fauna/ratos', 'tipo': 'veiculo', 'area': [1, 1],
               'descricao': f'{NOMES.get(esp, esp)}: roedor nativo (patch fauna, fase 5); andar, correr, farejar, comer, cavar e morto.',
               'ocupa_canto': False, 'partes': [{'nome': 'corpo', 'pai': None, 'pivo': [0.0, 0.0, 0.0]}], 'portas': [],
               'tris': tris, 'dims': dims, 'anima': True, 'estudo': 'estudo_rato.py'},
              open(os.path.join(saida, f'rato_{esp}.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('RATO_EXPORTADO', esp, tris, 'tris', dims)
    bpy.ops.wm.read_factory_settings(use_empty=True)
