import 'dart:math' as math;

// =============================================================================
// expression_parser_engine.dart
//
// Mathematical Expression & Formula Parser per Phase 1 Master Guide
// Section 24, 67 & Set 09.
//
// Supports:
// - Operators: +, -, *, /, unary -
// - Parentheses: ( )
// - Parameter identifier lookups: e.g. "WIDTH", "MAIN_WIDTH", "EDGE_OFFSET"
// - Number literals: integer & floating point
// - Examples:
//     "WIDTH / 2"
//     "MAIN_WIDTH / 2 - BRANCH_WIDTH / 2"
//     "LENGTH - 2 * EDGE_OFFSET"
// =============================================================================

class ExpressionEvaluationException implements Exception {
  final String message;
  const ExpressionEvaluationException(this.message);

  @override
  String toString() => 'ExpressionEvaluationException: $message';
}

class ExpressionParserEngine {
  /// Evaluates an expression string with provided parameter variable map.
  /// If [expression] is empty, returns [defaultValue].
  static double evaluate(
    String expression,
    Map<String, double> parameters, {
    double defaultValue = 0.0,
  }) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) return defaultValue;

    // Fast path: direct numeric literal
    final directNum = double.tryParse(trimmed);
    if (directNum != null) return directNum;

    // Fast path: direct parameter lookup (case-insensitive)
    for (final entry in parameters.entries) {
      if (entry.key.toLowerCase() == trimmed.toLowerCase()) {
        return entry.value;
      }
    }

    final tokens = _tokenize(trimmed);
    if (tokens.isEmpty) return defaultValue;

    final parser = _Parser(tokens, parameters);
    return parser.parseExpression();
  }

  /// Extracts all variable/parameter names referenced in an expression
  static Set<String> extractVariables(String expression) {
    const mathFunctions = {'floor', 'ceil', 'round', 'abs', 'sqrt', 'min', 'max'};
    final vars = <String>{};
    final tokens = _tokenize(expression);
    for (final token in tokens) {
      if (token.type == _TokenType.identifier) {
        if (!mathFunctions.contains(token.text.toLowerCase())) {
          vars.add(token.text);
        }
      }
    }
    return vars;
  }

  static List<_Token> _tokenize(String input) {
    final tokens = <_Token>[];
    int i = 0;
    while (i < input.length) {
      final char = input[i];

      // Whitespace
      if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        i++;
        continue;
      }

      // Operators & Parentheses
      if (char == '+') {
        tokens.add(const _Token(_TokenType.plus, '+'));
        i++;
      } else if (char == '-') {
        tokens.add(const _Token(_TokenType.minus, '-'));
        i++;
      } else if (char == '*') {
        tokens.add(const _Token(_TokenType.multiply, '*'));
        i++;
      } else if (char == '/') {
        tokens.add(const _Token(_TokenType.divide, '/'));
        i++;
      } else if (char == '(') {
        tokens.add(const _Token(_TokenType.openParen, '('));
        i++;
      } else if (char == ')') {
        tokens.add(const _Token(_TokenType.closeParen, ')'));
        i++;
      } else if (char == ',') {
        tokens.add(const _Token(_TokenType.comma, ','));
        i++;
      } else if (_isDigit(char) || (char == '.' && i + 1 < input.length && _isDigit(input[i + 1]))) {
        // Number literal
        final start = i;
        bool hasDot = char == '.';
        i++;
        while (i < input.length) {
          final c = input[i];
          if (_isDigit(c)) {
            i++;
          } else if (c == '.' && !hasDot) {
            hasDot = true;
            i++;
          } else {
            break;
          }
        }
        tokens.add(_Token(_TokenType.number, input.substring(start, i)));
      } else if (_isAlpha(char) || char == '_') {
        // Identifier / Variable Name
        final start = i;
        i++;
        while (i < input.length && (_isAlphaNum(input[i]) || input[i] == '_')) {
          i++;
        }
        tokens.add(_Token(_TokenType.identifier, input.substring(start, i)));
      } else {
        // Skip or advance unknown character
        i++;
      }
    }
    return tokens;
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  static bool _isAlpha(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
  }
  static bool _isAlphaNum(String c) => _isDigit(c) || _isAlpha(c);
}

