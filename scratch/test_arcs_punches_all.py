import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

sq2 = 1.0 / math.sqrt(2)

quads = [
    {
        'name': 'Q1_NE',
        'p0': (202.65180361560638, 83.43860018001283),
        'u': (sq2, sq2), 'v': (sq2, -sq2),
        'arcs': ['ARC_BND_9', 'ARC_BND_10', 'ARC_BND_11', 'ARC_BND_12'],
        'punches': ['SLOT_7', 'SLOT_8', 'SLOT_9'],
    },
    {
        'name': 'Q2_NW',
        'p0': (104.65180361560647, 83.43860018001283),
        'u': (-sq2, sq2), 'v': (-sq2, -sq2),
        'arcs': ['ARC_BND_1', 'ARC_BND_2', 'ARC_BND_3', 'ARC_BND_4'],
        'punches': ['SLOT_1', 'PUNCH_CPY_8064', 'SLOT_3'],
    },
    {
        'name': 'Q3_SE',
        'p0': (202.65180361560638, 188.00714267493942),
        'u': (sq2, -sq2), 'v': (sq2, sq2),
        'arcs': ['ARC_BND_13', 'ARC_BND_14', 'ARC_BND_15', 'ARC_BND_16'],
        'punches': ['SLOT_10', 'SLOT_11', 'SLOT_12'],
    },
    {
        'name': 'Q4_SW',
        'p0': (104.65180361560647, 188.00714267493925),
        'u': (-sq2, -sq2), 'v': (-sq2, sq2),
        'arcs': ['ARC_BND_5', 'ARC_BND_6', 'ARC_BND_7', 'ARC_BND_8'],
        'punches': ['SLOT_4', 'SLOT_5', 'SLOT_6'],
    },
]

def to_loc(p, p0, u, v):
    rx = p['x'] - p0[0]
    ry = p['y'] - p0[1]
    return (rx * u[0] + ry * u[1], rx * v[0] + ry * v[1])

for q in quads:
    p0 = q['p0']
    u = q['u']
    v = q['v']
    print(f"\n==================== {q['name']} ====================")
    for aid in q['arcs']:
        a = next(x for x in dsf['arcs'] if x['id'] == aid)
        lu, lv = to_loc(a['center'], p0, u, v)
        print(f"Arc   {aid:10s}: u={lu:5.1f}, v={lv:5.1f}, start={math.degrees(a['startAngleRad']):5.1f}°")
    for pid in q['punches']:
        p = next(x for x in dsf['punches'] if x['id'] == pid)
        lu, lv = to_loc(p['center'], p0, u, v)
        print(f"Punch {pid:15s}: u={lu:5.1f}, v={lv:5.1f}, rot={p.get('rotationDeg')}")
