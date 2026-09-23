import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

for a in dsf['arcs']:
    aid = a['id']
    ax, ay = a['center']['x'], a['center']['y']
    r = a['radius']
    s_deg = math.degrees(a['startAngleRad'])
    # Find closest face vertices
    closest_face = None
    min_dist = 999999
    for f in dsf['faces']:
        for v in f['vertices']:
            d = math.hypot(v['x'] - ax, v['y'] - ay)
            if d < min_dist:
                min_dist = d
                closest_face = f['id']
    print(f"{aid}: center=({ax:.2f}, {ay:.2f}) start={s_deg:.1f}° closest={closest_face} (dist={min_dist:.2f})")
