import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    dsf = json.load(f)

f16 = dsf['faces'][16]
verts = f16['vertices']

# v0: (76.3675, 159.7229)  - P4 bottom corner (connected to B4)
# v1: (76.3675, 111.7229)  - P4 top corner (connected to B1)
# v2: (104.6518, 83.4386)  - P1 left corner (connected to B1)
# v3: (202.6518, 83.4386)  - P1 right corner (connected to B2)
# v4: (230.9361, 111.7229) - P2 top corner (connected to B2)
# v5: (230.9361, 159.7229) - P2 bottom corner (connected to B3)
# v6: (202.6518, 188.0071) - P3 right corner (connected to B3)
# v7: (104.6518, 188.0071) - P3 left corner (connected to B4)

print("Baseline Dimensions:")
print(f"P1 opening (v2 to v3): x from {verts[2]['x']} to {verts[3]['x']}, length = {verts[3]['x'] - verts[2]['x']}")
print(f"P2 opening (v4 to v5): y from {verts[4]['y']} to {verts[5]['y']}, length = {verts[5]['y'] - verts[4]['y']}")
print(f"P3 opening (v7 to v6): x from {verts[7]['x']} to {verts[6]['x']}, length = {verts[6]['x'] - verts[7]['x']}")
print(f"P4 opening (v1 to v0): y from {verts[1]['y']} to {verts[0]['y']}, length = {verts[0]['y'] - verts[1]['y']}")

print("\nDiagonal Bends:")
print(f"B1 (v1 to v2): dx = {verts[2]['x'] - verts[1]['x']}, dy = {verts[2]['y'] - verts[1]['y']}")
print(f"B2 (v3 to v4): dx = {verts[4]['x'] - verts[3]['x']}, dy = {verts[4]['y'] - verts[3]['y']}")
print(f"B3 (v5 to v6): dx = {verts[6]['x'] - verts[5]['x']}, dy = {verts[6]['y'] - verts[5]['y']}")
print(f"B4 (v7 to v0): dx = {verts[0]['x'] - verts[7]['x']}, dy = {verts[0]['y'] - verts[7]['y']}")
