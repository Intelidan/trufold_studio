# TruFold Studio — Automatic Port Discovery from DSF Bends + Folded 3D Model

## Agent Implementation Walkthrough

### Purpose

This walkthrough adds a critical refinement to the CMS Template Authoring workflow:

> **Do not require the user to manually identify every physical port when TruFold can derive the ports from the existing DSF bend information and the already-working folded 3D model.**

The user should provide product intent and the required bend information. Once the folded model is valid, TruFold should inspect the resulting 3D topology, automatically detect the physical openings, calculate their dimensions, compare them with the dimensions entered by the user, and only ask the user to resolve ambiguity.

This is especially important for fittings where the relationship between ports and bend/flange lines is not one-to-one.

Example:

```text
45° Bend

Physical ports: 2
Bend lines:     3
Flange lines:   2
```

Therefore the authoring workflow must never assume:

```text
1 Port = 1 Bend = 1 Flange
```

Instead, physical ports, bends, flanges, and hole groups are separate semantic entities connected through geometry/topology relationships.

---

# 1. Core Architectural Principle

The existing application already has the most valuable pieces required for automatic discovery:

```text
DXF
  +
DSF bend/fold information
  ↓
Existing sheet-metal calculations
  ↓
Existing folded 3D simulation
  ↓
3D structural/topological analysis
  ↓
Automatic physical-port discovery
  ↓
Dimension measurement + expected-dimension matching
  ↓
Semantic role suggestion (optional)
  ↓
User confirmation only when required
```

Do not create a second bend solver or a separate 3D geometry engine for this feature.

Reuse the current systems.

---

# 2. The Important Distinction: Port vs Bend vs Flange vs Role

The implementation must maintain four separate concepts.

## 2.1 Physical Port

A physical port is an actual opening/terminal connection of the finished folded product.

Examples:

```text
45° Bend       → 2 physical openings
Reducer        → 2 physical openings
Equal Tee      → 3 physical openings
Unequal Tee    → 3 physical openings
Equal Cross    → 4 physical openings
Unequal Cross  → 4 physical openings
```

A port must be identified from the resulting folded geometry/topology, not from the number of bend lines.

## 2.2 Bend Feature

A bend is a sheet-metal fold relationship between adjacent faces.

Multiple bends can contribute to a single fitting.

A bend does not inherently belong exclusively to one port.

## 2.3 Flange Feature

A flange is a terminal/formed face or feature associated with a bend/face relationship.

A product can contain a different number of flange lines than physical ports.

## 2.4 Semantic Flow Role

A physical port may optionally receive a semantic role:

```text
INLET
OUTLET
MAIN
BRANCH
UNASSIGNED
BIDIRECTIONAL
```

Do not make role assignment part of physical-port detection.

For example:

- Bend/riser: either physical end may be inlet or outlet.
- Equal tee: all three ports can be identified without inventing flow direction.
- Equal cross: all four ports can be identified without inventing flow direction.
- Unequal tee/cross: the largest-width port can be suggested as the main/inlet candidate, while the remaining ports can be suggested as branches/outlets.

All such role assignments must remain editable by the user.

---

# 3. Desired CMS Authoring Experience

The user experience should evolve toward:

```text
Open DXF
   ↓
"Is this a CMS Part Drawing?"
   ↓ YES
Category
   ↓
Product Type
   ↓
Variation
   ↓
Dynamic expected-port form
   ↓
Enter key dimensions
   ↓
Guided bend/flange/coupler authoring only where needed
   ↓
Build/rebuild folded 3D model
   ↓
Automatic physical-port discovery
   ↓
Dimension matching
   ↓
Role suggestions where applicable
   ↓
User confirms only ambiguous items
   ↓
"What TruFold Learned"
   ↓
Interactive scaling preview
   ↓
Validation
   ↓
Save intelligent DSF
```

The application's objective is to reduce manual marking over time.

---

# 4. Why Automatic Port Discovery Is Better Than Port-by-Port Marking

The current guided workflow can fail when it interprets features as belonging directly to a port.

For example, a 45° bend has:

```text
2 ports
3 bend lines
2 flange lines
```

A workflow that says:

```text
PORT 1
  Add bend line
  Add flange line

PORT 2
  Add bend line
  Add flange line
```

