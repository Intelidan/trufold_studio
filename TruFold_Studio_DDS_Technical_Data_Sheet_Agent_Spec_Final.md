# TruFold Studio — DDS Technical Data Sheet System
## Native `.dds` Document, Template-Driven Product Instances, Technical Presentation, Annotation & Client Approval Workflow

## 1. Purpose

Implement the next major TruFold Studio architecture: the **Technical Data Sheet (TDS) document system** using the native `.dds` extension.

A `.dds` file is a client-facing technical-data-sheet document containing one or more product instances based on the application's built-in CMS DSF templates.

The critical architectural rule is:

> **The DSF in the application's template library is the immutable base/template definition. The DDS stores the user's selected parameters and document-specific information. When a DDS is opened, TruFold resolves the referenced template and reapplies the stored instance parameters to regenerate the product.**

The DDS therefore behaves like a reusable technical-document package rather than a copied collection of mutable template drawings.

---

## 2. Research-Informed TDS Format Direction

Research into professional cable-management manufacturers and technical-documentation conventions shows a recurring format that should guide TruFold's presentation without copying any company's branding.

### 2.1 Product data + dimensional drawing

Professional manufacturer sheets commonly combine:

- product identification/reference,
- descriptive product/application information,
- dimensional tables,
- dimensioned technical drawings,
- isometric or product illustrations,
- technical properties,
- certification/compliance information where applicable.

Pemsa's current product data sheets, for example, combine product identity, an isometric/product illustration, technical drawings with dimensional callouts, and certification/compliance information. citeturn435260search63

OBO's current product information presents a product/type/reference followed by dimensions and a structured technical-data section, and separately exposes data-sheet and conformity documents. citeturn435260search0turn435260search1

Legrand technical sheets combine product/reference information with a dedicated dimensions section, dimension drawings, and a product-size table. citeturn435260search64

Niedax documentation similarly combines dimensional/isometric drawings with structured product tables containing identifiers and technical/product information. citeturn670279search49turn670279search51

### 2.2 Drawing/document control

The DDS presentation should use a professional technical-document title block rather than a simple graphic footer.

ISO 7200 specifies data fields for title blocks and document headers, including legal owner, identification number, revision index, date of issue, sheet number and number of sheets. ISO states that the standard applies to manual and computer-based technical documentation and is currently confirmed. citeturn193332search0turn193332search20

ISO 5457 covers sizes and layout of technical drawing sheets, including borders, title-block placement and sheet layout. citeturn158287search1turn158287search2

ISO 128-1 provides general principles for the representation of technical drawings and is currently confirmed. citeturn158287search0

TruFold should **use these as design guidance for document structure and representation**, not claim compliance with a standard unless the resulting implementation has actually been checked against the full standard.

---

## 3. DDS vs DSF — Fundamental Architecture

### 3.1 DSF remains the template

The existing DSF/CMS template remains the authoritative definition of the product's geometry and feature behavior.

A template contains or provides:

- base 2D geometry,
- bend definitions,
- bend direction,
- flange definitions,
- flange sizes/default relationships,
- coupler-hole definitions,
- punches/features,
- product topology,
- port definitions/roles,
- scaling rules,
- cover-generation rules where applicable,
- other information required by the CMS engine.

Templates reside inside the application template library.

### 3.2 DDS stores the product instance

The DDS does **not** overwrite the template.

It stores the current product-instance state, equivalent to the result of a user manually changing parameters in the application.

Conceptually:

```text
CMS Template Library
        |
        | templateId + templateVersion
        v
     DSF Template
        |
        | apply DDS parameter overrides
        v
   Product Instance
        |
        +--> 2D flat geometry
        +--> cover geometry
        +--> folded 3D geometry
        +--> dimensions
        +--> annotations
        +--> document presentation
```

### 3.3 DDS is the source of edited values

When a user changes a product parameter while working inside a DDS:

```text
User edits parameter
        ↓
DDS instance state changes
        ↓
Template remains unchanged
        ↓
Geometry regenerates from template + DDS state
```

The next time the DDS is opened, the same template is found and the stored values are reapplied.

---

## 4. A DDS Can Contain a Set of Product Sheets

A `.dds` should support multiple product entries/sheets.

Example:

```text
Project Technical Data Sheet
|
+-- Sheet 1: Cover / Document Information
|
+-- Sheet 2: Trunking 90° Bend
|
+-- Sheet 3: Trunking 45° Bend
|
+-- Sheet 4: Trunking Equal Tee
|
+-- Sheet 5: Trunking Unequal Tee
|
+-- Sheet 6: Trunking Reducer
|
+-- ...
```

Each product sheet references an application template and carries its own parameter snapshot.

This should allow one DDS to become an actual **technical submittal package** rather than requiring one file per product.

---

## 5. Excel Order / Product List Import

The DDS creation workflow must support importing an **Excel workbook (`.xlsx`) containing the customer's required products, order line items, or basic product schedule**.

This is a first-class DDS creation workflow. The objective is to allow a customer order/product schedule to become the initial DDS structure without requiring the user to manually create every product sheet.

