import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

f16 = dsf['faces'][16]
actual_verts = f16['vertices']

X0 = 153.65180361560642
Y0 = 135.7228714274761

# In baseline:
# W1 = 98.0 (nominal 100)
# W2 = 48.0 (nominal 50)
# W3 = 98.0 (nominal 100)
# W4 = 48.0 (nominal 50)
W1 = 98.0
W2 = 48.0
W3 = 98.0
W4 = 48.0

L_chamfer = 40.0
C = L_chamfer / math.sqrt(2) # 28.2842712474619

calc_verts = [
    # v0: P4 bottom
    {'x': X0 - W4/2 - C, 'y': Y0 + W4/2}, # wait, let's check X: is it W3/2 or W4/2?
    # v1: P4 top
    {'x': X0 - W1/2 - C, 'y': Y0 - W4/2},
    # v2: P1 left
    {'x': X0 - W1/2, 'y': Y0 - W4/2 - C},
    # v3: P1 right
    {'x': X0 + W1/2, 'y': Y0 - W2/2 - C},
    # v4: P2 top
    {'x': X0 + W1/2 + C, 'y': Y0 - W2/2},
    # v5: P2 bottom
    {'x': X0 + W3/2 + C, 'y': Y0 + W2/2},
    # v6: P3 right
    {'x': X0 + W3/2, 'y': Y0 + W2/2 + C},
    # v7: P3 left
    {'x': X0 - W3/2, 'y': Y0 + W4/2 + C},
]
# For v0: West arm bottom is connected to corner 4 (between South arm left W3/2 and West arm bottom W4/2):
calc_verts[0] = {'x': X0 - W3/2 - C, 'y': Y0 + W4/2}

print("Comparing Calculated vs Actual F16 Vertices:")
for i in range(8):
    av = actual_verts[i]
    cv = calc_verts[i]
    dx = cv['x'] - av['x']
    dy = cv['y'] - av['y']
    print(f"v{i}: actual=({av['x']:.4f}, {av['y']:.4f}) calc=({cv['x']:.4f}, {cv['y']:.4f}) diff=({dx:.1e}, {dy:.1e})")
