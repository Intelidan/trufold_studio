import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

# Let's inspect the exact local coordinates of ALL features in Quadrant 1 (NE)
# Cheek F_3, Flap F_1 (P1), Flap F_0 (P2), Flange F_2 (FL3)
# Base bend B2 p0 = (202.6518, 83.4386), p1 = (230.9361, 111.7229)
# u_axis = (1/sqrt2, 1/sqrt2) = (0.70710678, 0.70710678)
# v_axis = (1/sqrt2, -1/sqrt2) = (0.70710678, -0.70710678)
# In local frame (u, v):
# p0 is at (0, 0), p1 is at (40, 0)

ux = 1.0 / math.sqrt(2)
uy = 1.0 / math.sqrt(2)
vx = 1.0 / math.sqrt(2)
vy = -1.0 / math.sqrt(2)
p0 = (202.65180361560638, 83.43860018001283)

def to_local(gx, gy):
    rx = gx - p0[0]
    ry = gy - p0[1]
    return (rx * ux + ry * uy, rx * vx + ry * vy)

def to_global(u, v):
    return (p0[0] + u * ux + v * vx, p0[1] + u * uy + v * vy)

print("--- Arcs in Q1 ---")
for aid in ['ARC_BND_9', 'ARC_BND_10', 'ARC_BND_11', 'ARC_BND_12']:
    a = next(x for x in dsf['arcs'] if x['id'] == aid)
    c = a['center']
    u, v = to_local(c['x'], c['y'])
    print(f"{aid}: center=({c['x']:.2f}, {c['y']:.2f}) -> local=(u={u:.2f}, v={v:.2f}), start={math.degrees(a['startAngleRad']):.1f}°")

print("\n--- Punches in Q1 ---")
for pid in ['SLOT_7', 'SLOT_8', 'SLOT_9']:
    p = next(x for x in dsf['punches'] if x['id'] == pid)
    c = p['center']
    u, v = to_local(c['x'], c['y'])
    print(f"{pid}: center=({c['x']:.2f}, {c['y']:.2f}) -> local=(u={u:.2f}, v={v:.2f}), rot={p.get('rotationDeg')}")