### 5.1 Import workflow

```text
New Technical Data Sheet
        ↓
Create from Excel / Import Order List
        ↓
Select .xlsx file
        ↓
Select worksheet
        ↓
Preview detected rows
        ↓
Map spreadsheet columns to DDS fields
        ↓
Match order lines to CMS templates
        ↓
Review unresolved items
        ↓
Create DDS product instances
        ↓
Create initial Product Index / Sheet Navigator
        ↓
Open DDS for technical editing
```

The user should be able to create a **basic DDS document containing the required order/product list and initial product sheets in one operation**.

### 5.2 Excel is an import source, not a live dependency

The Excel workbook is only the source used during import. The resulting DDS must contain the imported information needed for the product/document state.

After import:

```text
Excel file
    ↓
DDS stores imported values + source traceability
    ↓
DDS can be opened independently
```

The DDS must remain usable if the original Excel workbook is moved, renamed, or deleted.

### 5.3 Flexible column mapping

Do not hard-code one customer's Excel column names. Provide a simple mapping interface.

Example:

| Excel column | DDS field |
|---|---|
| Order No. | orderNumber |
| Line No. | orderLine |
| Customer Item | customerItemReference |
| Description | customerDescription |
| Product Type | productType / template lookup |
| Width | engineering parameter |
| Height | engineering parameter |
| Branch Width | engineering parameter |
| Branch Height | engineering parameter |
| Length | engineering parameter |
| Quantity | quantity |
| Remarks | lineItemRemarks |

The mapping may be remembered for future imports, but the user must be able to change it.

### 5.4 Product/template matching

The importer should resolve each order line to the application's CMS template library using the strongest available identifier.

Preferred order:

```text
1. Exact product/template code
2. Exact internal product ID
3. Recognized product-type mapping
4. User-assisted template selection
5. Unresolved item requiring review
```

Do not silently substitute a different template because a name appears similar.

Unresolved items should be displayed clearly before DDS creation is finalized.

### 5.5 One order line becomes one DDS product instance by default

Each imported order line should normally create one **product instance** and one corresponding product-sheet entry.

The order quantity must not create duplicate geometry.

Example:

```text
Order Line 001
Product: Equal Tee 100 × 100
Quantity: 25

→ One DDS product instance
→ One product sheet
→ Quantity stored as order metadata = 25
```

If the same customer item occurs on multiple lines with different dimensions, references, or requirements, those lines remain separate product instances.

### 5.6 The imported order list should appear when the DDS is created

The newly created DDS should immediately show the imported items in the Product Index / Sheet Navigator.

Example:

```text
01  Cover / Document Information
02  TR-001  Equal Tee 100 × 100          Qty 12
03  TR-002  90° Bend 150 × 100            Qty 8
04  TR-003  Reducer 150/75                Qty 4
05  TR-004  Unequal Tee                   Qty 6
```

This list is the initial technical-submittal schedule and becomes the starting point for creating the client's TDS package.

### 5.7 Separate customer/order data from engineering parameters

A spreadsheet can contain both commercial/order information and engineering information. The DDS must keep them logically separate.

```text
ORDER / CUSTOMER DATA
- Order number
- Order line
- Customer item/reference
- Quantity
- Customer description
- Customer remarks

ENGINEERING INSTANCE DATA
- Template ID
- Template version/fingerprint
- Width / height / length
- Branch dimensions
- Product-specific parameters
- Cover state/configuration
- Material/thickness where applicable
```

Customer description must not automatically become the engineering product definition.

### 5.8 Preserve order-line traceability

Each imported product instance should retain sufficient source information for traceability, for example:

```text
sourceType: "excel"
sourceFileName: "Customer_Order.xlsx"
sourceSheet: "Order"
sourceRow: 27
orderNumber: "..."
orderLine: "..."
customerItemReference: "..."
```

These fields are stored metadata only. DDS does not require the source workbook for reopening.

### 5.9 Import summary and exceptions

After processing the workbook, show an import summary before final DDS creation:

```text
Import Complete

48 order lines detected
42 templates matched
4 require template selection
2 invalid/skipped rows

[Review Unresolved Items]
[Create DDS]
```

Invalid or unresolved rows must not disappear silently.

### 5.10 Initial DDS generation from Excel

The first DDS generated from an order workbook should contain at least:

```text
Document information
Imported order/product index
Product instances
Resolved template references
Imported engineering parameters where available
Quantities / customer references
Basic product sheets
```

The user then continues with normal DDS authoring:

```text
Edit dimensions
        ↓
Generate/update 2D + cover + 3D
        ↓
Add dimensions/annotations
        ↓
Add technical notes
        ↓
Set revision/document-control information
        ↓
Export client TDS PDF
```

### 5.11 Manual DDS creation remains available

Excel import is an additional workflow, not a replacement for manual DDS creation.

Users must still be able to:

```text
New DDS
   ↓
Add Product Sheet
   ↓
Select Template
```

when no Excel order list exists.

### 5.12 Future-ready re-import

Do not make the first implementation a live two-way Excel synchronization system.

The architecture should leave room for future commands such as:

