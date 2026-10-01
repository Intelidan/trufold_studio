import json

with open('assets/dsf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf') as f:
    d = json.load(f)

for f_data in d.get('faces', []):
    fid = f_data['id']
    pts = [(round(p['x'], 1), round(p['y'], 1)) for p in f_data.get('vertices', [])]
    print(f"{fid}: {pts}")
