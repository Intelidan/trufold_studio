import math

# Baseline
h1 = 100.0
h2 = 100.0
h3 = 50.0
L_flap = 30.0

w1 = 100.0
w2 = 100.0
w3 = 50.0

pB1Top = (44.55, 163.00)
pBranchLeft = (187.42, 305.87)

dx = pBranchLeft[0] - pB1Top[0]
dy = pBranchLeft[1] - pB1Top[1]
theta1 = math.atan2(dy, dx)
theta1_deg = math.degrees(theta1)
print(f"B1 angle: {theta1_deg:.2f} deg")

beta1 = 180.0 - theta1_deg
beta3 = 90.0 + theta1_deg
print(f"Flap 1 bend angle at Port 1: {beta1:.2f} deg")
print(f"Flap 3 bend angle at Port 3: {beta3:.2f} deg")

# Test non-equal width: W1=150, W2=100, W3=50
# pB1Top = (44.55 - 50, 163.00) = (-5.45, 163.00)
# pBranchLeft = (212.42 - 25, 305.87) = (187.42, 305.87)
dx_unequal = 187.42 - (-5.45) # 192.87
dy_unequal = 305.87 - 163.00 # 142.87
theta_unequal = math.atan2(dy_unequal, dx_unequal)
theta_unequal_deg = math.degrees(theta_unequal)
print(f"\nUnequal W1=150 B1 angle: {theta_unequal_deg:.2f} deg")
beta1_unequal = 180.0 - theta_unequal_deg
beta3_unequal = 90.0 + theta_unequal_deg
print(f"Flap 1 bend angle (realigned): {beta1_unequal:.2f} deg")
print(f"Flap 3 bend angle (realigned): {beta3_unequal:.2f} deg")