```text
Create New DDS from Excel
Append Items from Excel
Update Imported Items from Excel
```

For the first implementation, **Create New DDS from Excel** is sufficient.

---

## 6. Recommended DDS Data Model

### Product instance vs sheet

The underlying engineering product instance should be separate from its presentation sheet.

```text
DDS Document
│
├── Product Instances
│     ├── Product A
│     ├── Product B
│     └── Product C
│
└── Sheets
      ├── Cover / Index
      ├── Product Sheet A
      ├── Product Sheet B
      └── Product Sheet C
```

A sheet presents a product instance; it should not become the authoritative owner of the engineering parameter state.

This separation is important for Excel import, product duplication, future multi-view sheets, and revision workflows.


The exact schema must follow existing project naming conventions, but the conceptual model should be:

```json
{
  "ddsVersion": 1,
  "document": {
    "title": "...",
    "orderInfo": {
      "orderNumber": "...",
      "orderDate": "...",
      "sourceType": "excel",
      "sourceFileName": "Customer_Order.xlsx"
    },
    "documentNumber": "...",
    "revision": "...",
    "issueDate": "...",
    "status": "For Approval",
    "project": "...",
    "client": "...",
    "consultant": "...",
    "contractor": "...",
    "preparedBy": "...",
    "checkedBy": "...",
    "approvedBy": "...",
    "notes": "..."
  },
  "sheets": [
    {
      "sheetId": "...",
      "productInstanceId": "product_instance_001",
      "orderLine": {
        "orderNumber": "...",
        "lineNumber": "001",
        "customerItemReference": "...",
        "quantity": 12,
        "customerDescription": "...",
        "remarks": "..."
      },
      "templateId": "trunking_equal_tee",
      "templateVersion": "...",
      "templateFingerprint": "...",
      "productName": "...",
      "instanceParameters": { },
      "coverState": { },
      "annotations": [ ],
      "drawings": [ ],
      "viewState": { },
      "sheetLayout": { }
    }
  ]
}
```

The exact field names are illustrative only.

### Important

The DDS must store **the complete resolved instance parameter set required to reproduce the product**, not only values that happen to differ from the template default.

The DDS should therefore behave as a reproducible product-instance snapshot:

```text
DSF template version
        +
Complete DDS instance parameters
        ↓
Same product configuration regenerated
```

The DDS must not rely on current template defaults to reconstruct omitted values for an existing instance.

---

## 7. Template Versioning and Integrity

Add explicit template-version information to every DDS product instance.

Recommended fields:

```text
 templateId
 templateVersion
 templateFingerprint / hash
```

Reason:

A client-approved DDS created today should remain reproducible even if a future application release contains an updated version of the same product template.

Recommended opening behavior:

```text
DDS references template version X
        ↓
Template library lookup
        |
        +-- exact version found → load normally
        |
        +-- newer/different version only → warn about template mismatch
        |
        +-- template missing → show unresolved-template state
```

Do not silently substitute a different product template.

If the application later introduces explicit template migration, that should be a deliberate user action that creates a new DDS revision rather than changing the original silently.

---

## 8. Parameter Snapshot Model

The DDS should store everything the user is allowed to edit from the parameter interface.

Examples:

```text
Basic dimensions
- Width
- Height
- Branch widths
- Branch heights
- Lengths
- Radii where exposed

Sheet-metal geometry parameters
- Flange dimensions
- Bend-related editable parameters
- Bend direction where user-editable
- Allowances where user-editable

Features
- Coupler-hole options
- Hole spacing/offset parameters
- Punch/slot parameters where exposed

Cover
- Cover presence
- Cover-linked dimensions
- Cover-specific overrides if later introduced
- Cover placement state

Product data
- Product code
- Description
- Material
- Thickness
- Finish/coating
- Notes
```

Do not store derived geometry values as the primary source when those values can be regenerated from the template and parameters.

Derived geometry should be regenerated by the engine.

---

## 9. Covers in DDS

The current trunking cover architecture must integrate naturally with DDS.

The cover is part of the product instance, but cover geometry is generated parametrically from the main product dimensions.

Therefore the preferred DDS representation is:

```text
DDS
|
+-- Base instance parameters
|
+-- Cover enabled = true
|
+-- Cover-specific parameters/overrides where applicable
|
+-- Cover placement/visibility state
```

The application then performs:

```text
DDS base parameters
        ↓
Base template scaling
        ↓
Cover generator/scaler
        ↓
Base + Cover 2D
        ↓
Base + Cover 3D
```

The DDS should not need to store an independently edited copy of the cover flat geometry unless the user is explicitly given a future freeform/custom-cover editing workflow.

For the first implementation, cover dimensions that are mathematically derived from the base should appear as **Derived / read-only** values in the parameter table. Only cover parameters explicitly declared editable by the product contract should be user-editable.

---

## 10. Reopening a DDS

The opening workflow should be deterministic:

```text
Open .dds
   ↓
Read document metadata
   ↓
Enumerate product sheets
   ↓
For each sheet:
   Find templateId
   Verify templateVersion/fingerprint
   Load DSF template
   Apply instanceParameters
   Generate dependent cover
   Regenerate 3D
   Restore annotations
   Restore sheet presentation
   ↓
Open TDS workspace
```

