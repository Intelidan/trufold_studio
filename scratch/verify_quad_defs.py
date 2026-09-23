import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    baseline = json.load(f)

# Define Quadrant Transform Definition
quadrants = [
    {
        'name': 'Q1_NE',
        'cheek_id': 'F_3',
        'flap_h_id': 'F_1',
        'flap_v_id': 'F_0',
        'flange_id': 'F_2',
        'bend_base_id': 'B2',
        'bend_h_id': 'B9',
        'bend_v_id': 'B8',
        'bend_fl_id': 'FL3',
        'arcs_h': ['ARC_BND_12', 'ARC_BND_11'], # base arc, top arc
        'arcs_v': ['ARC_BND_9', 'ARC_BND_10'],
        'punches_h': ['SLOT_7', 'SLOT_8'],
        'punches_v': ['SLOT_9'],
        'port_h_idx': 0, # Port 1
        'port_v_idx': 1, # Port 2
        'p0_base': (202.65180361560638, 83.43860018001283),
        'u_vec': (1.0 / math.sqrt(2), 1.0 / math.sqrt(2)),
        'v_vec': (1.0 / math.sqrt(2), -1.0 / math.sqrt(2)),
        'dW_u': lambda dW1, dW2, dW3, dW4: (dW1 / 2.0, -dW2 / 2.0),
    },
    {
        'name': 'Q2_NW',
        'cheek_id': 'F_7',
        'flap_h_id': 'F_5',
        'flap_v_id': 'F_4',
        'flange_id': 'F_6',
        'bend_base_id': 'B1',
        'bend_h_id': 'B10',
        'bend_v_id': 'B5',
        'bend_fl_id': 'FL2',
        'arcs_h': ['ARC_BND_4', 'ARC_BND_3'],
        'arcs_v': ['ARC_BND_1', 'ARC_BND_2'],
        'punches_h': ['SLOT_1', 'PUNCH_CPY_8064'],
        'punches_v': ['SLOT_3'],
        'port_h_idx': 0, # Port 1
        'port_v_idx': 3, # Port 4
        'p0_base': (104.65180361560647, 83.43860018001283),
        'u_vec': (-1.0 / math.sqrt(2), 1.0 / math.sqrt(2)),
        'v_vec': (-1.0 / math.sqrt(2), -1.0 / math.sqrt(2)),
        'dW_u': lambda dW1, dW2, dW3, dW4: (-dW1 / 2.0, -dW4 / 2.0),
    },
    {
        'name': 'Q3_SE',
        'cheek_id': 'F_11',
        'flap_h_id': 'F_9',
        'flap_v_id': 'F_8',
        'flange_id': 'F_10',
        'bend_base_id': 'B3',
        'bend_h_id': 'B12',
        'bend_v_id': 'B7',
        'bend_fl_id': 'FL4',
        'arcs_h': ['ARC_BND_16', 'ARC_BND_15'],
        'arcs_v': ['ARC_BND_13', 'ARC_BND_14'],
        'punches_h': ['SLOT_10', 'SLOT_11'],
        'punches_v': ['SLOT_12'],
        'port_h_idx': 2, # Port 3
        'port_v_idx': 1, # Port 2
        'p0_base': (202.65180361560638, 188.00714267493942),
        'u_vec': (1.0 / math.sqrt(2), -1.0 / math.sqrt(2)),
        'v_vec': (1.0 / math.sqrt(2), 1.0 / math.sqrt(2)),
        'dW_u': lambda dW1, dW2, dW3, dW4: (dW3 / 2.0, dW2 / 2.0),
    },
    {
        'name': 'Q4_SW',
        'cheek_id': 'F_15',
        'flap_h_id': 'F_13',
        'flap_v_id': 'F_12',
        'flange_id': 'F_14',
        'bend_base_id': 'B4',
        'bend_h_id': 'B11',
        'bend_v_id': 'B6',
        'bend_fl_id': 'FL1',
        'arcs_h': ['ARC_BND_8', 'ARC_BND_7'],
        'arcs_v': ['ARC_BND_5', 'ARC_BND_6'],
        'punches_h': ['SLOT_4', 'SLOT_5'],
        'punches_v': ['SLOT_6'],
        'port_h_idx': 2, # Port 3
        'port_v_idx': 3, # Port 4
        'p0_base': (104.65180361560647, 188.00714267493925),
        'u_vec': (-1.0 / math.sqrt(2), -1.0 / math.sqrt(2)),
        'v_vec': (-1.0 / math.sqrt(2), 1.0 / math.sqrt(2)),
        'dW_u': lambda dW1, dW2, dW3, dW4: (-dW3 / 2.0, dW4 / 2.0),
    },
]

print("Quadrant definitions ready.")
# Let's verify p0_base matches base bends p1 in baseline
for q in quadrants:
    bid = q['bend_base_id']
    b = next(x for x in baseline['bends'] if x['id'] == bid)
    p0 = q['p0_base']
    dist = math.hypot(b['p1']['x'] - p0[0], b['p1']['y'] - p0[1])
    print(f"{q['name']} {bid}: dist={dist:.4e}")
