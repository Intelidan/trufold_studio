import json

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

if dsf.get('arcs'):
    print("Arc keys:", list(dsf['arcs'][0].keys()))
    for i, a in enumerate(dsf['arcs']):
        print(f"Arc {i}: {a}")

if dsf.get('punches'):
    print("\nPunch keys:", list(dsf['punches'][0].keys()))
    for i, p in enumerate(dsf['punches']):
        print(f"Punch {i}: {p}")