The user should see the same product state that was previously saved.

---

## 11. DDS Authoring UI

The current CAD UI should gain a dedicated **Technical Data Sheet workspace** while retaining the existing geometry engine.

Recommended top-level tabs:

```text
[Product] [Technical Data Sheet] [2D Drawing] [3D View] [Export]
```

The exact navigation can be adapted to the application's existing UI patterns.

### Recommended TDS workspace

```text
+---------------------------------------------------------------+
| DDS: Project Technical Data Sheet       Rev 01   FOR APPROVAL |
+----------------------+----------------------------------------+
| SHEET / PRODUCTS     |                                        |
|                      |      3D / Isometric View               |
| > Cover Page         |                                        |
| > 90° Bend           |                                        |
| > 45° Bend           |                                        |
| > Equal Tee          |      [interactive 3D]                  |
| > Unequal Tee        |                                        |
| > Reducer            |                                        |
|                      |----------------------------------------|
| [+ Add Product]      |      2D Technical Drawing               |
|                      |                                        |
+----------------------+----------------------------------------+
| Parameter Table / Properties / Annotations / Revision        |
+---------------------------------------------------------------+
```

The UI should remain understandable to a normal technical-office user, not resemble a full CAD authoring workstation.

---

## 12. Parameter Table

Provide a dedicated table for editing product dimensions.

Example:

| Parameter | Value | Unit | Source |
|---|---:|---|---|
| Width W | 150 | mm | DDS |
| Height H | 100 | mm | DDS |
| Branch Width | 100 | mm | DDS |
| Branch Height | 75 | mm | DDS |
| Thickness | 1.2 | mm | Template/DDS |
| Cover | Yes | — | DDS |

### Behavior

Changing a value must immediately:

```text
Edit parameter
    ↓
Validate
    ↓
Write value into DDS instance state
    ↓
Regenerate 2D
    ↓
Regenerate cover
    ↓
Regenerate 3D
    ↓
Update dimension annotations/tables
```

### Important

The parameter table must clearly distinguish:

```text
Template-defined / read-only
DDS instance value / editable
Derived value / calculated
```

This prevents users from thinking they are editing the master product template.

---

## 13. Annotation and Basic Drawing System

The DDS must support basic technical-document annotation without becoming a full CAD drawing package.

### Required first-pass tools

```text
Text
Text box / note box
Leader arrow
Line
Polyline
Rectangle
Circle
Arc
Dimension annotation
Reference/callout label
Symbol placeholder
Revision cloud or simple change marker if practical
```

### Annotation properties

Each annotation should have:

```text
id
position
rotation
text/style
layer or category
visibility
linked entity/feature where applicable
```

Annotations belong to the DDS, not the master template, unless they are explicitly part of a product template definition.

---

## 14. Intelligent Dimension Annotations

Use the existing dimension/constraint architecture where possible.

A dimension displayed on a DDS should preferably be linked to actual geometry or a parameter rather than being manually typed text.

Example:

```text
Parameter W = 150
        ↓
Geometry width = 150
        ↓
Dimension annotation displays 150 mm
```

If the user changes W to 200:

```text
W = 200
        ↓
Geometry updates
        ↓
Dimension automatically displays 200 mm
```

This is particularly important for client approval drawings because the printed dimension must always correspond to the actual regenerated model.

---

### 14.1 Linked vs Graphic Annotations

DDS annotations should be classified into two groups.

### Model-linked annotations

These are attached to product parameters or persistent geometry/feature IDs and update when the product instance changes.

Examples:

```text
Port width dimension
Port height dimension
Overall length dimension
Hole-to-edge dimension
Port label
Feature callout
```

### Graphic annotations

These are document markup independent of model regeneration.

Examples:

```text
Line
Rectangle
Circle
Free reference sketch
Text box
General note
Revision cloud
```

Graphic annotations should remain where the user placed them unless they are explicitly attached to model geometry.

This separation prevents regeneration from destroying office/client markup.

---

### 14.2 Order / Product Schedule

When a DDS is created from an Excel order list, the document should automatically create a visible **Order / Product Schedule** as part of the initial document structure.

Recommended information:

| Sheet | Order Line | Customer Item | Product | Configuration | Qty | Status |
|---:|---|---|---|---|---:|---|
| 02 | 001 | TR-001 | Equal Tee | 100 × 100 | 12 | Resolved |
| 03 | 002 | TR-002 | 90° Bend | 150 × 100 | 8 | Resolved |
| 04 | 003 | TR-003 | Reducer | 150/75 | 4 | Resolved |
| 05 | 004 | TR-004 | Unequal Tee | Custom | 6 | Review |

This schedule can appear on the **DDS cover/index sheet** and should remain linked to the underlying product instances.

The schedule is not intended to replace the detailed technical sheet. It is the client's/contractor's quick index of the products included in the technical submittal.

The schedule should update when:

```text
Product instance added/removed
Order line/reference changed
Product name changed
Sheet number changed
Quantity changed
Resolution status changed
```

