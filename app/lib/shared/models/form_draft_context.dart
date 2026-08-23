/// Lifecycle mode for a retained form draft.
enum FormDraftMode { create, edit, action }

/// Stable identity for one form draft within an authenticated app session.
///
/// Callers should provide only identities that define their form context. For
/// example, an edit form uses [entityId], while a product action may use
/// [productId] and [optionId]. [variantId] covers normalized values such as a
/// price variant that further partitions an otherwise identical context.
class FormDraftContext {
  const FormDraftContext({
    required this.formType,
    required this.mode,
    this.entityId,
    this.productId,
    this.optionId,
    this.variantId,
  }) : assert(formType != '');

  final String formType;
  final FormDraftMode mode;
  final String? entityId;
  final String? productId;
  final String? optionId;
  final String? variantId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FormDraftContext &&
          other.formType == formType &&
          other.mode == mode &&
          other.entityId == entityId &&
          other.productId == productId &&
          other.optionId == optionId &&
          other.variantId == variantId;

  @override
  int get hashCode =>
      Object.hash(formType, mode, entityId, productId, optionId, variantId);

  @override
  String toString() =>
      'FormDraftContext('
      'formType: $formType, '
      'mode: $mode, '
      'entityId: $entityId, '
      'productId: $productId, '
      'optionId: $optionId, '
      'variantId: $variantId)';
}