cannot represent the product correctly.

The correct approach is:

```text
Product variation contract
        ↓
Expected structural features
        ↓
Bends / flanges established
        ↓
Folded 3D model
        ↓
Openings detected
        ↓
Physical ports derived
```

The user should not have to explain to the application information that the folded topology can already reveal.

---

# 5. When Should Port Discovery Run?

Port discovery should run whenever enough information exists to produce a valid or structurally analyzable folded model.

Minimum preferred condition:

```text
DXF loaded
+
DSF loaded/updated
+
required bend information available
+
3D fold calculation succeeds
```

The engine should then automatically call something similar to:

```dart
await discoverPhysicalPorts();
```

Do not wait until the end of the entire CMS workflow if the current model is already sufficient.

This allows the app to use discovery as part of the guided workflow.

---

# 6. Automatic Port Discovery Pipeline

Implement the pipeline in the following order.

```text
STEP A
Load/reconcile DXF + DSF
        ↓
STEP B
Run existing bend/fold calculations
        ↓
STEP C
Build/read folded 3D topology
        ↓
STEP D
Collect boundary edges / boundary loops
        ↓
STEP E
Find candidate openings
        ↓
STEP F
Group edges into opening regions
        ↓
STEP G
Measure opening W × H and other geometry
        ↓
STEP H
Compare candidates to product-variation expectations
        ↓
STEP I
Assign stable PhysicalPort IDs
        ↓
STEP J
Assign confidence
        ↓
STEP K
Optionally suggest semantic roles
        ↓
STEP L
Ask the user only if ambiguity remains
```

---

# 7. Use the Existing 3D Model as the Structural Truth

The existing 3D simulator already folds faces based on DSF bend information.

Do not try to rediscover ports primarily from raw DXF edges.

Use the folded result because it represents how the finished sheet-metal part actually looks.

The analyzer should have access to:

```text
Folded Faces
Face IDs
Face Normals
Face Adjacency
Bend IDs
Bend-to-face relationships
Boundary Edges
Boundary Loops
Vertex connectivity
Folded coordinates
```

If the existing engine exposes different names, reuse its actual types instead of creating duplicate geometry types.

---

# 8. Candidate Opening Detection

A physical port normally manifests as an opening at the terminal boundary of the folded product.

The first implementation should therefore analyze open boundary loops.

Conceptually:

```text
Folded solid/sheet-metal topology
          ↓
Boundary edges not paired with another face
          ↓
Connected boundary components
          ↓
Candidate opening loops
```

For each candidate loop, calculate:

- edge count
- perimeter
- planar/non-planar status
- approximate plane
- plane normal
- bounding box
- projected width
- projected height
- center point
- orientation
- host/adjacent face IDs
- connected bend/face ancestry

Do not assume every boundary is a port.

A candidate classifier must follow.

---

# 9. Candidate Opening Classification

Not every open boundary should become a port.

Possible categories:

```text
PORT_CANDIDATE
FLANGE_OPEN_BOUNDARY
RELIEF_BOUNDARY
MANUFACTURING_NOTCH
INTERNAL_CUTOUT
OTHER
```

Use product-variation rules plus topology and geometry to classify candidates.

Important signals include:

1. Candidate is at the terminal end of a connected wall system.
2. Candidate has the expected approximate opening dimensions.
3. Candidate orientation is consistent with the fitting geometry.
4. Candidate is connected to the expected folded face chain.
5. Candidate is not a small relief/notch.
6. Candidate count is consistent with the product variation.
7. Candidate location agrees with known product topology.

The classifier should produce a score/confidence rather than a binary guess.

---

# 10. Expected Port Count Comes from the Product Variation

The product-variation contract should define expected topology.

Example:

```text
45° Bend
expected physical ports = 2

90° Bend
expected physical ports = 2

Riser
expected physical ports = 2

Reducer
expected physical ports = 2

Equal Tee
expected physical ports = 3

Unequal Tee
expected physical ports = 3

Equal Cross
expected physical ports = 4

Unequal Cross
expected physical ports = 4
```

The analyzer should compare:

```text
Expected Port Count
vs
Detected Candidate Count
```

Example:

```text
Expected: 2
Detected: 2

→ Excellent match
```

