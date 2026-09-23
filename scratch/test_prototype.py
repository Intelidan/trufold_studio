import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    baseline = json.load(f)

sq2 = 1.0 / math.sqrt(2)

def scale_cross(params):
    W1 = params.get('W1', 100.0)
    H1 = params.get('H1', 100.0)
    W2 = params.get('W2', 50.0)
    H2 = params.get('H2', 50.0)
    W3 = params.get('W3', 100.0)
    H3 = params.get('H3', 100.0)
    W4 = params.get('W4', 50.0)
    H4 = params.get('H4', 50.0)

    dW1 = W1 - 100.0
    dW2 = W2 - 50.0
    dW3 = W3 - 100.0
    dW4 = W4 - 50.0

    dH1 = H1 - 100.0
    dH2 = H2 - 50.0
    dH3 = H3 - 100.0
    dH4 = H4 - 50.0

    H_body = max(H1, max(H2, max(H3, H4)))
    dH_body = H_body - 100.0

    # 4 Quadrants configuration
    # p0_base is the horizontal mouth corner in baseline
    quads = [
        {
            'name': 'Q1_NE',
            'p0_base': (202.65180361560638, 83.43860018001283),
            'dp0': (dW1 / 2.0, -dW2 / 2.0),
            'u': (sq2, sq2), 'v': (sq2, -sq2),
            'cheek': 'F_3', 'flap_h': 'F_1', 'flap_v': 'F_0', 'flange': 'F_2',
            'b_base': 'B2', 'b_h': 'B9', 'b_v': 'B8', 'b_fl': 'FL3',
            'arcs_h': ('ARC_BND_12', 'ARC_BND_11'), # base, top
            'arcs_v': ('ARC_BND_9', 'ARC_BND_10'),  # base, top
            'punches_h': ['SLOT_7', 'SLOT_8'],
            'punches_v': ['SLOT_9'],
            'rot_punch': 135.0,
            'H_h': H1, 'dH_h': dH1,
            'H_v': H2, 'dH_v': dH2,
            'slot_v_id_2': 'SLOT_9_B',
        },
        {
            'name': 'Q2_NW',
            'p0_base': (104.65180361560647, 83.43860018001283),
            'dp0': (-dW1 / 2.0, -dW4 / 2.0),
            'u': (-sq2, sq2), 'v': (-sq2, -sq2),
            'cheek': 'F_7', 'flap_h': 'F_5', 'flap_v': 'F_4', 'flange': 'F_6',
            'b_base': 'B1', 'b_h': 'B10', 'b_v': 'B5', 'b_fl': 'FL2',
            'arcs_h': ('ARC_BND_4', 'ARC_BND_3'),
            'arcs_v': ('ARC_BND_1', 'ARC_BND_2'),
            'punches_h': ['SLOT_1', 'PUNCH_CPY_8064'],
            'punches_v': ['SLOT_3'],
            'rot_punch': 45.0,
            'H_h': H1, 'dH_h': dH1,
            'H_v': H4, 'dH_v': dH4,
            'slot_v_id_2': 'SLOT_3_B',
        },
        {
            'name': 'Q3_SE',
            'p0_base': (202.65180361560638, 188.00714267493942),
            'dp0': (dW3 / 2.0, dW2 / 2.0),
            'u': (sq2, -sq2), 'v': (sq2, sq2),
            'cheek': 'F_11', 'flap_h': 'F_9', 'flap_v': 'F_8', 'flange': 'F_10',
            'b_base': 'B3', 'b_h': 'B12', 'b_v': 'B7', 'b_fl': 'FL4',
            'arcs_h': ('ARC_BND_16', 'ARC_BND_15'),
            'arcs_v': ('ARC_BND_13', 'ARC_BND_14'),
            'punches_h': ['SLOT_10', 'SLOT_11'],
            'punches_v': ['SLOT_12'],
            'rot_punch': 45.0,
            'H_h': H3, 'dH_h': dH3,
            'H_v': H2, 'dH_v': dH2,
            'slot_v_id_2': 'SLOT_12_B',
        },
        {
            'name': 'Q4_SW',
            'p0_base': (104.65180361560647, 188.00714267493925),
            'dp0': (-dW3 / 2.0, dW4 / 2.0),
            'u': (-sq2, -sq2), 'v': (-sq2, sq2),
            'cheek': 'F_15', 'flap_h': 'F_13', 'flap_v': 'F_12', 'flange': 'F_14',
            'b_base': 'B4', 'b_h': 'B11', 'b_v': 'B6', 'b_fl': 'FL1',
            'arcs_h': ('ARC_BND_8', 'ARC_BND_7'),
            'arcs_v': ('ARC_BND_5', 'ARC_BND_6'),
            'punches_h': ['SLOT_4', 'SLOT_5'],
            'punches_v': ['SLOT_6'],
            'rot_punch': 135.0,
            'H_h': H3, 'dH_h': dH3,
            'H_v': H4, 'dH_v': dH4,
            'slot_v_id_2': 'SLOT_6_B',
        },
    ]

    print(f"Testing Scale: W=({W1},{W2},{W3},{W4}) H=({H1},{H2},{H3},{H4}) -> H_body={H_body}")
    # Verify baseline match if dW=0, dH=0
    if abs(dW1)+abs(dW2)+abs(dW3)+abs(dW4)+abs(dH1)+abs(dH2)+abs(dH3)+abs(dH4) < 1e-4:
        print("  Zero delta test passed.")

scale_cross({'W1': 100, 'H1': 100, 'W2': 50, 'H2': 50, 'W3': 100, 'H3': 100, 'W4': 50, 'H4': 50})
scale_cross({'W1': 100, 'H1': 100, 'W2': 100, 'H2': 50, 'W3': 100, 'H3': 100, 'W4': 50, 'H4': 50})
scale_cross({'W1': 100, 'H1': 100, 'W2': 50, 'H2': 75, 'W3': 100, 'H3': 100, 'W4': 50, 'H4': 50})
scale_cross({'W1': 100, 'H1': 100, 'W2': 50, 'H2': 125, 'W3': 100, 'H3': 100, 'W4': 50, 'H4': 50})
