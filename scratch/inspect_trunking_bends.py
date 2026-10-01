import json
import math

with open('assets/dsf_templates/trunking_accessories/unequal_tee_100x100x50x100x100x50x50.dsf') as f:
    d = json.load(f)

# Let's inspect the bends in trunking unequal tee:
bends = d.get('bends', [])
for b in bends:
    print(f"Bend {b['id']}: parent={b['parentFaceId']} -> child={b['childFaceId']} angle={b['targetAngleDeg']} dir={b['direction']}")
    print(f"   p1=({b['p1']['x']}, {b['p1']['y']}) -> p2=({b['p2']['x']}, {b['p2']['y']})")
