import re

with open('assets/dxf_templates/trunking_accessories/unequal_cross_100x50x100x50.dxf', 'r') as f:
    content = f.read()

layers = set(re.findall(r'8\n([^\n]+)', content))
print("Layers in DXF:", layers)

texts = re.findall(r'TEXT\n[\s\S]*?1\n([^\n]+)', content)
print("Texts in DXF:", texts[:20])