Do not make the schedule a manually duplicated text table. It should be generated from DDS document data.

---

## 15. Basic TDS Sheet Layout

The exported/client-facing sheet should have a professional structure inspired by established manufacturer technical sheets.

### Recommended single-product sheet

```text
┌───────────────────────────────────────────────────────────────┐
│ COMPANY LOGO / DOCUMENT TITLE                                 │
│ TECHNICAL DATA SHEET                                          │
├───────────────────────────────────────────────────────────────┤
│ Product Name / Product Code / Description                     │
├──────────────────────────────┬────────────────────────────────┤
│                              │                                │
│   2D DIMENSIONED DRAWING     │      3D ISOMETRIC VIEW         │
│                              │                                │
│   with key dimensions        │      base + cover              │
│                              │                                │
├──────────────────────────────┴────────────────────────────────┤
│ TECHNICAL PARAMETERS                                          │
│                                                              │
│ W | H | branch dimensions | thickness | material | coating   │
├───────────────────────────────────────────────────────────────┤
│ PRODUCT / APPLICATION NOTES                                  │
├───────────────────────────────────────────────────────────────┤
│ GENERAL NOTES / REFERENCES / STANDARDS                       │
├───────────────────────────────────────────────────────────────┤
│ REVISION HISTORY                                              │
├───────────────────────────────────────────────────────────────┤
│ PREPARED | CHECKED | APPROVED | DATE | REV | SHEET           │
└───────────────────────────────────────────────────────────────┘
```

This is a recommended TruFold layout, not a reproduction of any one manufacturer's format.

---

## 16. Cover Page

For multi-product DDS files, generate a dedicated cover page.

Recommended content:

```text
Company logo/name
TECHNICAL DATA SHEET

Project
Client
Consultant
Contractor
Project/Package reference
DDS document number
Revision
Issue date
Document status
Prepared by
Checked by
Approved by

Product contents / index
```

The cover page should include the product-sheet list and sheet count.

---

## 17. Client Approval-Oriented Document Control

Because the DDS will be sent to clients for review and approval, include document-control information as a first-class feature.

Recommended fields:

```text
Document No.
Revision
Date
Status
Project
Client
Consultant
Contractor
Prepared By
Checked By
Approved By
Sheet No.
Total Sheets
```

Include a revision history table:

| Rev | Date | Description | Prepared | Checked | Approved |
|---|---|---|---|---|---|
| 00 | — | Initial issue | — | — | — |
| 01 | — | Client comments incorporated | — | — | — |

Use configurable approval/status wording rather than hard-coding one company's approval vocabulary.

---

## 18. Product Sheet Information Architecture

Each product sheet should support these content groups.

### A. Identification

```text
Product category
Product type
Variant
Product code
Description
Drawing number
```

### B. Dimensional data

```text
Width
Height
Length
Branch sizes
Radii
Angles
Flange sizes
Port sizes
```

Only display fields relevant to the selected product.

### C. Sheet-metal data

```text
Material
Thickness
Finish/coating
Bend information where useful
```

### D. Cover data

```text
Cover supplied: Yes/No
Cover dimensions
Cover flange information
Cover-specific notes
```

### E. Feature data

```text
Coupler holes
Punches
Slots
Feature counts
Relevant feature dimensions
```

### F. Notes

Free-form user-authored technical notes.

---

## 19. Isometric View Strategy

The 3D isometric view should be a central visual element of the client TDS.

Recommended default:

```text
Base + Cover

Isometric camera
Clean background
Consistent line/material presentation
No unnecessary UI controls
```

The view should show the relationship between the main accessory and cover clearly.

For approval drawings, the preferred presentation should be a **clean technical isometric**, rather than a heavily shaded videogame-like rendering.

The user should still be able to interactively orbit/zoom during document preparation.

---

## 20. 2D Technical Drawing Strategy

The 2D drawing should present the actual regenerated product geometry from the DDS parameters.

Recommended views may include:

```text
Top / plan view
Front/end view
Side view
Section/profile view where useful
Flat pattern view when manufacturing information is intended
```

Do not automatically display every possible view.

The system should select or allow the user to select useful views depending on the product type.

---

## 21. Base + Cover Presentation

For products with covers, support at least two meaningful presentation modes.

### Mode A — Separate explanatory view

```text
Base drawing                 Cover drawing
     [BASE]                     [COVER]
```

Useful when showing how the cover is manufactured.

### Mode B — Installed/isometric view

```text
        COVER
      ┌────────┐
      │        │
      └────────┘
       BASE BODY
```

Useful for showing the final assembled product.

The same product instance should feed both views.

---

## 22. Unequal Product Presentation

For unequal Tee/Cross products, the DDS should show the actual stored dimensions for each branch.

Example table:

| Port | Width | Height |
|---|---:|---:|
| P1 | 100 | 100 |
| P2 | 50 | 75 |
| P3 | 100 | 75 |

For products where body height is derived, the table may also show:

```text
Body Height = max(P1, P2, P3)
```

and the generated cover should visibly match the regenerated unequal geometry.

