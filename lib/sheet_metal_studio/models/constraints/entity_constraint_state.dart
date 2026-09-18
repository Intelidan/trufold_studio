// =============================================================================
// entity_constraint_state.dart
//
// Degrees of Freedom (DOF) visual diagnostic state for CAD sketch entities.
// Reflects Onshape CAD standard color coding:
// - underConstrained: CAD Blue (#0284C7) - entity has free degrees of freedom.
// - fullyConstrained: Slate Black (#0F172A) - position and size fully fixed/constrained.
// - overConstrained: Crimson Red (#EF4444) - contradictory/conflicting constraints.
// =============================================================================

import 'package:flutter/material.dart';

enum EntityConstraintState {
  underConstrained,
  fullyConstrained,
  overConstrained;

  Color get color {
    switch (this) {
      case EntityConstraintState.underConstrained:
        return const Color(0xFF0284C7); // Onshape CAD Blue
      case EntityConstraintState.fullyConstrained:
        return const Color(0xFF0F172A); // Slate Black
      case EntityConstraintState.overConstrained:
        return const Color(0xFFEF4444); // Conflict Red
    }
  }

  String get label {
    switch (this) {
      case EntityConstraintState.underConstrained:
        return 'Under-Constrained (Free to Move)';
      case EntityConstraintState.fullyConstrained:
        return 'Fully Constrained';
      case EntityConstraintState.overConstrained:
        return 'Over-Constrained / Conflict';
    }
  }
}
