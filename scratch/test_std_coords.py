import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

sq2 = 1.0 / math.sqrt(2)

quads = [
    {
        'name': 'Q1_NE',
        'p0': (202.65180361560638, 83.43860018001283),
        'u': (sq2, sq2),
        'v': (sq2, -sq2),
        'cheek': 'F_3', 'flap_h': 'F_1', 'flap_v': 'F_0', 'flange': 'F_2',
        'b_base': 'B2', 'b_h': 'B9', 'b_v': 'B8', 'b_fl': 'FL3',
    },
    {
        'name': 'Q2_NW',
        'p0': (104.65180361560647, 83.43860018001283),
        'u': (-sq2, sq2),
        'v': (-sq2, -sq2),
        'cheek': 'F_7', 'flap_h': 'F_5', 'flap_v': 'F_4', 'flange': 'F_6',
        'b_base': 'B1', 'b_h': 'B10', 'b_v': 'B5', 'b_fl': 'FL2',
    },
    {
        'name': 'Q3_SE',
        'p0': (202.65180361560638, 188.00714267493942),
        'u': (sq2, -sq2),
        'v': (sq2, sq2),
        'cheek': 'F_11', 'flap_h': 'F_9', 'flap_v': 'F_8', 'flange': 'F_10',
        'b_base': 'B3', 'b_h': 'B12', 'b_v': 'B7', 'b_fl': 'FL4',
    },
    {
        'name': 'Q4_SW',
        'p0': (104.65180361560647, 188.00714267493925),
        'u': (-sq2, -sq2),
        'v': (-sq2, sq2),
        'cheek': 'F_15', 'flap_h': 'F_13', 'flap_v': 'F_12', 'flange': 'F_14',
        'b_base': 'B4', 'b_h': 'B11', 'b_v': 'B6', 'b_fl': 'FL1',
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
    for fid in [q['cheek'], q['flap_h'], q['flap_v'], q['flange']]:
        face = next(f for f in dsf['faces'] if f['id'] == fid)
        locs = [to_loc(pt, p0, u, v) for pt in face['vertices']]
        loc_str = ", ".join([f"({lu:.1f},{lv:.1f})" for lu, lv in locs])
        print(f"Face {fid:4s}: {loc_str}")
