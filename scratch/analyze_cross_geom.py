import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

print("DSF Parameters:", dsf.get('parameters', {}))

# Let's inspect baseFloor F_16
f16 = dsf['faces'][16]
print("\n--- F16 Vertices ---")
for i, v in enumerate(f16['vertices']):
    print(f"v{i}: ({v['x']:.4f}, {v['y']:.4f})")

# Let's map bends
print("\n--- Bends ---")
for b in dsf.get('bends', []):
    p1 = b['p1']
    p2 = b['p2']
    dx = p2['x'] - p1['x']
    dy = p2['y'] - p1['y']
    length = math.hypot(dx, dy)
    angle_deg = math.degrees(math.atan2(dy, dx))
    print(f"{b['id']}: ({p1['x']:.2f}, {p1['y']:.2f}) -> ({p2['x']:.2f}, {p2['y']:.2f}) len={length:.2f} angle={angle_deg:.1f}°")

# Let's map each face to its vertices and see where it lies
print("\n--- Faces Details ---")
for f in dsf.get('faces', []):
    fid = f['id']
    pts = f['vertices']
    xs = [p['x'] for p in pts]
    ys = [p['y'] for p in pts]
    cx = sum(xs)/len(xs)
    cy = sum(ys)/len(ys)
    print(f"{fid}: {len(pts)} verts, center=({cx:.2f}, {cy:.2f}) x=[{min(xs):.2f}, {max(xs):.2f}] y=[{min(ys):.2f}, {max(ys):.2f}]")

# Let's map punches
print("\n--- Punches Details ---")
for p in dsf.get('punches', []):
    pid = p['id']
    c = p['center']
    print(f"{pid}: center=({c['x']:.2f}, {c['y']:.2f}) rot={p.get('rotationDeg')} w={p.get('widthMm')} l={p.get('lengthMm')} role={p.get('role')} parentFace={p.get('parentFaceId')}")

# Let's map arcs
print("\n--- Arcs Details ---")
for a in dsf.get('arcs', []):
    aid = a['id']
    c = a['center']
    start_deg = math.degrees(a['startAngleRad'])
    sweep_deg = math.degrees(a['sweepAngleRad'])
    print(f"{aid}: center=({c['x']:.2f}, {c['y']:.2f}) r={a['radius']} start={start_deg:.1f}° sweep={sweep_deg:.1f}°")