or:

```text
Expected: 3
Detected: 4

→ Ambiguous; ask user to review
```

Never silently select arbitrary candidates when counts do not match.

---

# 11. Use User-Entered Port Dimensions as a Powerful Matching Signal

The dynamic product-intent form should allow the user to provide physical dimensions before or during analysis.

Example:

```text
Port 1
W = 300 mm
H = 150 mm

Port 2
W = 200 mm
H = 100 mm

Port 3
W = 200 mm
H = 100 mm
```

After 3D folding, suppose the analyzer finds:

```text
Candidate A = 299.8 × 150.1
Candidate B = 200.2 × 100.0
Candidate C = 199.9 × 100.1
```

The system should match candidates to expected ports using dimensional tolerance.

Conceptually:

```text
matchScore =
    dimensionSimilarity
  + topologySimilarity
  + expectedOrientation
  + location/connection evidence
```

Use tolerances rather than exact equality because bend calculations, numerical precision, and geometric projection can introduce small differences.

---

# 12. Do Not Depend Only on Bounding Boxes

A simple bounding box is useful but must not be the only measurement method.

Depending on the existing geometry engine, calculate opening dimensions using the plane of the opening and the actual terminal boundary.

For example:

```text
3D opening loop
      ↓
Fit/derive opening plane
      ↓
Project loop into local 2D coordinates
      ↓
Determine width
Determine height
      ↓
Compare with expected W × H
```

For non-rectangular or manufacturing-tolerant openings, the implementation should retain the full loop geometry and not destroy it just because width/height were calculated.

---

# 13. Establish Stable Physical Port IDs

Once candidates are accepted, assign stable IDs:

```text
PORT_1
PORT_2
PORT_3
PORT_4
```

The ID must persist through authoring and scaling as long as the topology remains equivalent.

Do not use array position alone as a persistent identity.

Store a stable semantic ID and structural references such as:

```text
portId
hostFaceIds
boundaryEdgeIds
boundaryLoopId
center
normal
width
height
orientation
confidence
source
```

If geometry changes significantly during scaling, the system should re-identify and reconcile the same semantic port rather than blindly replacing IDs.

---

# 14. Port Identification Should Be Independent of Inlet / Outlet Assignment

After physical ports are discovered, optionally run the semantic-role engine.

Example for a bend:

```text
PORT_1 = physical opening
PORT_2 = physical opening

Flow role:
Not assigned
```

Either physical port may later become inlet/outlet.

For equal tee:

```text
PORT_1
PORT_2
PORT_3

No automatic inlet assumed.
```

For unequal tee:

```text
PORT_1 = 300 × 150
PORT_2 = 200 × 100
PORT_3 = 200 × 100

Suggested:
PORT_1 → MAIN / INLET candidate
PORT_2 → BRANCH candidate
PORT_3 → BRANCH candidate
```

The suggestion must say why it was made:

```text
Reason: Port 1 has the largest opening width.
Confidence: Medium/High according to the configured rule.
```

The user can accept, change, or leave unassigned.

---

# 15. Guided Workflow Must Become Adaptive

The previous workflow should not create fixed steps such as:

```text
Port 1 bend
Port 1 flange
Port 2 bend
Port 2 flange
```

Instead generate steps based on what is actually required.

Example 45° Bend:

```text
Step 1
Confirm product intent

Step 2
Confirm expected port dimensions

Step 3
Ensure required bend information exists

Step 4
Fold 3D model

Step 5
Automatically discover 2 physical openings

Step 6
Confirm dimensions

Step 7
Define/confirm flange features if required

Step 8
Classify coupler holes if required

Step 9
Review learned template
```

The user should only be asked to manually draw/select something when the engine cannot derive it safely.

---

# 16. Guided Bend Authoring Must Be Structural, Not Port-Owned

When a variation requires 3 bends, the workflow should say:

```text
45° BEND
Required structural bends: 3

BEND_1  ○
BEND_2  ○
BEND_3  ○
```

Not:

```text
PORT_1
  Add bend

PORT_2
  Add bend
```

If the engine already recognizes one or more bend definitions from the DSF, mark them as satisfied.

Example:

```text
Required bends: 3
Already recognized: 2
Remaining: 1
```

