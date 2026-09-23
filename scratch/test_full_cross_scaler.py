import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    baseline = json.load(f)

sq2 = 1.0 / math.sqrt(2)
X0 = 153.65180361560642
Y0 = 135.7228714274761
C = 40.0 * sq2 # 28.2842712474619

def run_cross_scaler(W1=100.0, H1=100.0, W2=50.0, H2=50.0, W3=100.0, H3=100.0, W4=50.0, H4=50.0):
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
    
    # 4 Quadrants
    quads = [
        {
            'name': 'Q1_NE',
            'cheek': 'F_3', 'flap_h': 'F_1', 'flap_v': 'F_0', 'flange': 'F_2',
            'b_base': 'B2', 'b_h': 'B9', 'b_v': 'B8', 'b_fl': 'FL3',
            'arcs_h': ('ARC_BND_12', 'ARC_BND_11'), # base, top
            'arcs_v': ('ARC_BND_9', 'ARC_BND_10'),  # base, top
            'punches_h': ['SLOT_7', 'SLOT_8'],
            'punches_v': ['SLOT_9'],
            'p0_base': (202.65180361560638, 83.43860018001283),
            'dp0': (dW1 / 2.0, -dW2 / 2.0),
            'u': (sq2, sq2), 'v': (sq2, -sq2),
            'H_h': H1, 'dH_h': dH1,
            'H_v': H2, 'dH_v': dH2,
            'rot_punch': 135.0,
            'new_punch_v_id': 'SLOT_9_B',
        },
        {
            'name': 'Q2_NW',
            'cheek': 'F_7', 'flap_h': 'F_5', 'flap_v': 'F_4', 'flange': 'F_6',
            'b_base': 'B1', 'b_h': 'B10', 'b_v': 'B5', 'b_fl': 'FL2',
            'arcs_h': ('ARC_BND_4', 'ARC_BND_3'),
            'arcs_v': ('ARC_BND_1', 'ARC_BND_2'),
            'punches_h': ['SLOT_1', 'PUNCH_CPY_8064'],
            'punches_v': ['SLOT_3'],
            'p0_base': (104.65180361560647, 83.43860018001283),
            'dp0': (-dW1 / 2.0, -dW4 / 2.0),
            'u': (-sq2, sq2), 'v': (-sq2, -sq2),
            'H_h': H1, 'dH_h': dH1,
            'H_v': H4, 'dH_v': dH4,
            'rot_punch': 45.0,
            'new_punch_v_id': 'SLOT_3_B',
        },
        {
            'name': 'Q3_SE',
            'cheek': 'F_11', 'flap_h': 'F_9', 'flap_v': 'F_8', 'flange': 'F_10',
            'b_base': 'B3', 'b_h': 'B12', 'b_v': 'B7', 'b_fl': 'FL4',
            'arcs_h': ('ARC_BND_16', 'ARC_BND_15'),
            'arcs_v': ('ARC_BND_13', 'ARC_BND_14'),
            'punches_h': ['SLOT_10', 'SLOT_11'],
            'punches_v': ['SLOT_12'],
            'p0_base': (202.65180361560638, 188.00714267493942),
            'dp0': (dW3 / 2.0, dW2 / 2.0),
            'u': (sq2, -sq2), 'v': (sq2, sq2),
            'H_h': H3, 'dH_h': dH3,
            'H_v': H2, 'dH_v': dH2,
            'rot_punch': 45.0,
            'new_punch_v_id': 'SLOT_12_B',
        },
        {
            'name': 'Q4_SW',
            'cheek': 'F_15', 'flap_h': 'F_13', 'flap_v': 'F_12', 'flange': 'F_14',
            'b_base': 'B4', 'b_h': 'B11', 'b_v': 'B6', 'b_fl': 'FL1',
            'arcs_h': ('ARC_BND_8', 'ARC_BND_7'),
            'arcs_v': ('ARC_BND_5', 'ARC_BND_6'),
            'punches_h': ['SLOT_4', 'SLOT_5'],
            'punches_v': ['SLOT_6'],
            'p0_base': (104.65180361560647, 188.00714267493925),
            'dp0': (-dW3 / 2.0, dW4 / 2.0),
            'u': (-sq2, -sq2), 'v': (-sq2, sq2),
            'H_h': H3, 'dH_h': dH3,
            'H_v': H4, 'dH_v': dH4,
            'rot_punch': 135.0,
            'new_punch_v_id': 'SLOT_6_B',
        },
    ]

    # Map entity id to quadrant
    quad_by_face = {}
    quad_by_bend = {}
    quad_by_arc = {}
    quad_by_punch = {}
    for q in quads:
        for fid in [q['cheek'], q['flap_h'], q['flap_v'], q['flange']]:
            quad_by_face[fid] = q
        for bid in [q['b_base'], q['b_h'], q['b_v'], q['b_fl']]:
            quad_by_bend[bid] = q
        for aid in [q['arcs_h'][0], q['arcs_h'][1], q['arcs_v'][0], q['arcs_v'][1]]:
            quad_by_arc[aid] = q
        for pid in q['punches_h'] + q['punches_v']:
            quad_by_punch[pid] = q

    def transform_quad_pt(pt, q, fid=None, bid=None, pid=None, aid=None):
        p0 = q['p0_base']
        dp0 = q['dp0']
        u = q['u']
        v = q['v']
        
        rx = pt['x'] - p0[0]
        ry = pt['y'] - p0[1]
        lu = rx * u[0] + ry * u[1]
        lv = rx * v[0] + ry * v[1]
        
        dH_h = q['dH_h']
        dH_v = q['dH_v']
        H_h = q['H_h']
        H_v = q['H_v']
        
        lu_star = lu
        lv_star = lv
        
        if fid == q['flap_h'] or bid == q['b_h']:
            if lv > 20.0:
                lv_star = lv + dH_h
        elif fid == q['flap_v'] or bid == q['b_v']:
            if lv > 20.0:
                lv_star = lv + dH_v
        elif fid == q['flange'] or bid == q['b_fl']:
            lv_star = lv + dH_body
        elif fid == q['cheek']:
            if lv < 5.0:
                lv_star = lv
            elif abs(lu - 40.0) < 5.0:
                if lv < 70.0:
                    lv_star = lv + dH_v
                else:
                    lv_star = lv + dH_body
            elif abs(lu) < 5.0:
                lv_star = lv + dH_body
        elif aid:
            if aid == q['arcs_h'][1]:
                lv_star = lv + dH_h
            elif aid == q['arcs_v'][1]:
                lv_star = lv + dH_v
        elif pid:
            if pid in q['punches_h']:
                if pid == q['punches_h'][0]:
                    if H_h < 95.0:
                        lv_star = lv + (dH_h + 50.0) / 2.0
                    else:
                        lv_star = lv
                else: # second slot
                    lv_star = lv + dH_h
            elif pid in q['punches_v']:
                if H_v < 95.0:
                    lv_star = lv + dH_v / 2.0
                else:
                    lv_star = lv
                    
        gx = p0[0] + dp0[0] + lu_star * u[0] + lv_star * v[0]
        gy = p0[1] + dp0[1] + lu_star * u[1] + lv_star * v[1]
        return {'x': gx, 'y': gy}

    # Transform Base Floor F_16
    unbent_W1 = 98.0 + dW1
    unbent_W2 = 48.0 + dW2
    unbent_W3 = 98.0 + dW3
    unbent_W4 = 48.0 + dW4
    
    new_f16_verts = [
        {'x': X0 - unbent_W3/2 - C, 'y': Y0 + unbent_W4/2},     # v0: P4 bottom
        {'x': X0 - unbent_W1/2 - C, 'y': Y0 - unbent_W4/2},     # v1: P4 top
        {'x': X0 - unbent_W1/2,     'y': Y0 - unbent_W4/2 - C}, # v2: P1 left
        {'x': X0 + unbent_W1/2,     'y': Y0 - unbent_W2/2 - C}, # v3: P1 right
        {'x': X0 + unbent_W1/2 + C, 'y': Y0 - unbent_W2/2},     # v4: P2 top
        {'x': X0 + unbent_W3/2 + C, 'y': Y0 + unbent_W2/2},     # v5: P2 bottom
        {'x': X0 + unbent_W3/2,     'y': Y0 + unbent_W2/2 + C}, # v6: P3 right
        {'x': X0 - unbent_W3/2,     'y': Y0 + unbent_W4/2 + C}, # v7: P3 left
    ]

    # Transform Faces
    face_vertex_map = {}
    new_faces = []
    for f in baseline['faces']:
        fid = f['id']
        if fid == 'F_16':
            new_faces.append({**f, 'vertices': new_f16_verts})
            for vi, v in enumerate(new_f16_verts):
                face_vertex_map[f"F_16_v{vi}"] = v
            continue
            
        q = quad_by_face[fid]
        nverts = []
        for vi, v in enumerate(f['vertices']):
            nv = transform_quad_pt(v, q, fid=fid)
            nverts.append(nv)
            face_vertex_map[f"{fid}_v{vi}"] = nv
        new_faces.append({**f, 'vertices': nverts})

    # Transform Bends
    new_bends = []
    for b in baseline['bends']:
        bid = b['id']
        q = quad_by_bend[bid]
        np1 = transform_quad_pt(b['p1'], q, bid=bid)
        np2 = transform_quad_pt(b['p2'], q, bid=bid)
        new_bends.append({**b, 'p1': np1, 'p2': np2})

    # Transform Arcs
    new_arcs = []
    for a in baseline['arcs']:
        aid = a['id']
        q = quad_by_arc[aid]
        nc = transform_quad_pt(a['center'], q, aid=aid)
        new_arcs.append({**a, 'center': nc})

    # Transform Punches (universal 95mm rule)
    suppressed_punches = set()
    if H1 < 95.0:
        suppressed_punches.add('SLOT_8')
        suppressed_punches.add('PUNCH_CPY_8064')
    if H3 < 95.0:
        suppressed_punches.add('SLOT_5')
        suppressed_punches.add('SLOT_11')

    new_punches = []
    for p in baseline['punches']:
        pid = p['id']
        if pid in suppressed_punches:
            continue
        q = quad_by_punch[pid]
        nc = transform_quad_pt(p['center'], q, pid=pid)
        new_punches.append({**p, 'center': nc})

    # Synthesize 2nd slots on vertical flaps if H2 >= 95 or H4 >= 95
    for q in quads:
        if q['H_v'] >= 95.0:
            # Slot on flap_v at u=58.0, v=74.0 + (dH_v - 50.0)
            u_star = 58.0
            v_star = 74.0 + (q['dH_v'] - 50.0 if q['dH_v'] > 50.0 else 0.0)
            p0 = q['p0_base']
            dp0 = q['dp0']
            u = q['u']
            v = q['v']
            gx = p0[0] + dp0[0] + u_star * u[0] + v_star * v[0]
            gy = p0[1] + dp0[1] + u_star * u[1] + v_star * v[1]
            new_punches.append({
                'id': q['new_punch_v_id'],
                'type': 'obroundSlot',
                'center': {'x': gx, 'y': gy},
                'widthMm': 8.0,
                'lengthMm': 20.0,
                'rotationDeg': q['rot_punch'],
                'role': 'coupler',
                'parentFaceId': q['flap_v'],
            })

    # Transform Outer Contour
    new_contour = []
    for ci, cp in enumerate(baseline['outerContour']):
        # Find matching face vertex from baseline
        matched_key = None
        for bf in baseline['faces']:
            for vi, bv in enumerate(bf['vertices']):
                if math.hypot(bv['x'] - cp['x'], bv['y'] - cp['y']) < 1e-3:
                    matched_key = f"{bf['id']}_v{vi}"
                    break
            if matched_key:
                break
        if matched_key and matched_key in face_vertex_map:
            new_contour.append(face_vertex_map[matched_key])
        else:
            new_contour.append(cp)

    return {
        'faces': new_faces,
        'bends': new_bends,
        'arcs': new_arcs,
        'punches': new_punches,
        'outerContour': new_contour,
    }

