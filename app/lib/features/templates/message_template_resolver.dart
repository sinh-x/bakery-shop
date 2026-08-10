import '../../data/models/message_template.dart';
import '../../shared/labels/templates.dart';
import 'template_context.dart';

/// Placeholder resolver for [MessageTemplate] bodies (DG-375 Phase 4.3 / FR4).
///
/// Resolves two kinds of placeholders:
/// 1. **Simple** — ``{field}`` → replaced with the field's display value from
///    [TemplateContext]. Empty values render as ``(trống)``.
/// 2. **Select** — ``{field, select: value1: text1 | value2: text2}`` →
///    evaluates the field's raw value and renders the matching branch's text.
///    Branch text may itself contain simple placeholders, which are resolved
///    recursively. An optional trailing ``| default: text`` (or a final
///    branch with no label) renders when no value matches.
/// 3. **If** — ``{field, if: prefix: {field}}`` → renders ``prefix`` + the
///    field value only when the field is non-empty; otherwise renders the
///    empty string.
///
/// The resolver operates on the raw template [body] stored verbatim by the
/// backend (Phase 1). It is pure and has no side effects, making it safe to
/// test in isolation.
class MessageTemplateResolver {
  MessageTemplateResolver(this.context);
  final TemplateContext context;

  /// The string used in place of an empty field value for simple
  /// substitutions. Matches the requirements doc §11 Risk mitigation.
  /// Centralized in [TemplatesLabels.emptyFieldPlaceholder] (NFR4).
  static const emptyPlaceholder = TemplatesLabels.emptyFieldPlaceholder;

  /// Resolves all placeholders in [template.body] using [context].
  String resolvePlaceholders(MessageTemplate template) {
    return _resolveBody(template.body);
  }

  /// Resolves all placeholders in a raw template body string.
  String resolveBody(String body) => _resolveBody(body);

  String _resolveBody(String body) {
    var result = body;
    // Resolve conditional (select / if) placeholders first, because their
    // branch text may contain simple placeholders that the simple pass would
    // otherwise double-resolve. Loop until no conditional placeholders remain
    // (branch text may itself contain nested conditionals, though the seeded
    // templates do not nest them).
    for (var i = 0; i < 5; i++) {
      final next = _resolveConditionals(result);
      if (next == result) break;
      result = next;
    }
    // Then resolve any remaining simple placeholders (including those inside
    // previously-selected branch text).
    result = _resolveSimple(result);
    return result;
  }

  /// Resolves ``{field, select: ...}`` and ``{field, if: ...}`` placeholders.
  String _resolveConditionals(String body) {
    var result = body;
    // select: {field, select: v1: t1 | v2: t2 | default: t3}
    result = _resolveSelect(result);
    // if: {field, if: prefix: {field}}
    result = _resolveIf(result);
    return result;
  }

  final _selectRegex = RegExp(
    r'\{([a-z_]+),\s*select:\s*([^{}]+(?:\{[^{}]*\}[^{}]*)*)\}',
  );

  String _resolveSelect(String body) {
    return body.replaceAllMapped(_selectRegex, (match) {
      final field = match.group(1)!;
      final branchesText = match.group(2)!;
      final rawValue = context.rawValueFor(field);
      final branches = _parseSelectBranches(branchesText);
      if (branches.isEmpty) return '';
      // Find a branch whose label matches the raw value (case-insensitive,
      // trimmed). Fall back to the `default` branch or the last branch.
      var selected = branches.lastWhere(
        (b) => b.isDefault,
        orElse: () => branches.last,
      );
      for (final b in branches) {
        if (!b.isDefault && b.label.trim().toLowerCase() == rawValue.trim().toLowerCase()) {
          selected = b;
          break;
        }
      }
      return selected.text;
    });
  }

  final _ifRegex = RegExp(
    r'\{([a-z_]+),\s*if:\s*([^{}]*):\s*\{([a-z_]+)\}\}',
  );

  String _resolveIf(String body) {
    return body.replaceAllMapped(_ifRegex, (match) {
      final field = match.group(1)!;
      final prefix = match.group(2)!;
      final value = context.valueFor(field);
      if (value.trim().isEmpty) return '';
      return '$prefix: $value';
    });
  }

  /// Parses the inside of a select placeholder into a list of branches.
  ///
  /// Branch syntax: ``value: text`` separated by ``|``. A branch labelled
  /// ``default`` (or the last branch when no label is present) is the
  /// fallback. Branch text may contain simple placeholders (``{field}``).
  List<_SelectBranch> _parseSelectBranches(String text) {
    final branches = <_SelectBranch>[];
    // Split on top-level `|` (not inside nested braces).
    final parts = _splitOnPipe(text);
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final colon = _findBranchColon(trimmed);
      if (colon == -1) {
        // No label — treat as default text.
        branches.add(_SelectBranch(label: '', text: trimmed, isDefault: true));
        continue;
      }
      final label = trimmed.substring(0, colon).trim();
      final branchText = trimmed.substring(colon + 1).trim();
      final isDefault = label.toLowerCase() == 'default';
      branches.add(_SelectBranch(
        label: label,
        text: branchText,
        isDefault: isDefault,
      ));
    }
    return branches;
  }

  /// Splits a string on top-level ``|`` characters, ignoring pipes inside
  /// nested ``{...}`` placeholders.
  List<String> _splitOnPipe(String text) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        if (depth > 0) depth--;
      } else if (ch == '|' && depth == 0) {
        parts.add(text.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(text.substring(start));
    return parts;
  }

  /// Finds the index of the first ``:`` that separates a branch label from
  /// its text, skipping colons inside nested ``{...}``.
  int _findBranchColon(String text) {
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        if (depth > 0) depth--;
      } else if (ch == ':' && depth == 0) {
        return i;
      }
    }
    return -1;
  }

  final _simpleRegex = RegExp(r'\{([a-z_]+)\}');

  String _resolveSimple(String body) {
    return body.replaceAllMapped(_simpleRegex, (match) {
      final field = match.group(1)!;
      final value = context.valueFor(field);
      if (value.trim().isEmpty) return emptyPlaceholder;
      return value;
    });
  }
}

class _SelectBranch {
  const _SelectBranch({
    required this.label,
    required this.text,
    required this.isDefault,
  });
  final String label;
  final String text;
  final bool isDefault;
}

/// Convenience extension so callers can write
/// `template.resolvePlaceholders(context)`.
extension MessageTemplateResolverExt on MessageTemplate {
  /// Resolves all placeholders in this template's [body] using [context].
  String resolvePlaceholders(TemplateContext context) {
    return MessageTemplateResolver(context).resolveBody(body);
  }
}