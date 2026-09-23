import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

# Helper to check point in polygon
def point_in_poly(x, y, poly):
    n = len(poly)
    inside = False
    p1x, p1y = poly[0]['x'], poly[0]['y']
    for i in range(n + 1):
        p2x, p2y = poly[i % n]['x'], poly[i % n]['y']
        if y > min(p1y, p2y):
            if y <= max(p1y, p2y):
                if x <= max(p1x, p2x):
                    if p1y != p2y:
                        xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
                    if p1x == p2x or x <= xinters:
                        inside = not inside
        p1x, p1y = p2x, p2y
    return inside

# Assign each punch to face
print("--- Punch -> Face Mapping ---")
for p in dsf['punches']:
    px, py = p['center']['x'], p['center']['y']
    found = None
    for f in dsf['faces']:
        if point_in_poly(px, py, f['vertices']):
            found = f['id']
            break
    print(f"{p['id']}: center=({px:.2f}, {py:.2f}) -> Face {found}")

# Assign each arc to face (check center or endpoints)
print("\n--- Arc Details & Nearest Bends/Faces ---")
for a in dsf['arcs']:
    ax, ay = a['center']['x'], a['center']['y']
    r = a['radius']
    # start and end points of arc
    s_ang = a['startAngleRad']
    e_ang = s_ang + a['sweepAngleRad']
    sp_x = ax + r * math.cos(s_ang)
    sp_y = ax + r * math.sin(s_ang)
    print(f"{a['id']}: center=({ax:.2f}, {ay:.2f}), start={math.degrees(s_ang):.1f}°, sweep={math.degrees(a['sweepAngleRad']):.1f}°")

print("\n--- Quadrant Grouping ---")
# Q1: North-East (P1 Top, P2 Right)
# Q2: North-West (P1 Top, P4 Left)
# Q3: South-East (P3 Bottom, P2 Right)
# Q4: South-West (P3 Bottom, P4 Left)
quads = {
    'Q1 (NE)': {'faces': ['F_3', 'F_1', 'F_0', 'F_2'], 'bends': ['B2', 'B8', 'B9', 'FL3']},
    'Q2 (NW)': {'faces': ['F_7', 'F_5', 'F_4', 'F_6'], 'bends': ['B1', 'B5', 'B10', 'FL2']},
    'Q3 (SE)': {'faces': ['F_11', 'F_9', 'F_8', 'F_10'], 'bends': ['B3', 'B7', 'B12', 'FL4']},
    'Q4 (SW)': {'faces': ['F_15', 'F_13', 'F_12', 'F_14'], 'bends': ['B4', 'B6', 'B11', 'FL1']},
}

for qname, qdata in quads.items():
    print(f"\n=== {qname} ===")
    print("Faces:", qdata['faces'])
    print("Bends:", qdata['bends'])
