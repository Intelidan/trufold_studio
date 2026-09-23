import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

# The 4 Cheeks and their Base Bends:
# Q1 (NE): Cheek F_3, Bend B2: from (202.6518, 83.4386) [near P1] to (230.9361, 111.7229) [near P2]
# Q2 (NW): Cheek F_7, Bend B1: from (104.6518, 83.4386) [near P1] to (76.3675, 111.7229) [near P4]
# Q3 (SE): Cheek F_11, Bend B3: from (202.6518, 188.0071) [near P3] to (230.9361, 159.7229) [near P2]
# Q4 (SW): Cheek F_15, Bend B4: from (104.6518, 188.0071) [near P3] to (76.3675, 159.7229) [near P4]

quadrant_specs = [
    {
        'quad': 'Q1 (NE)',
        'cheek_id': 'F_3',
        'p_horiz_id': 'PORT_1', # along horiz side (u=0)
        'p_vert_id': 'PORT_2',  # along vert side (u=40)
        'flap_horiz_id': 'F_1',
        'flap_vert_id': 'F_0',
        'flange_id': 'F_2',
        'bend_base': 'B2',
        'bend_horiz': 'B9',
        'bend_vert': 'B8',
        'bend_flange': 'FL3',
        'p_base_0': (202.6518, 83.4386), # P1 corner
        'p_base_1': (230.9361, 111.7229), # P2 corner
        'u_sign': (1, 1),
        'v_sign': (1, -1),
    },
    {
        'quad': 'Q2 (NW)',
        'cheek_id': 'F_7',
        'p_horiz_id': 'PORT_1', # along horiz side (u=0)
        'p_vert_id': 'PORT_4',  # along vert side (u=40)
        'flap_horiz_id': 'F_5',
        'flap_vert_id': 'F_4',
        'flange_id': 'F_6',
        'bend_base': 'B1',
        'bend_horiz': 'B10',
        'bend_vert': 'B5',
        'bend_flange': 'FL2',
        'p_base_0': (104.6518, 83.4386), # P1 corner
        'p_base_1': (76.3675, 111.7229),  # P4 corner
        'u_sign': (-1, 1),
        'v_sign': (-1, -1),
    },
    {
        'quad': 'Q3 (SE)',
        'cheek_id': 'F_11',
        'p_horiz_id': 'PORT_3', # along horiz side (u=0)
        'p_vert_id': 'PORT_2',  # along vert side (u=40)
        'flap_horiz_id': 'F_9',
        'flap_vert_id': 'F_8',
        'flange_id': 'F_10',
        'bend_base': 'B3',
        'bend_horiz': 'B12',
        'bend_vert': 'B7',
        'bend_flange': 'FL4',
        'p_base_0': (202.6518, 188.0071), # P3 corner
        'p_base_1': (230.9361, 159.7229), # P2 corner
        'u_sign': (1, -1),
        'v_sign': (1, 1),
    },
    {
        'quad': 'Q4 (SW)',
        'cheek_id': 'F_15',
        'p_horiz_id': 'PORT_3', # along horiz side (u=0)
        'p_vert_id': 'PORT_4',  # along vert side (u=40)
        'flap_horiz_id': 'F_13',
        'flap_vert_id': 'F_12',
        'flange_id': 'F_14',
        'bend_base': 'B4',
        'bend_horiz': 'B11',
        'bend_vert': 'B6',
        'bend_flange': 'FL1',
        'p_base_0': (104.6518, 188.0071), # P3 corner
        'p_base_1': (76.3675, 159.7229),  # P4 corner
        'u_sign': (-1, -1),
        'v_sign': (-1, 1),
    },
]

for q in quadrant_specs:
    p0 = q['p_base_0']
    p1 = q['p_base_1']
    dx = p1[0] - p0[0]
    dy = p1[1] - p0[1]
    L = math.hypot(dx, dy)
    ux = dx / L
    uy = dy / L
    # vx, vy normal pointing outward:
    # If base bend goes from P_horiz to P_vert, normal to the right (clockwise):
    # (ux, uy) rotated 90°:
    # In Q1: dx>0, dy>0. Center of cheek is x>202, y<83. So vx>0, vy<0.
    # (uy, -ux) = (0.7071, -0.7071). Exactly!
    vx = uy
    vy = -ux
    print(f"\n==================== {q['quad']} ====================")
    print(f"Base Bend: p0={p0} -> p1={p1}, L={L:.2f}")
    print(f"u_axis: ({ux:.4f}, {uy:.4f}), v_axis: ({vx:.4f}, {vy:.4f})")
    
    # Cheek vertices in local frame
    cheek = next(f for f in dsf['faces'] if f['id'] == q['cheek_id'])
    print(f"Cheek {q['cheek_id']}:")
    for vi, v in enumerate(cheek['vertices']):
        rx = v['x'] - p0[0]
        ry = v['y'] - p0[1]
        u = rx * ux + ry * uy
        v_coord = rx * vx + ry * vy
        print(f"  v{vi}: global=({v['x']:.2f}, {v['y']:.2f}) -> local=(u={u:.2f}, v={v_coord:.2f})")
        
    # Flap horiz
    f_h = next(f for f in dsf['faces'] if f['id'] == q['flap_horiz_id'])
    print(f"Flap Horiz {q['flap_horiz_id']}:")
    for vi, v in enumerate(f_h['vertices']):
        rx = v['x'] - p0[0]
        ry = v['y'] - p0[1]
        u = rx * ux + ry * uy
        v_coord = rx * vx + ry * vy
        print(f"  v{vi}: global=({v['x']:.2f}, {v['y']:.2f}) -> local=(u={u:.2f}, v={v_coord:.2f})")

    # Flap vert
    f_v = next(f for f in dsf['faces'] if f['id'] == q['flap_vert_id'])
    print(f"Flap Vert {q['flap_vert_id']}:")
    for vi, v in enumerate(f_v['vertices']):
        rx = v['x'] - p0[0]
        ry = v['y'] - p0[1]
        u = rx * ux + ry * uy
        v_coord = rx * vx + ry * vy
        print(f"  v{vi}: global=({v['x']:.2f}, {v['y']:.2f}) -> local=(u={u:.2f}, v={v_coord:.2f})")
