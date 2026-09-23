import json
import math

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dsf', 'r') as f:
    baseline = json.load(f)

# Let's inspect the contour indices around the 4 horizontal flap junctions:
# Q2: ci=8 (F_6_v2), ci=9 (F_5_v0, F_6_v3, F_7_v0), ci=10 (F_5_v1)
# Q1: ci=19 (F_1_v4), ci=20 (F_1_v5, F_2_v0, F_3_v4), ci=21 (F_2_v1)
# Q3: ci=36 (F_10_v2), ci=37 (F_9_v0, F_10_v3, F_11_v0), ci=38 (F_9_v1)
# Q4: ci=47 (F_13_v4), ci=48 (F_13_v5, F_14_v0, F_15_v4), ci=49 (F_14_v1)

print("Contour point 9:")
print("  baseline:", baseline['outerContour'][9])
print("Contour point 20:")
print("  baseline:", baseline['outerContour'][20])
print("Contour point 37:")
print("  baseline:", baseline['outerContour'][37])
print("Contour point 48:")
print("  baseline:", baseline['outerContour'][48])