Then guide the user specifically to the missing one.

---

# 17. Automatic Completion Detection

Every guided step should have a machine-checkable completion condition.

Example:

```text
Step: Confirm Port 1

Completion condition:
PhysicalPort PORT_1 exists
AND
confidence >= required threshold
AND
expected dimensions are within tolerance
```

For a bend step:

```text
Completion condition:
Required BendEntity exists
AND
its edge/face association is valid
```

For a flange step:

```text
Completion condition:
Required FlangeEntity exists
AND
its parent relation is valid
```

For coupler selection:

```text
Completion condition:
Expected coupler-hole group exists
AND
all required members are classified
```

Never advance merely because the user clicked `Accept & Continue` if the step has a verifiable condition.

---

# 18. Guided Selection Interaction Must Be a Real CAD Interaction Mode

When a step requires selection:

```text
Guidance step
   ↓
Activate interaction context
   ↓
Set selection filter
   ↓
Highlight candidates
   ↓
Enable correct tool automatically
   ↓
Hover preview
   ↓
Click
   ↓
Record semantic result
   ↓
Visual confirmation
   ↓
Validate completion
```

For example, when asking the user to confirm a candidate port:

- Hovering over the candidate should highlight it.
- Clicking should select it.
- The selected candidate should remain visibly highlighted.
- The HUD should update to `Selected`.
- The 3D corresponding opening should also highlight.
- The checklist should change from open to completed.

The user must never be left wondering whether the application registered the click.

---

# 19. Automatic Port Discovery Should Be Re-Runnable

Port detection is not a one-time operation.

It should run after significant geometric changes.

Examples:

```text
User adds bend
   ↓
Re-fold
   ↓
Re-analyze ports

User changes bend angle
   ↓
Re-fold
   ↓
Re-analyze ports

User changes port width
   ↓
Regenerate
   ↓
Re-analyze ports
```

The engine should attempt to reconcile old and new physical ports.

Example:

```text
Before:
PORT_1 → boundaryLoop_17

After scaling:
new boundaryLoop_43

Topology + geometry match old PORT_1

→ retain semantic PORT_1 ID
→ update structural references
```

---

# 20. Port Discovery Must Feed Parametric Scaling

The port is not merely something to label.

It should become an anchor for the parametric dependency graph.

Example:

```text
PortWidth
   ↓
Physical Port
   ↓
Terminal opening
   ↓
Host face / wall chain
   ↓
Connected bend positions
   ↓
Flange position
   ↓
Coupler-hole region
   ↓
Perforation region
   ↓
Flat pattern
   ↓
Existing sheet-metal engine
   ↓
3D model
```

Therefore automatic port detection is an important prerequisite for intelligent scaling.

---

# 21. Interactive Scaling Preview

When the user changes a parameter such as:

```text
Port Width: 300 → 350 mm
```

the system should perform:

```text
Parameter change
      ↓
Dependency lookup
      ↓
Update physical port target
      ↓
Regenerate dependent geometry
      ↓
Run existing sheet-metal calculations
      ↓
Fold 3D model
      ↓
Re-discover / reconcile ports
      ↓
Validate resulting W × H
      ↓
Update 2D + 3D preview
```

The scaling preview should not merely move a UI slider while leaving the underlying semantic model unchanged.

---

# 22. Handle Ambiguity Explicitly

Automatic discovery must not pretend certainty when the topology is ambiguous.

Example:

```text
Expected ports: 3
Detected candidates: 4
```

Show:

```text
TruFold found 4 possible openings.
The selected variation expects 3 ports.

Candidate A   300 × 150   96%
Candidate B   200 × 100   94%
Candidate C   200 × 100   93%
Candidate D    20 × 10    41%
```

The user can reject Candidate D.

Or:

```text
Port 1
Suggested: Candidate A
[Accept]
[Choose another]
```

The important principle is:

> **Automation first, user correction second.**

---

# 23. Confidence Levels

Use the existing confidence concept consistently.

```text
HIGH
Geometry, topology, count, and dimensions strongly agree.

MEDIUM
The candidate is plausible but needs verification.

LOW
The application cannot safely determine the result.
```

Suggested UI:

```text
● High confidence
● Medium confidence — verify
● Low confidence — action required
```

