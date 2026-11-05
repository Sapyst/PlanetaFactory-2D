"""Prancha de quadros das ações de um modelo de fauna JÁ EXPORTADO (lê o .glb, como o jogo recebe): uma linha por
ação, uma coluna por quadro (ações de 24 quadros: um sim, um não), duas vistas (de lado, rente ao chão: contato; e de
3/4 por cima: pernas, cabeça, cauda), com a textura assada. Mede o menor z de cada quadro (nada abaixo do chão).
Uso: blender -b --python quadros_fauna.py -- <arquivo.glb> <saída sem extensão> [colunas=12] [largura=3200]"""
import bpy, bmesh, math, os, sys
from mathutils import Vector

a = sys.argv[sys.argv.index('--') + 1:]
GLB, SAIDA = a[0], a[1]
OPC = dict(x.split('=', 1) for x in a[2:] if '=' in x)
NCOL = int(OPC.get('colunas', 12))
LARG = int(OPC.get('largura', 3200))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 24
bpy.ops.import_scene.gltf(filepath=GLB)
arm0 = next(o for o in sc.objects if o.type == 'ARMATURE')
malha0 = next(o for o in sc.objects if o.type == 'MESH')
ad = arm0.animation_data
acoes = []
for tr in (ad.nla_tracks if ad else []):
    for st in tr.strips:
        if st.action:
            acoes.append(st.action)
if ad and ad.action and ad.action not in acoes:
    acoes.append(ad.action)
ORDEM = ['andar', 'correr', 'espreitar', 'pastar', 'alerta', 'morder', 'comer', 'deitado', 'nadar', 'pulo', 'morto']
acoes.sort(key=lambda ac: next((i for i, n in enumerate(ORDEM) if ac.name.startswith(n)), 99))
if ad:
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    ad.action = None


def curvas(act):
    try:
        return list(act.fcurves)
    except Exception:
        fc = []
        for lay in act.layers:
            for st in lay.strips:
                for cb in st.channelbags:
                    fc += list(cb.fcurves)
        return fc


def posar_estatico(arm, act, f):
    """Copia para o esqueleto a pose da ação no quadro f (avaliando as curvas: a cópia fica parada)."""
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    for fc in curvas(act):
        dp = fc.data_path
        if not dp.startswith('pose.bones["'):
            continue
        bn = dp.split('"')[1]
        prop = dp.rsplit('.', 1)[1]
        pb = arm.pose.bones.get(bn)
        if pb is None:
            continue
        v = getattr(pb, prop)
        v[fc.array_index] = fc.evaluate(f)
        setattr(pb, prop, v)


sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading
sh.light = 'STUDIO'
sh.color_type = 'TEXTURE'
sh.show_shadows = True
sh.show_cavity = True
sc.display.light_direction = (0.35, -0.45, 0.82)
sc.view_settings.view_transform = 'Standard'
cam_d = bpy.data.cameras.new('Cam')
cam = bpy.data.objects.new('Cam', cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
bpy.context.view_layer.update()
bb = [malha0.matrix_world @ Vector(c) for c in malha0.bound_box]
comp = max(p.x for p in bb) - min(p.x for p in bb) + 0.35 * max(0.3, max(p.z for p in bb))
alt = max(p.z for p in bb) + 0.15 * max(p.z for p in bb)
x_meio = (max(p.x for p in bb) + min(p.x for p in bb)) / 2
mt_chao = bpy.data.materials.new('Chao')
mt_chao.diffuse_color = (0.33, 0.33, 0.33, 1)
mt_rot = bpy.data.materials.new('Rot')
mt_rot.diffuse_color = (0.92, 0.92, 0.92, 1)
arm0.hide_render = True
malha0.hide_render = True
linhas = {'lado': [], '34': []}
log = []
for act in acoes:
    ini, fim = act.frame_range
    nq = int(round(fim - ini))
    passo = max(1, nq // NCOL)
    qs = list(range(0, nq, passo))[:NCOL] if nq > 2 else [0, 1]
    criados = []
    zpior = 1e9
    for ci, q in enumerate(qs):
        arm = arm0.copy()
        arm.data = arm0.data
        arm.animation_data_clear()
        sc.collection.objects.link(arm)
        me = malha0.copy()
        sc.collection.objects.link(me)
        me.parent = arm
        for md in me.modifiers:
            if md.type == 'ARMATURE':
                md.object = arm
        arm.location = (ci * comp - x_meio, 0.0, 0.0)
        arm.hide_render = False
        me.hide_render = False
        posar_estatico(arm, act, ini + q)
        criados += [arm, me]
        bpy.context.view_layer.update()
        ev = me.evaluated_get(bpy.context.evaluated_depsgraph_get())
        mm = ev.to_mesh()
        z = min((ev.matrix_world @ v.co).z for v in mm.vertices)
        ev.to_mesh_clear()
        zpior = min(zpior, z)
        if z < -0.0015:
            log.append(f'{act.name} q{q}: abaixo do chão {z:.4f}')
    bm = bmesh.new()
    res = bmesh.ops.create_cube(bm, size=1.0)
    for v in res['verts']:
        v.co = Vector((v.co.x * (NCOL * comp + 0.3), v.co.y * 1.8, v.co.z * 0.008 - 0.004))
    chao_me = bpy.data.meshes.new('chao')
    bm.to_mesh(chao_me)
    chao = bpy.data.objects.new('chao', chao_me)
    chao.data.materials.append(mt_chao)
    chao.location = ((NCOL - 1) * comp / 2, 0, 0)
    sc.collection.objects.link(chao)
    cu = bpy.data.curves.new('t', 'FONT')
    cu.body = f'{act.name} ({nq})   menor z = {zpior:+.4f} m'
    cu.size = 0.011 * NCOL * comp
    rot = bpy.data.objects.new('ROT', cu)
    rot.data.materials.append(mt_rot)
    sc.collection.objects.link(rot)
    criados += [chao, rot]
    cx = (NCOL - 1) * comp / 2
    W = NCOL * comp
    for v in ('lado', '34'):
        for o in criados:
            if o.type == 'ARMATURE':
                o.rotation_mode = 'XYZ'            # o importador de glTF deixa em quatérnio
                o.rotation_euler = (0, 0, 0.0 if v == 'lado' else -0.75)
        ele = math.radians(6 if v == 'lado' else 30)
        H_ = alt * 1.18 + 0.022 * NCOL * comp + (0.0 if v == 'lado' else 0.3 * alt)
        d = Vector((0, -math.cos(ele), math.sin(ele)))
        alvo = Vector((cx, 0.0, (alt * 1.18 + 0.022 * NCOL * comp) * 0.5 - 0.05 * alt))
        rot.location = (-comp * 0.45, -0.9 * comp, alt * 1.08 + (0.0 if v == 'lado' else 0.25 * alt))
        rot.rotation_euler = (math.pi / 2 - ele, 0, 0)
        cam.location = alvo + d * 60.0
        cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
        cam_d.type = 'ORTHO'
        cam_d.ortho_scale = W * 1.02
        sc.render.resolution_x = LARG
        sc.render.resolution_y = int(LARG * H_ / (W * 1.02))
        arq = f'{SAIDA}__{act.name}_{v}.png'
        sc.render.filepath = arq
        bpy.ops.render.render(write_still=True)
        linhas[v].append(arq)
    for o in criados:
        bpy.data.objects.remove(o, do_unlink=True)

import numpy as np
for v, arqs in linhas.items():
    imgs = [bpy.data.images.load(f) for f in arqs]
    w = imgs[0].size[0]
    H = sum(im.size[1] for im in imgs)
    big = np.zeros((H, w, 4), dtype=np.float32)
    big[:, :, :3] = 0.10
    big[:, :, 3] = 1.0
    y = H
    for im in imgs:
        h = im.size[1]
        px = np.empty(w * h * 4, dtype=np.float32)
        im.pixels.foreach_get(px)
        big[y - h:y] = px.reshape(h, w, 4)
        y -= h
    out = bpy.data.images.new('prancha', w, H, alpha=False)
    out.pixels.foreach_set(big.ravel())
    out.filepath_raw = SAIDA + ('' if v == 'lado' else '_34') + '.png'
    out.file_format = 'PNG'
    out.save()
    for f in arqs:
        os.remove(f)
print('QUADROS_GLB', os.path.basename(GLB), 'ações:', [ac.name for ac in acoes], 'problemas:', log or 'nenhum')
