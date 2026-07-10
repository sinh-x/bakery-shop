import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/order_draft.dart';
import 'package:bakery_app/shared/labels/orders.dart';

class RutTienEditor extends StatefulWidget {
  const RutTienEditor({
    super.key,
    required this.item,
    required this.onStateChanged,
  });

  final DraftOrderItem item;
  final VoidCallback onStateChanged;

  @override
  State<RutTienEditor> createState() => _RutTienEditorState();
}

class _RutTienEditorState extends State<RutTienEditor> {
  bool _rutTien = false;
  late TextEditingController _cashAmountCtrl;
  late TextEditingController _cashFeeCtrl;
  bool _editingCashAmount = false;

  static const int _defaultCashFee = 20000;
  static const int _cashFeeStep = 5000;
  static const int _cashAmountStep = 100000;
  static const int _minCashAmount = 100000;

  @override
  void initState() {
    super.initState();
    final savedCashFee = widget.item.attributes['cash_fee'];
    final savedCashAmount = widget.item.attributes['cash_amount'];
    _cashFeeCtrl = TextEditingController(
      text: (savedCashFee ?? '$_defaultCashFee').toString(),
    );
    _cashAmountCtrl = TextEditingController(
      text: (savedCashAmount ?? '').toString(),
    );
    _rutTien = widget.item.attributes['rut_tien']?.toString() == 'true';
  }

  @override
  void dispose() {
    _cashAmountCtrl.dispose();
    _cashFeeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.item.product.attributes['rut_tien']?.toString() != 'true') {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          value: _rutTien,
          onChanged: (v) {
            setState(() => _rutTien = v ?? false);
            if (_rutTien) {
              widget.item.attributes['rut_tien'] = 'true';
              widget.item.attributes['cash_fee'] = _cashFeeCtrl.text;
              widget.item.attributes['cash_amount'] = _cashAmountCtrl.text;
            } else {
              widget.item.attributes.remove('rut_tien');
              widget.item.attributes.remove('cash_fee');
              widget.item.attributes.remove('cash_amount');
              widget.item.daDuaTienRut = false;
            }
            widget.onStateChanged();
          },
          title: const Text(VN.rutTien),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (_rutTien) ...[
          Row(
            children: [
              const Text('${VN.soTienRut}: '),
              IconButton.filled(
                onPressed: () {
                  final current = int.tryParse(_cashAmountCtrl.text) ?? 0;
                  if (current > _minCashAmount) {
                    final next = current - _cashAmountStep;
                    final clamped =
                        next < _minCashAmount ? _minCashAmount : next;
                    setState(() {
                      _cashAmountCtrl.text = '$clamped';
                      _editingCashAmount = false;
                    });
                    widget.item.attributes['cash_amount'] = '$clamped';
                    widget.onStateChanged();
                  }
                },
                icon: const Icon(Icons.remove, size: 16),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _editingCashAmount = true),
                  child: _editingCashAmount
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: TextFormField(
                            controller: _cashAmountCtrl,
                            autofocus: true,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              isDense: true,
                              suffixText: 'đ',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(9),
                            ],
                            onChanged: (v) {
                              widget.item.attributes['cash_amount'] = v;
                              widget.onStateChanged();
                            },
                            onEditingComplete: () {
                              final val =
                                  int.tryParse(_cashAmountCtrl.text) ?? 0;
                              if (val < _minCashAmount && val != 0) {
                                _cashAmountCtrl.text = '$_minCashAmount';
                                widget.item.attributes['cash_amount'] =
                                    '$_minCashAmount';
                                widget.onStateChanged();
                              }
                              setState(() => _editingCashAmount = false);
                            },
                          ),
                        )
                      : Center(
                          child: Text(
                            _cashAmountCtrl.text.isEmpty ||
                                    _cashAmountCtrl.text == '0'
                                ? '0đ'
                                : formatVND(
                                    (int.tryParse(_cashAmountCtrl.text) ?? 0)
                                        .toDouble(),
                                  ),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                ),
              ),
              IconButton.filled(
                onPressed: () {
                  final current = int.tryParse(_cashAmountCtrl.text) ?? 0;
                  final next = current + _cashAmountStep;
                  final clamped =
                      next < _minCashAmount ? _minCashAmount : next;
                  setState(() {
                    _cashAmountCtrl.text = '$clamped';
                    _editingCashAmount = false;
                  });
                  widget.item.attributes['cash_amount'] = '$clamped';
                  widget.onStateChanged();
                },
                icon: const Icon(Icons.add, size: 16),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('${VN.phiRutTien}: '),
              IconButton.filled(
                onPressed: () {
                  final current =
                      int.tryParse(_cashFeeCtrl.text) ?? _defaultCashFee;
                  if (current >= _cashFeeStep) {
                    final next = current - _cashFeeStep;
                    setState(() => _cashFeeCtrl.text = '$next');
                    widget.item.attributes['cash_fee'] = '$next';
                    widget.onStateChanged();
                  }
                },
                icon: const Icon(Icons.remove, size: 16),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  (int.tryParse(_cashFeeCtrl.text) ?? _defaultCashFee) == 0
                      ? 'Miễn phí'
                      : formatVND(
                          (int.tryParse(_cashFeeCtrl.text) ?? _defaultCashFee)
                              .toDouble(),
                        ),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton.filled(
                onPressed: () {
                  final current =
                      int.tryParse(_cashFeeCtrl.text) ?? _defaultCashFee;
                  final next = current + _cashFeeStep;
                  setState(() => _cashFeeCtrl.text = '$next');
                  widget.item.attributes['cash_fee'] = '$next';
                  widget.onStateChanged();
                },
                icon: const Icon(Icons.add, size: 16),
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