# Test 1: Zero Delta Baseline Invariance
res_base = run_cross_scaler()
max_diff = 0.0
for f1, f2 in zip(baseline['faces'], res_base['faces']):
    for v1, v2 in zip(f1['vertices'], f2['vertices']):
        d = math.hypot(v1['x'] - v2['x'], v1['y'] - v2['y'])
        max_diff = max(max_diff, d)
print(f"Test 1 (Baseline Invariance): max face vertex diff = {max_diff:.4e}")

# Test 2: Arcs Baseline Invariance
arc_diff = 0.0
for a1, a2 in zip(baseline['arcs'], res_base['arcs']):
    d = math.hypot(a1['center']['x'] - a2['center']['x'], a1['center']['y'] - a2['center']['y'])
    arc_diff = max(arc_diff, d)
print(f"Test 2 (Arc Center Invariance): max arc center diff = {arc_diff:.4e}")

# Test 3: Punches Baseline Invariance
punch_diff = 0.0
for p1, p2 in zip(baseline['punches'], res_base['punches']):
    d = math.hypot(p1['center']['x'] - p2['center']['x'], p1['center']['y'] - p2['center']['y'])
    punch_diff = max(punch_diff, d)
print(f"Test 3 (Punch Center Invariance): max punch center diff = {punch_diff:.4e}")

# Test 4: Contour Baseline Invariance
cnt_diff = 0.0
for c1, c2 in zip(baseline['outerContour'], res_base['outerContour']):
    d = math.hypot(c1['x'] - c2['x'], c1['y'] - c2['y'])
    cnt_diff = max(cnt_diff, d)
print(f"Test 4 (Contour Invariance): max contour point diff = {cnt_diff:.4e}")

# Test 5: Scaling Port 2 H2 to 95mm (Synthesize 2nd slots on Port 2 flaps)
res_95 = run_cross_scaler(H2=95.0)
print(f"Test 5 (H2=95mm): Punches count = {len(res_95['punches'])} (expected 14: 12 + 2)")

# Test 6: Scaling Port 1 H1 to 75mm (Suppress 2nd slots on Port 1 flaps)
res_75 = run_cross_scaler(H1=75.0)
print(f"Test 6 (H1=75mm): Punches count = {len(res_75['punches'])} (expected 10: 12 - 2)")
