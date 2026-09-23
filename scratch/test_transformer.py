import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

sq2 = 1.0 / math.sqrt(2)

def transform_pt(pt, q, fid=None, bid=None, pid=None, aid=None, params=None):
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
    dH_body = q['dH_body']
    H_h = q['H_h']
    H_v = q['H_v']
    
    lu_star = lu
    lv_star = lv
    
    # Transform lv based on face / entity role
    if fid == q['flap_h'] or bid == q['bend_h_id']:
        if lv > 20.0:
            lv_star = lv + dH_h
    elif fid == q['flap_v'] or bid == q['bend_v_id']:
        if lv > 20.0:
            lv_star = lv + dH_v
    elif fid == q['flange'] or bid == q['bend_fl_id']:
        lv_star = lv + dH_body
    elif fid == q['cheek']:
        # Cheek sidewall:
        # Base vertices at lv < 5 stay at 0
        if lv < 5.0:
            lv_star = lv
        elif abs(lu - 40.0) < 5.0:
            # Vertex at u=40:
            # If lv is near 48, it connects to Flap Vert -> scales with dH_v
            # If lv is near 98, it connects to Return Flange -> scales with dH_body
            if lv < 70.0:
                lv_star = lv + dH_v
            else:
                lv_star = lv + dH_body
        elif abs(lu) < 5.0:
            # Vertex at u=0:
            # Connects to Flange -> scales with dH_body
            lv_star = lv + dH_body
    elif aid:
        # Arcs: base arcs (lv < 20) stay at lv; top arcs scale with port height
        if aid == q['arcs_h'][1]: # top arc of horiz flap
            lv_star = lv + dH_h
        elif aid == q['arcs_v'][1]: # top arc of vert flap
            lv_star = lv + dH_v
        else:
            lv_star = lv
    elif pid:
        # Punches:
        if pid in q['punches_h']:
            if pid == q['punches_h'][0]: # first slot
                if H_h < 95.0:
                    lv_star = lv + (dH_h + 50.0) / 2.0
                else:
                    lv_star = lv
            elif len(q['punches_h']) > 1 and pid == q['punches_h'][1]: # second slot
                lv_star = lv + dH_h
        elif pid in q['punches_v']:
            if H_v < 95.0:
                lv_star = lv + dH_v / 2.0
            else:
                lv_star = lv

    # Reconstruct global point: (p0 + dp0) + lu_star * u + lv_star * v
    gx = p0[0] + dp0[0] + lu_star * u[0] + lv_star * v[0]
    gy = p0[1] + dp0[1] + lu_star * u[1] + lv_star * v[1]
    return {'x': gx, 'y': gy}

print("Point transformer defined.")