Do not use confidence to hide failures.

Low confidence must lead to an explicit user action or a clear explanation.

---

# 24. "What TruFold Learned" Should Show Physical Ports

The final review should say something concrete.

Example:

```text
WHAT TRUFOLD LEARNED

Product
45° Bend

Physical Ports
✓ Port 1   100 × 100 mm
✓ Port 2   100 × 100 mm

Structural Features
✓ Bend lines   3 / 3
✓ Flange lines 2 / 2

Coupler Features
✓ Groups detected

3D Structure
✓ Folded model valid
✓ Opening topology valid

Scaling
✓ Port Width linked
✓ Port Height linked
```

For an unequal tee:

```text
Physical Ports
✓ Port 1   300 × 150 mm
✓ Port 2   200 × 100 mm
✓ Port 3   200 × 100 mm

Suggested semantic roles
Port 1 → Main / Inlet candidate
Port 2 → Branch candidate
Port 3 → Branch candidate

[Accept suggestions]
[Review roles]
```

---

# 25. Data Model Recommendation

Extend the semantic model approximately as follows.

```dart
class PhysicalPort {
  final String id;
  final String variationId;

  final List<String> hostFaceIds;
  final String? boundaryLoopId;
  final List<String> boundaryEdgeIds;

  final double width;
  final double height;

  final Vector3 center;
  final Vector3 normal;
  final Vector3 widthDirection;
  final Vector3 heightDirection;

  final double confidence;
  final PortDetectionSource detectionSource;

  final PortRole? role;
  final PortRole? suggestedRole;
  final String? suggestionReason;
}
```

Keep role nullable.

Keep structural references separate from semantic labels.

---

# 26. Detection Source

Recommended enumeration:

```dart
enum PortDetectionSource {
  foldedTopology,
  dimensionMatched,
  productRule,
  userConfirmed,
  userMarked,
  migrated,
}
```

A port detected from topology and confirmed by the user can retain both pieces of provenance through separate metadata if required.

Do not overwrite provenance with a generic `automatic = true` flag.

---

# 27. Product Variation Contract

The variation contract should describe expected physical structure, not just UI fields.

Conceptually:

```dart
class ProductVariationContract {
  String productType;
  String variationName;

  ExpectedPortTopology portTopology;
  ExpectedFeatureSet structuralFeatures;
  RoleAssignmentRules? roleRules;
  HoleRules holeRules;
  ScalingRules scalingRules;
}
```

Example:

```text
45° Bend

Ports: 2
Bends: 3
Flanges: 2
Flow role: optional
```

Example:

```text
Unequal Tee

Ports: 3
Main width relation: largest-port candidate
Branch relation: remaining ports
Flow role: suggest only
```

Do not hardcode these rules inside canvas widgets.

---

# 28. Relationship Graph

Once discovery completes, build relationships such as:

```text
PhysicalPort P1
   │
   ├── boundaryLoop
   ├── hostFace(s)
   └── connected structural chain
             │
             ├── Bend B1
             ├── Bend B2
             └── Flange F1
```

Another port may share structural features:

```text
P1 ─── B2 ─── P2
       │
       └── shared structural relationship
```

This is allowed and expected.

The graph must support one bend being related to multiple semantic regions where the geometry requires it.

---

# 29. Coupler Hole Classification Should Also Use the Semantic Model

Coupler holes should remain distinct from general perforations.

Recommended classes:

```text
COUPLER_HOLE
PERFORATION_HOLE
OTHER_MANUFACTURING_HOLE
REFERENCE_HOLE
```

Once physical ports are known, coupler-hole regions can be evaluated relative to:

- port opening
- host face
- edge/port boundary
- expected coupler pattern

This is much more reliable than asking the user to manually click every slot when the geometry can reveal candidate groups.

---

# 30. Integration with Existing TopologicalZoneMorpher

The existing `TopologicalZoneMorpher` should not become the port-detection engine.

Recommended responsibility split:

```text
Port Discovery
    ↓
Identifies stable semantic regions and topology

Dependency / Parameter Engine
    ↓
Determines what should move and why

Feature Regeneration
    ↓
Updates geometry from parameters

TopologicalZoneMorpher
    ↓
Acts as a controlled geometry morphing fallback
    ↓
Only where parameterized regeneration cannot directly rebuild a zone
```

