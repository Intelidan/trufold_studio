import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

# Let's inspect each face's vertices in detail
for f in dsf['faces']:
    fid = f['id']
    print(f"\n--- {fid} ---")
    for vi, v in enumerate(f['vertices']):
        print(f"  v{vi}: ({v['x']:.4f}, {v['y']:.4f})")

# Let's inspect outer contour
print(f"\n--- Outer Contour ({len(dsf['outerContour'])} points) ---")
for ci, cp in enumerate(dsf['outerContour']):
    # check which face vertex it matches
    matched = []
    for f in dsf['faces']:
        for vi, v in enumerate(f['vertices']):
            if math.hypot(v['x'] - cp['x'], v['y'] - cp['y']) < 0.01:
                matched.append(f"{f['id']}_v{vi}")
    print(f"ci={ci:2d}: ({cp['x']:.2f}, {cp['y']:.2f}) -> {', '.join(matched)}")