---

## 23. DDS Editing vs Template Editing

This distinction must be obvious in the UI.

### DDS editing

```text
Edit Product Instance
```

Changes are stored in the DDS.

### Template editing

```text
CMS Template Authoring
```

Changes the master template library and should remain a separate workflow.

A user editing a DDS must never accidentally modify the embedded/application template.

---

## 24. Adding a Product to an Existing DDS

Provide:

```text
+ Add Product
```

Workflow:

```text
Add Product
    ↓
Choose Category
    ↓
Choose Product Type
    ↓
Choose Template / Variant
    ↓
Initial parameters loaded
    ↓
Product inserted into DDS
```

The new product becomes another independent DDS instance.

---

## 25. DDS Product Duplication

Provide an efficient way to create size variants without rebuilding sheets.

Example:

```text
Duplicate Product
      ↓
New product instance
      ↓
Change W/H/etc.
      ↓
New sheet generated
```

This will be especially useful when a client requests several size variants during approval.

Duplicating a sheet must duplicate the **instance parameters and document presentation**, not the master template.

---

## 26. Template Discovery / Missing Template Handling

When a DDS is opened, template lookup must be explicit.

Possible states:

```text
FOUND
  → normal operation

FOUND BUT VERSION MISMATCH
  → warning + controlled recovery

NOT FOUND
  → unresolved template state
```

For a missing template, do not silently replace it with a visually similar product.

The document should explain which product/template is unavailable.

---

## 27. Save Behavior

DDS becomes the primary writable document when the user is working in TDS mode.

Recommended commands:

```text
Ctrl + S
    → save DDS

Save As DDS
    → create new DDS

Export PDF
    → generate client-facing TDS PDF

Export DXF
    → export selected physical drawing geometry
```

Changing DDS values must never write those values back into the CMS template.

---

## 28. Export PDF — Client Deliverable

The primary client-facing output should be a professionally formatted PDF generated from the DDS.

Recommended export:

```text
DDS
 ↓
TDS PDF
```

The PDF must contain the exact product state represented in the DDS at export time.

### PDF should include

- company identity/branding,
- project/document information,
- product title/reference,
- 3D isometric drawing,
- dimensioned technical views,
- technical parameter table,
- notes,
- revision history,
- page/sheet numbers,
- document status,
- approval area where applicable.

---

## 29. Export Layout Modes

Provide at least:

```text
Single Product Sheet
Full DDS Package
Selected Sheets
```

And optionally:

```text
A4
A3
Auto orientation
```

Sheet size/orientation should be controlled independently from the model geometry.

---

## 30. Approval Workflow Consideration

The DDS itself should remain the editable engineering document.

The exported PDF represents an issued/review version.

Recommended lifecycle:

```text
Draft DDS
   ↓
Internal Review
   ↓
Issue PDF
   ↓
Client Comments
   ↓
Modify DDS
   ↓
Increment Revision
   ↓
Re-export PDF
```

Do not overwrite an issued revision silently.

The DDS should allow revision metadata to be updated deliberately.

---

## 31. Revision and Comment Preservation

Future-friendly design should allow a revision to carry:

```text
Revision number
Revision date
Description of change
Author
Checker
Approver
Client comment reference
```

Consider storing client-comment references in the DDS later so an approval package can document why dimensions changed.

Do not implement a full document-management system in the first pass.

---

## 32. Basic Drawing Layer System

Separate generated technical geometry from user annotation.

Recommended conceptual layers:

```text
MODEL_2D
DIMENSIONS
CENTERLINES
ANNOTATIONS
NOTES
CONSTRUCTION
COVER
BASE
APPROVAL_MARKUP
```

Generated geometry should remain distinguishable from user-authored annotations.

---

## 33. Prevent Annotation Loss During Regeneration

Changing a parameter must regenerate product geometry without destroying unrelated DDS annotations.

Example:

```text
User places note:
"CLIENT TO CONFIRM FINISH"

User changes Width 150 → 200

Expected:
Geometry updates
Dimension updates
3D updates
Note remains exactly where the DDS layout expects it
```

Where an annotation is linked to a geometry feature, use a persistent feature ID/reference rather than screen coordinates alone.

---

## 34. Presentation View State

The DDS should store the presentation state necessary to reopen the document as expected.

Examples:

```text
2D zoom
2D pan
2D visibility
3D camera
3D visibility
Base/cover display mode
Selected sheet
Active parameter section
```

Camera state should be optional; geometric/product state is more important than UI state.

---

## 35. 3D Cover Viewer

The previously planned detachable cover viewer should integrate with DDS rather than create a new model state.

```text
DDS product instance
       ↓
Shared base + cover model
       ├── Main 3D viewport
       └── Detachable cover/assembly viewport
```

Closing the detached viewer must not affect the DDS product state.

---

## 36. Recommended TDS Visual Hierarchy

The final client document should prioritize information in this order:

```text
1. Product identity
2. What the product looks like
3. Main dimensions
4. Complete technical parameter table
5. Cover/base relationship
6. Manufacturing/technical notes
7. Document control / revision / approval
```