Do not use blind global stretching as the primary scaling mechanism.

---

# 31. 2D and 3D Must Remain Synchronized

When a port is selected in 2D:

```text
2D boundary/feature highlight
        ↕
3D folded opening highlight
```

When a 3D opening is selected:

```text
3D opening highlight
        ↕
2D source-region highlight
```

This cross-highlighting is important because users can understand a folded opening more easily than an abstract boundary loop, while the actual authoring geometry remains in the 2D DXF/DSF representation.

---

# 32. Example: 45° Bend End-to-End

This example should be implemented as an important proof of concept.

## Step 1 — User identifies CMS product

```text
Category: Tray Accessories
Product: Bend
Variation: 45° Bend
```

## Step 2 — Dynamic form

```text
Expected physical ports: 2

Port 1
W = 100
H = 100

Port 2
W = 100
H = 100
```

Flow role is left unassigned.

## Step 3 — Required structural features

The product contract says:

```text
Bend lines: 3
Flange lines: 2
```

The UI shows this independently from the physical ports.

## Step 4 — Guided bend completion

The application either detects existing DSF bends or guides the user to create the missing ones.

The progress card should say:

```text
Bends
✓ 1 / 3
✓ 2 / 3
● 3 / 3
```

not:

```text
Port 1 bend
Port 2 bend
```

## Step 5 — Fold the model

Existing engine produces the 3D bend.

## Step 6 — Automatic port discovery

The analyzer finds two terminal openings.

```text
Candidate A = 100.1 × 100.0
Candidate B = 99.9 × 100.2
```

Expected = 2.

Dimension agreement = good.

The app assigns:

```text
PORT_1 → Candidate A
PORT_2 → Candidate B
```

## Step 7 — User confirmation

```text
2 physical ports detected

✓ Port 1 100 × 100
✓ Port 2 100 × 100

[Accept & Continue]
```

No manual clicking is required unless the user wants to override.

## Step 8 — Flange classification

The system processes the expected 2 flange features separately.

## Step 9 — Coupler classification

The system identifies candidates or requests the user to select them only if confidence is low.

## Step 10 — Scaling

Changing width/height updates the semantic port and all dependent geometry, then refolds and revalidates the model.

---

# 33. Example: Unequal Tee

Input:

```text
Product: Tee
Variation: Unequal Tee

Port 1 = 300 × 150
Port 2 = 200 × 100
Port 3 = 200 × 100
```

After folding:

```text
3 terminal openings detected
```

The system matches dimensions.

Then it applies the optional role rule:

```text
Largest width = 300

Suggested:
Port 1 → MAIN / INLET candidate
Port 2 → BRANCH candidate
Port 3 → BRANCH candidate
```

The application must show that these are suggestions, not geometric facts.

---

# 34. Example: Equal Tee

Input:

```text
Product: Tee
Variation: Equal Tee

3 ports
all equal
```

After folding:

```text
3 openings detected
```

The app should say:

```text
3 physical ports identified.

No flow direction assigned because the selected variation does not
provide sufficient information to determine an inlet from geometry alone.
```

The user may assign roles later if needed.

---

# 35. Failure Handling

The discovery engine must produce meaningful diagnostics.

Examples:

### Fold failure

```text
3D folding could not be completed.
Port discovery is temporarily unavailable.

[Resolve Bend Data]
```

### Wrong port count

```text
Expected: 3 ports
Detected: 2

Possible causes:
- Missing bend information
- Incorrect flange/demarcation
- Geometry not connected

[Inspect 3D Model]
[Review Bend Features]
```

### Dimension mismatch

```text
Expected Port 1: 300 × 150
Detected candidate: 250 × 150

The opening was not automatically accepted.
```

Never silently convert a mismatch into a successful port.

---

# 36. Automation Maturity

Design this system so that manual interaction decreases as recognition improves.

## Level 1 — Guided Manual

User performs most demarcation with strong visual guidance.

## Level 2 — Suggested

TruFold detects candidates and user confirms them.

## Level 3 — High Confidence Automation

TruFold automatically accepts high-confidence ports and structural features.

## Level 4 — Exception Review

