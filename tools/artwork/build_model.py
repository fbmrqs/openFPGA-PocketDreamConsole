"""Build an editable low-poly handheld and render a seven-tone pixel sprite."""
from pathlib import Path
import argparse
import sys
from math import cos, sin, pi, floor
import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[2] / 'build/artwork')
args = parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
OUT = args.output.resolve()
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

TONES = [0, 41, 88, 143, 185, 242, 255]
THICKNESS_SCALE = 1.30

def linear(v):
    v /= 255
    return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4

materials = []
for value in TONES:
    m = bpy.data.materials.new(f'Gray {value:03d}')
    c = linear(value)
    m.diffuse_color = (c, c, c, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (c, c, c, 1)
    bsdf.inputs['Roughness'].default_value = 1
    materials.append(m)

def mesh_object(name, vertices, faces, indices):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for material in materials:
        mesh.materials.append(material)
    for poly, index in zip(mesh.polygons, indices):
        poly.material_index = index
    return obj

def rounded_outline(width, height, radius, steps=6):
    points = []
    for x, y, start in [(width/2-radius, height/2-radius, 0),
                         (-width/2+radius, height/2-radius, pi/2),
                         (-width/2+radius, -height/2+radius, pi),
                         (width/2-radius, -height/2+radius, 3*pi/2)]:
        for i in range(steps+1):
            a = start + i*pi/(2*steps)
            points.append((x+radius*cos(a), y+radius*sin(a)))
    return points

def ring_solid(name, outline, rings, top=5, side=3, bottom=1, center=(0, 0)):
    n = len(outline)
    vertices = [(x*s+center[0], y*s+center[1], z)
                for z, s in rings for x, y in outline]
    faces = [tuple(reversed(range(n)))]
    colors = [bottom]
    for j in range(len(rings)-1):
        for i in range(n):
            faces.append((j*n+i, j*n+(i+1)%n, (j+1)*n+(i+1)%n, (j+1)*n+i))
            # Side faces use discrete directional tones, without smooth shading.
            x, y = outline[i]
            band = side if isinstance(side, int) else side[j]
            colors.append(max(1, band-1) if x < -2.5 else band)
    faces.append(tuple(range((len(rings)-1)*n, len(rings)*n)))
    colors.append(top)
    return mesh_object(name, vertices, faces, colors)

def rounded(name, width, height, radius, z0, z1, center=(0,0), top=5, side=3):
    return ring_solid(name, rounded_outline(width,height,radius),
                      [(z0, .97), (z1-.025, 1), (z1, .97)], top, side, center=center)

def disc(name, x, y, radius, z0, z1, top=2, side=1, count=16):
    outline = [(radius*cos(2*pi*i/count), radius*sin(2*pi*i/count)) for i in range(count)]
    return ring_solid(name, outline, [(z0,.94),(z1-.035,1),(z1,.87)],
                      top, side, center=(x,y))

# Separate shells and the seam remain editable pieces in the Blender file.
body_outline = rounded_outline(7.8, 3.4, 1.18, 7)
ring_solid('Lower shell', body_outline, [(.02,.88),(.13,.97),(.25,1)], 3, [1,3])
ring_solid('Dark shell seam', body_outline, [(.25,1),(.31,1)], 1, 1)
ring_solid('Upper shell', body_outline, [(.31,1),(.56,1),(.71,.965)], 5, [3,4])

# A shallow black bezel and a quiet, blank LCD match the reference sprites.
rounded('Screen bezel', 4.48, 2.65, .12, .705, .78, (-.05,.13), 0, 1)
rounded('Screen inset rim', 4.13, 2.32, .04, .78, .795, (-.05,.13), 2, 1)
rounded('Blank LCD', 3.96, 2.16, .025, .795, .802, (-.05,.13), 4, 3)

# Faceted left directional control with four low-relief arrows.
disc('Directional pad recess', -2.97,.15,.70,.69,.75, 0,1,24)
disc('Directional pad rim', -2.97,.15,.61,.75,.82, 3,1,16)
disc('Directional pad face', -2.97,.15,.53,.82,.87, 2,1,16)
disc('Directional pad center', -2.97,.15,.28,.87,.90, 2,2,12)
for i in range(4):
    a = i*pi/2
    cx, cy = -2.97+.38*cos(a), .15+.38*sin(a)
    pts = [(cx+.10*cos(a), cy+.10*sin(a), .886),
           (cx-.07*cos(a)-.085*sin(a),cy-.07*sin(a)+.085*cos(a),.886),
           (cx-.07*cos(a)+.085*sin(a),cy-.07*sin(a)-.085*cos(a),.886)]
    mesh_object(f'Directional arrow {i+1}', pts, [(0,1,2)], [3])

for label, x,y in [('a',2.71,-.20),('b',3.22,.39)]:
    disc(f'Button {label} recess',x,y,.38,.69,.76,0,1)
    disc(f'Button {label}',x,y,.29,.76,.89,2,1)

disc('Small function button recess',2.53,.88,.23,.69,.75,0,1)
disc('Small function button',2.53,.88,.16,.75,.81,3,1)
rounded('Left shoulder control',1.15,.20,.06,.47,.70,(-2.53,1.61),2,1)
rounded('Right shoulder control',1.15,.20,.06,.47,.70,(2.53,1.61),2,1)

for obj in bpy.context.scene.objects:
    if obj.type == 'MESH':
        for vertex in obj.data.vertices:
            vertex.co.z *= THICKNESS_SCALE

scene = bpy.context.scene
camera_data = bpy.data.cameras.new('Orthographic 2 to 1 pixel view')
camera = bpy.data.objects.new('Orthographic 2 to 1 pixel view', camera_data)
bpy.context.collection.objects.link(camera)
target = Vector((0,0,.35*THICKNESS_SCALE))
camera.location = target + Vector((-8,-8,6.531972647))
camera.rotation_euler = (target-camera.location).to_track_quat('-Z','Y').to_euler()
camera_data.type = 'ORTHO'
# Portable library images share a left edge and bottom baseline.
camera_data.ortho_scale = 30.4
camera_data.shift_x = 70.5 / 521
camera_data.shift_y = 21 / 521
scene.camera = camera
scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'FLAT'
scene.display.shading.color_type = 'MATERIAL'
scene.display.shading.show_shadows = False
scene.display.shading.show_cavity = False
scene.display.shading.show_specular_highlight = False
scene.display.shading.show_object_outline = False
scene.display.shading.background_type = 'WORLD'
scene.world.color = (1,1,1)
scene.display.render_aa = 'OFF'
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.view_settings.exposure = 0
scene.view_settings.gamma = 1
scene.render.resolution_x = 521
scene.render.resolution_y = 165
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGB'
scene.render.film_transparent = False
scene.render.dither_intensity = 0
scene.render.filepath = str(OUT/'pdc.png')

# These are actual coplanar mesh details, aligned to the final pixel grid.
# Their sizes are exact at the saved camera and native render resolution.
bpy.context.view_layer.update()
right = camera.matrix_world.to_quaternion() @ Vector((1,0,0))
up = camera.matrix_world.to_quaternion() @ Vector((0,1,0))
det = right.x*up.y-right.y*up.x
pixel_size = camera_data.ortho_scale / scene.render.resolution_x

def pixel_detail(name, location, tone, width=1, height=1, pixel_offset=(0,0)):
    width = max(1, round(width / 2))
    height = max(1, round(height / 2))
    pixel_offset = tuple(value / 2 for value in pixel_offset)
    p = Vector(location)
    uv = world_to_camera_view(scene, camera, p)
    sx = uv.x*scene.render.resolution_x
    sy = uv.y*scene.render.resolution_y
    cx = floor(sx)+width/2+pixel_offset[0]
    cy = floor(sy)+height/2+pixel_offset[1]
    vertices = []
    for dx, dy in [(-width/2+.01,-height/2+.01),(width/2-.01,-height/2+.01),
                   (width/2-.01,height/2-.01),(-width/2+.01,height/2-.01)]:
        a, b = (cx+dx-sx)*pixel_size, (cy+dy-sy)*pixel_size
        vertices.append((p.x+(up.y*a-right.y*b)/det,
                         p.y+(-up.x*a+right.x*b)/det,p.z))
    return mesh_object(name, vertices, [(0,1,2,3)], [tone])

for step in range(3):
    pixel_detail(f'Power indicator - isometric step {step+1}',
                 (-2.90,1.12,.718*THICKNESS_SCALE),
                 4, width=2, height=2, pixel_offset=(2*step-2,step-1))
for row in range(3):
    for col in range(5):
        pixel_detail(f'Speaker pixel row {row+1} column {col+1}',
                     (2.38,-.86,.718*THICKNESS_SCALE),
                     2 if col in (1,2) else 3, width=2, height=2,
                     pixel_offset=(4*col+4*row, 2*col-2*row))
scene['palette_srgb'] = '#000000 #292929 #585858 #8F8F8F #B9B9B9 #F2F2F2 #FFFFFF'
scene['camera_elevation_degrees'] = 30
scene['layout_reference'] = 'Portable bounds approximately x=131..249, bottom baseline y=137 on a 521x165 canvas.'
scene['render_notes'] = 'Flat material colors; no antialiasing; 2:1 diagonal pixel steps.'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'handheld.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'handheld.glb'), export_format='GLB',
                          export_cameras=True, export_materials='EXPORT')
bpy.ops.render.render(write_still=True)
print('DELIVERED', OUT)
