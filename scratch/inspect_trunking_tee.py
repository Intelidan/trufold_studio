import json

with open('assets/dsf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf') as f:
    d = json.load(f)

print("--- BENDS ---")
for b in d.get('bends', []):
    print(f"{b['id']}: p1=({b['p1']['x']:.1f}, {b['p1']['y']:.1f}) p2=({b['p2']['x']:.1f}, {b['p2']['y']:.1f}) angle={b.get('targetAngleDeg')} dir={b.get('direction')} parent={b.get('parentFaceId')} child={b.get('childFaceId')}")

print("\n--- FACES ---")
for face in d.get('faces', []):
    pts = [(p['x'], p['y']) for p in face.get('vertices', [])]
    print(f"{face['id']}: name={face.get('name')} {len(pts)} pts")