Do not overcrowd the page with every internal CMS parameter.

The parameter table should display **technical information useful to the client**, while the DDS still retains all necessary engine parameters internally.

---

## 37. Internal vs Client-Facing Parameters

This is an important separation.

### Internal engine data

May include:

```text
bend IDs
face IDs
feature IDs
topology IDs
constraint relationships
scaling coefficients
internal offsets
algorithmic metadata
```

### Client-facing data

Should include only meaningful engineering/product information:

```text
W
H
branch dimensions
thickness
material
finish
angle
radius
cover dimensions
port dimensions
key hole/punch dimensions
```

The DDS can contain the full internal state while the PDF generator selects only appropriate presentation fields.

---

## 38. Parameter Table Configuration

The system should allow product-specific parameter visibility.

For example:

```text
90° Bend
  Angle = 90°
  Width
  Height
  Radius

Unequal Tee
  P1 Width
  P1 Height
  P2 Width
  P2 Height
  P3 Width
  P3 Height
  Body Height (derived)
```

Do not show irrelevant parameters simply because they exist internally.

---

## 39. Recommended First Implementation Scope

The first implementation should focus on the complete core pipeline:

```text
Template resolution
      ↓
DDS parameter snapshot
      ↓
Parameter table
      ↓
Base regeneration
      ↓
Cover regeneration
      ↓
2D presentation
      ↓
3D isometric presentation
      ↓
Annotations
      ↓
DDS save/reopen
      ↓
PDF TDS export
```

Do not attempt advanced PDM/document-management functions in this sprint.

---

## 40. Suggested Implementation Order

### Phase 1 — DDS core data model

- `.dds` file schema.
- Document metadata.
- Product-instance collection.
- Product-sheet collection.
- Template ID/version/fingerprint.
- Complete instance parameter storage.
- Order/import metadata structures.
- Basic presentation state.

### Phase 1A — Excel order/product-list import foundation

- Excel (`.xlsx`) reader abstraction.
- Worksheet and row preview.
- Column mapping UI.
- Product/template matching.
- Unresolved-item handling.
- Order-line source metadata.
- Product-instance creation.
- Automatic initial Order/Product Schedule and Sheet Navigator population.

### Phase 2 — Template resolver

- Find template in library.
- Validate version/fingerprint.
- Apply stored values.
- Handle missing/mismatched templates.

### Phase 3 — Product instance regeneration

- Existing base scaler.
- Existing cover generator/scaler.
- 2D regeneration.
- 3D regeneration.

### Phase 4 — DDS parameter table

- Product-specific fields.
- Editable values.
- Read-only/derived indicators.
- Immediate regeneration.

### Phase 5 — TDS drawing canvas

- Sheet/page layout.
- 2D views.
- 3D isometric viewport.
- Dimension annotations.
- Basic drawing tools.
- Text and notes.

### Phase 6 — Multi-sheet DDS

- Add/remove/duplicate/reorder sheets.
- Product index.
- Cover page.

### Phase 7 — Client PDF export

- Professional template.
- Title block.
- Revision history.
- Approval block.
- Page numbering.
- Consistent isometric/2D presentation.

### Phase 8 — Advanced presentation

- Detached 3D windows.
- Additional view presets.
- Approval markup/comment references.
- More advanced drawing symbols.

---

## 41. Validation Plan

### A. Template isolation

Change a DDS parameter.

Expected:

```text
DDS changes
Template does not change
```

### B. Save/reopen

```text
Open template
Change parameters
Save DDS
Close
Reopen DDS
```

Expected:

```text
Exactly the same parameter state
Exactly the same regenerated geometry
```

### C. Scaling reversibility

```text
100 → 150 → 200 → 150 → 100
```

Final geometry must return to baseline.

### D. Cover synchronization

```text
Change base dimension
        ↓
Cover updates
```

No manual cover redraw should be required.

### E. Annotation persistence

```text
Place note
Change dimensions
Save
Reopen
```

Expected:

```text
Note remains
```

### F. Multi-sheet persistence

Add several product sheets, save DDS, reopen.

All sheets must resolve their correct templates and parameter states.

### G. Template mismatch

Test an intentionally incompatible/missing template.

Expected:

```text
Clear warning
No silent substitution
No destructive modification
```

### H. PDF fidelity

Verify that PDF dimensions, parameter tables, 2D views and 3D views correspond to the DDS state that was exported.

### I. Revision control

Create Rev 00, then make a controlled change and issue Rev 01.

Verify the revision information appears consistently throughout the exported package.

### J. Excel import

Verify:

```text
Excel workbook
    ↓
Preview rows
    ↓
Map columns
    ↓
Resolve CMS templates
    ↓
Create DDS
    ↓
Order/Product Schedule populated
    ↓
Product instances + sheets created
```

Also verify:

- Quantity is stored as order metadata and does not duplicate geometry.
- Customer references remain traceable to the imported order line.
- Unresolved items remain visible until reviewed.
- The DDS opens correctly without the original Excel workbook.
- A manually created DDS remains fully supported.

---

## 42. Professional TDS Style Direction