enum _TokenType {
  number,
  identifier,
  plus,
  minus,
  multiply,
  divide,
  openParen,
  closeParen,
  comma,
}

class _Token {
  final _TokenType type;
  final String text;
  const _Token(this.type, this.text);

  @override
  String toString() => '$type("$text")';
}

class _Parser {
  final List<_Token> tokens;
  final Map<String, double> parameters;
  int _pos = 0;

  _Parser(this.tokens, this.parameters);

  _Token? get _current => _pos < tokens.length ? tokens[_pos] : null;

  double parseExpression() {
    return _parseAddSub();
  }

  double _parseAddSub() {
    var left = _parseMulDiv();

    while (_current != null &&
        (_current!.type == _TokenType.plus || _current!.type == _TokenType.minus)) {
      final op = _current!.type;
      _pos++;
      final right = _parseMulDiv();
      if (op == _TokenType.plus) {
        left += right;
      } else {
        left -= right;
      }
    }
    return left;
  }

  double _parseMulDiv() {
    var left = _parseUnary();

    while (_current != null &&
        (_current!.type == _TokenType.multiply || _current!.type == _TokenType.divide)) {
      final op = _current!.type;
      _pos++;
      final right = _parseUnary();
      if (op == _TokenType.multiply) {
        left *= right;
      } else {
        if (right.abs() < 1e-9) {
          throw const ExpressionEvaluationException('Division by zero in expression formula');
        }
        left /= right;
      }
    }
    return left;
  }

  double _parseUnary() {
    if (_current != null && _current!.type == _TokenType.minus) {
      _pos++;
      return -_parsePrimary();
    }
    if (_current != null && _current!.type == _TokenType.plus) {
      _pos++;
      return _parsePrimary();
    }
    return _parsePrimary();
  }

  double _parsePrimary() {
    final token = _current;
    if (token == null) {
      throw const ExpressionEvaluationException('Unexpected end of formula expression');
    }

    if (token.type == _TokenType.number) {
      _pos++;
      return double.tryParse(token.text) ?? 0.0;
    }

    if (token.type == _TokenType.identifier) {
      final name = token.text.toLowerCase();
      _pos++;

      // Check for function call: e.g. floor(...), ceil(...), min(a, b)
      if (_current != null && _current!.type == _TokenType.openParen) {
        _pos++; // consume '('
        final arg1 = _parseAddSub();

        if (name == 'min' || name == 'max') {
          if (_current == null || _current!.type != _TokenType.comma) {
            throw ExpressionEvaluationException('Function "$name" requires 2 arguments separated by a comma');
          }
          _pos++; // consume ','
          final arg2 = _parseAddSub();
          if (_current == null || _current!.type != _TokenType.closeParen) {
            throw const ExpressionEvaluationException('Expected ")" after function arguments');
          }
          _pos++; // consume ')'
          return name == 'min' ? math.min(arg1, arg2) : math.max(arg1, arg2);
        } else {
          if (_current == null || _current!.type != _TokenType.closeParen) {
            throw const ExpressionEvaluationException('Expected ")" after function argument');
          }
          _pos++; // consume ')'
          switch (name) {
            case 'floor':
              return arg1.floorToDouble();
            case 'ceil':
              return arg1.ceilToDouble();
            case 'round':
              return arg1.roundToDouble();
            case 'abs':
              return arg1.abs();
            case 'sqrt':
              if (arg1 < 0) throw const ExpressionEvaluationException('sqrt() of negative number');
              return math.sqrt(arg1);
            default:
              throw ExpressionEvaluationException('Unknown function "$name"');
          }
        }
      }

      // Case-insensitive lookup in parameters
      for (final entry in parameters.entries) {
        if (entry.key.toLowerCase() == name) {
          return entry.value;
        }
      }
      throw ExpressionEvaluationException('Unknown parameter variable "${token.text}"');
    }

    if (token.type == _TokenType.openParen) {
      _pos++;
      final val = _parseAddSub();
      if (_current == null || _current!.type != _TokenType.closeParen) {
        throw const ExpressionEvaluationException('Mismatched parentheses: expected ")"');
      }
      _pos++;
      return val;
    }

    throw ExpressionEvaluationException('Unexpected token "${token.text}" in formula expression');
  }
}