TruFold completes the template and asks the user to review only ambiguous items.

The architecture must support all four levels.

Do not make today's manual sequence the permanent architecture.

---

# 37. Recommended New Services / Components

Names may be adapted to existing architecture, but the responsibilities should be separated.

```text
Cms3DFoldAnalysisService
    Runs/reuses existing 3D fold result

CmsOpeningDetector
    Extracts candidate opening loops

CmsPortCandidateClassifier
    Determines which boundaries are likely physical ports

CmsPortDimensionAnalyzer
    Measures W × H and orientation

CmsPortMatcher
    Matches detected candidates to expected product ports

CmsPortReconciler
    Maintains stable IDs across model updates/scaling

CmsPortRoleSuggestionEngine
    Suggests semantic flow roles independently

CmsGuidedSelectionController
    Handles actual canvas interaction for manual confirmations

CmsWorkflowStepGenerator
    Generates adaptive workflow from variation + analysis state
```

Reuse existing geometry/model classes wherever possible.

---

# 38. Suggested APIs

Possible interfaces:

```dart
Future<PortDiscoveryResult> discoverPhysicalPorts({
  required FoldedModel foldedModel,
  required ProductVariationContract contract,
  List<ExpectedPort>? expectedPorts,
});
```

```dart
PortMatchResult matchPortCandidates({
  required List<PortCandidate> candidates,
  required List<ExpectedPort> expectedPorts,
});
```

```dart
RoleSuggestionResult suggestPortRoles({
  required List<PhysicalPort> ports,
  required ProductVariationContract contract,
});
```

```dart
PortReconciliationResult reconcilePorts({
  required List<PhysicalPort> previousPorts,
  required List<PhysicalPort> newPorts,
});
```

These are conceptual APIs; first inspect the codebase for existing equivalent services before adding new ones.

---

# 39. Test Strategy

## Unit Tests

Test at least:

```text
2-port bend → 2 openings
2-port reducer → 2 openings
3-port equal tee → 3 openings
3-port unequal tee → 3 openings
4-port equal cross → 4 openings
4-port unequal cross → 4 openings
```

Test dimension matching within tolerance.

Test wrong candidate count.

Test ambiguous candidate count.

Test port ID reconciliation after scaling.

Test role suggestions independently from physical detection.

## Integration Tests

```text
DXF + DSF
→ fold
→ discover openings
→ match expected ports
→ save DSF
→ reopen
→ rediscover/reconcile
```

## UI Tests

Verify:

- candidate hover highlight
- candidate selection
- accepted-state display
- 2D/3D cross-highlight
- automatic step advancement
- ambiguity dialog
- undo
- review summary

---

# 40. Acceptance Criteria

The implementation is complete when:

1. A CMS DXF can be opened through the intent-first workflow.
2. Product type and variation determine expected physical-port topology.
3. User-entered port dimensions can be stored independently from flow roles.
4. Existing DSF bend information is reused.
5. Existing 3D folding is reused.
6. A valid folded model can be analyzed for open boundaries.
7. Physical-port candidates can be detected automatically.
8. Candidate opening dimensions can be measured.
9. Candidates can be matched to expected ports with tolerances.
10. Stable physical-port IDs are created and reconciled after changes.
11. Inlet/outlet/branch roles remain separate from physical port detection.
12. Unequal fittings can receive role suggestions based on documented rules.
13. Ambiguous results are presented to the user rather than silently guessed.
14. Guided selection is a real interactive CAD mode when manual confirmation is needed.
15. Bend/flange feature counts are variation-driven and not port-owned.
16. Scaling uses semantic port anchors and dependencies.
17. Scaling refolds the 3D model and revalidates the resulting openings.
18. 2D and 3D views stay synchronized.
19. The final review explains exactly what TruFold learned.
20. Intelligent DSF preserves the semantic information and can be reopened without losing associations.

---

# 41. Agent Implementation Rules

### Rule 1 — Inspect before creating

Search the existing codebase for current DSF parsing, bend calculations, folded 3D topology, face/edge models, selection, and scaling before adding new implementations.

### Rule 2 — Reuse the existing fold engine

Do not build a parallel sheet-metal folding algorithm.

### Rule 3 — Physical ports come from folded geometry

