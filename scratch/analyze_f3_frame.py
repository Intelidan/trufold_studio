import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

# Inspect Cheek F_3 (NE)
# B2 is the base bend: (202.6518, 83.4386) -> (230.9361, 111.7229)
# Let's see the local coordinate frame:
# Base bend B2 vector: (28.2843, 28.2843), length 40.0, unit_u = (1/sqrt2, 1/sqrt2)
# Outward normal unit_v = (1/sqrt2, -1/sqrt2) or (-1/sqrt2, 1/sqrt2)?
# Let's check where F_3 vertices lie relative to B2

f3 = next(f for f in dsf['faces'] if f['id'] == 'F_3')
p0_b2 = {'x': 202.6518, 'y': 83.4386} # B2 start (near P1)
p1_b2 = {'x': 230.9361, 'y': 111.7229} # B2 end (near P2)

# Vector along B2:
ux = (p1_b2['x'] - p0_b2['x']) / 40.0 # 1/sqrt2 = 0.7071
uy = (p1_b2['y'] - p0_b2['y']) / 40.0 # 1/sqrt2 = 0.7071

# Normal away from baseFloor F16 (outward into F3):
# F16 is to the left/bottom of B2, so F3 is to the right/top:
# Outward normal has positive X, negative Y? Let's check F3 center (254.13, 65.90)
# p0_b2 is (202.65, 83.44). Vector to center is (+51.48, -17.54).
# So vx > 0, vy < 0. vx = 1/sqrt2, vy = -1/sqrt2!
# Let's verify dot product: ux*vx + uy*vy = (1/sqrt2)*(1/sqrt2) + (1/sqrt2)*(-1/sqrt2) = 0.5 - 0.5 = 0! Perfect!

vx = uy
vy = -ux

print("=== Cheek F_3 (Quadrant 1 - NE) ===")
print(f"u_axis (along B2 from P1 to P2): ({ux:.4f}, {uy:.4f})")
print(f"v_axis (outward normal): ({vx:.4f}, {vy:.4f})")

for vi, v in enumerate(f3['vertices']):
    rx = v['x'] - p0_b2['x']
    ry = v['y'] - p0_b2['y']
    u = rx * ux + ry * uy
    v_coord = rx * vx + ry * vy
    print(f"  v{vi}: global=({v['x']:.2f}, {v['y']:.2f}) -> local=(u={u:.2f}, v={v_coord:.2f})")

# Let's also check F_1 (Flap to P1), F_0 (Flap to P2), F_2 (Return Flange) in this frame!
print("\n--- F_1 (Port 1 flap) in F_3 frame ---")
f1 = next(f for f in dsf['faces'] if f['id'] == 'F_1')
for vi, v in enumerate(f1['vertices']):
    rx = v['x'] - p0_b2['x']
    ry = v['y'] - p0_b2['y']
    u = rx * ux + ry * uy
    v_coord = rx * vx + ry * vy
    print(f"  v{vi}: global=({v['x']:.2f}, {v['y']:.2f}) -> local=(u={u:.2f}, v={v_coord:.2f})")

print("\n--- F_0 (Port 2 flap) in F_3 frame ---")
f0 = next(f for f in dsf['faces'] if f['id'] == 'F_0')
for vi, v in enumerate(f0['vertices']):
    rx = v['x'] - p0_b2['x']
    ry = v['y'] - p0_b2['y']
    u = rx * ux + ry * uy
    v_coord = rx * vx + ry * vy
    print(f"  v{vi}: global=({v['x']:.2f}, {v['y']:.2f}) -> local=(u={u:.2f}, v={v_coord:.2f})")

print("\n--- F_2 (Return flange FL3) in F_3 frame ---")
f2 = next(f for f in dsf['faces'] if f['id'] == 'F_2')
for vi, v in enumerate(f2['vertices']):
    rx = v['x'] - p0_b2['x']
    ry = v['y'] - p0_b2['y']
    u = rx * ux + ry * uy
    v_coord = rx * vx + ry * vy
    print(f"  v{vi}: global=({v['x']:.2f}, {v['y']:.2f}) -> local=(u={u:.2f}, v={v_coord:.2f})")