Use a clean engineering-document aesthetic rather than a marketing brochure aesthetic.

Recommended characteristics:

```text
White/light technical drawing background
Clear black/grey engineering linework
One restrained brand accent colour
Strong product title hierarchy
Consistent dimension styling
Consistent tables
Minimal decorative graphics
High-quality isometric views
Large readable product identification
Clean title block
Clear revision/status information
```

The visual goal is:

> **A professional engineering submittal that looks credible when printed, PDF'd, reviewed, stamped and returned by a consultant/client.**

---

## 43. Recommended Sheet Templates

Initially create three reusable page templates.

### Template A — Cover Sheet

```text
Company / project information
DDS title
Document number
Revision
Status
Product index
Approval information
```

### Template B — Standard Product Sheet

```text
Product identity
3D isometric
2D technical drawing
Parameter table
Notes
Revision/title block
```

### Template C — Complex Product Sheet

For unequal Tee/Cross, reducers, risers and other products needing additional information:

```text
Product identity
Large 3D isometric
Primary dimensioned views
Port/branch table
Cover information
Technical notes
Revision/title block
```

---

## 44. Client Approval Presentation

The PDF issued to the client should make the intended review task obvious.

The client should be able to answer quickly:

```text
What product is this?
What are its dimensions?
What are the branch/port sizes?
What does it look like in 3D?
Does it include a cover?
How does the cover fit?
What material/thickness/finish is proposed?
What document revision am I reviewing?
Where do I record approval/comments?
```

This is more important than exposing the application's internal CAD complexity.

---

## 45. Suggested Future Extensions

Do not implement these unless required after the core DDS pipeline is stable, but structure the schema so they can be added later:

```text
BOM / parts list
Material weight
Surface area
Estimated sheet size
Manufacturing time
Coating information
Costing
QR code / document verification
Digital approval/signature
Client comment tracking
Revision comparison
PDF stamping
Automatic product catalogue generation
```

A future DDS revision may therefore evolve from a technical drawing package into a complete product technical-submittal package.

---

## 46. Important Architectural Rules

1. **DSF template is the immutable base.**
2. **DDS stores the product-instance parameter state.**
3. **DDS edits never modify the application template.**
4. **Geometry is regenerated from template + DDS parameters.**
5. **Covers are derived from the current base instance parameters.**
6. **Annotations are DDS/document data, not template data unless explicitly defined as template annotations.**
7. **Client-facing tables show meaningful engineering parameters, not internal engine data.**
8. **Template version/fingerprint must be stored so an approved DDS can be reproduced reliably.**
9. **Excel import creates DDS product instances and order metadata; the DDS must not remain dependent on the source workbook.**
10. **A PDF export is a rendered issued document; it is not the editable DDS source.**
11. **The existing CAD/scaling engines remain the geometry authorities; DDS is the document/instance authority.**

---
## 47. End-to-End Architecture

```text
                 APP TEMPLATE LIBRARY
                         │
                         │ DSF Template
                         ▼
                  TEMPLATE RESOLVER
                         │
       ┌─────────────────┴─────────────────┐
       ▼                                   ▼
  Manual DDS Setup                  Excel Order Import
       │                                   │
       └─────────────────┬─────────────────┘
                         ▼
                 PRODUCT INSTANCE
                         │
           ┌─────────────┼─────────────┐
           ▼             ▼             ▼
       BASE 2D       COVER 2D       3D MODEL
           │             │             │
           └─────────────┼─────────────┘
                         ▼
                 DDS DOCUMENT MODEL
                         │
       ┌─────────────────┼──────────────────┐
       ▼                 ▼                  ▼
    PRODUCT          ORDER / PRODUCT    SHEET LAYOUT
   INSTANCES            SCHEDULE             │
       │                                      │
       └─────────────────┬────────────────────┘
                         ▼
                    PARAMETERS +
                    ANNOTATIONS
          │              │              │
          └──────────────┼──────────────┘
                         ▼
                 TECHNICAL SHEET UI
                         │
             ┌───────────┴───────────┐
             ▼                       ▼
         Save .DDS               Export PDF
                                     │
                                     ▼
                          CLIENT TDS / APPROVAL
```

---

## 48. Final Agent Instruction

Do not redesign the existing CMS template/scaling engines merely to create DDS.

The DDS should sit above them as the **product-instance and technical-document layer**.

The intended relationship is:

```text
MASTER TEMPLATE
    = what the product is and how it is constructed

DDS INSTANCE
    = how this particular product is currently sized/configured

TDS PDF
    = how that DDS instance is presented to the client
```

The application should make the entire process feel simple:

```text
Select product/template OR import Excel order
       ↓
Create product instances + Order/Product Schedule
       ↓
Edit dimensions in table
       ↓
2D + cover + 3D update live
       ↓
Add notes/dimensions
       ↓
Arrange technical sheet
       ↓
Save .dds
       ↓
Export professional PDF
       ↓
Send to client for review/approval
```

The key objective is to make TruFold Studio evolve from a **CMS drawing/scaling application into a product technical-documentation system**, while preserving the reliable template-driven geometry architecture already established.