Use 3D topology/openings as the primary source for physical-port discovery.

### Rule 4 — Product rules constrain interpretation

Use the variation contract to determine expected count/topology and to validate results.

### Rule 5 — User dimensions are evidence and constraints

Use entered W × H to improve candidate matching, not merely to display them.

### Rule 6 — Port and role are different

Never encode inlet/outlet semantics into the physical-port identity.

### Rule 7 — Bends and flanges are structural features

Do not assume one bend or one flange per port.

### Rule 8 — Manual interaction is the exception path

Use user selection when automatic detection has low confidence or ambiguity.

### Rule 9 — Every manual selection must be recorded

A click that produces no semantic state change is not an implemented workflow step.

### Rule 10 — Show state visually

Every selection must have hover, selected, confirmed, and error/invalid feedback as applicable.

### Rule 11 — Re-analyze after geometry changes

Port discovery must be re-runnable and reconciled after bend/parameter updates.

### Rule 12 — Keep 2D and 3D synchronized

A semantic object should map back to both its 2D source geometry and its 3D representation.

### Rule 13 — Fail explicitly

Do not turn uncertain geometry into a false successful template.

### Rule 14 — Protect existing behavior

Normal DXF mode and legacy DSF files must continue to work.

### Rule 15 — Build toward exception-only review

The architecture should allow increasing automation without rewriting the workflow later.

---

# 42. Recommended Implementation Order

Implement in this order:

```text
1. Audit existing folded-model/topology APIs

2. Build a read-only opening-boundary analyzer

3. Visualize all candidate openings in 3D

4. Measure candidate W × H

5. Add product-variation expected-port contracts

6. Match candidates to expected ports

7. Persist stable PhysicalPort entities

8. Add 2D ↔ 3D cross-highlighting

9. Add ambiguity resolution UI

10. Integrate with CMS guided workflow

11. Separate structural bend/flange steps from port steps

12. Add role suggestion engine

13. Connect discovered ports to scaling dependencies

14. Add re-fold + re-discovery after scaling

15. Add review/readiness screen

16. Expand to additional fitting variations
```

Start with one strong proof of concept:

```text
45° Bend
```

because it immediately proves that:

```text
2 ports
≠
3 bends
≠
2 flanges
```

and therefore validates the correct semantic architecture.

---

# 43. Final Target Architecture

```text
                    CMS PRODUCT INTENT
                           │
                           ▼
                 PRODUCT VARIATION CONTRACT
                           │
                           ▼
                    DXF + DSF INPUT
                           │
                           ▼
              EXISTING SHEET-METAL ENGINE
                           │
                           ▼
                  EXISTING FOLDED 3D MODEL
                           │
                           ▼
                ┌─────────────────────────┐
                │ 3D STRUCTURAL ANALYSIS │
                └────────────┬────────────┘
                             │
            ┌────────────────┼────────────────┐
            ▼                ▼                ▼
       Openings           Bends           Flanges
            │                │                │
            ▼                │                │
      Physical Ports         │                │
            │                │                │
            └────────────────┼────────────────┘
                             ▼
                    SEMANTIC RELATIONSHIPS
                             │
                 ┌───────────┴───────────┐
                 ▼                       ▼
          Optional Role Layer       Hole Classification
                 │                       │
                 └───────────┬───────────┘
                             ▼
                    PARAMETER / DEPENDENCY
                             │
                             ▼
                       INTELLIGENT SCALE
                             │
                    ┌────────┴────────┐
                    ▼                 ▼
                   2D                3D
                    │                 │
                    └────────┬────────┘
                             ▼
                         VALIDATION
                             │
                             ▼
                    INTELLIGENT DSF SAVE
```

## Final instruction to the implementing agent

> **Do not make the user manually mark information that TruFold can reliably derive from its own DSF and folded 3D calculations.**
>
> The user should provide product intent, key dimensions, and missing information. TruFold should use the DSF and existing 3D engine to discover the physical structure, identify openings, calculate port dimensions, establish semantic relationships, and propose the next action.
>
> **The application should behave like an intelligent engineering assistant: automatically analyze first, visually explain what it found, ask the user to confirm only where necessary, and then use the confirmed semantic structure for future scaling and automation.**
