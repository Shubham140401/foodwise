import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/orders_dao.dart';
import '../services/csv_import_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _parser = CsvImportService();

  bool _swiggyLoading = false;
  bool _zomatoLoading = false;
  String? _swiggyResult;
  String? _zomatoResult;
  bool _swiggySuccess = false;
  bool _zomatoSuccess = false;

  Future<void> _import(String app) async {
    final isSwiggy = app == 'Swiggy';
    setState(() {
      if (isSwiggy) {
        _swiggyLoading = true;
        _swiggyResult = null;
      } else {
        _zomatoLoading = true;
        _zomatoResult = null;
      }
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        _setResult(isSwiggy, 'Cancelled.', false);
        return;
      }

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        _setResult(isSwiggy, 'Could not read file.', false);
        return;
      }

      final content = String.fromCharCodes(bytes);
      final orders = isSwiggy
          ? _parser.parseSwiggy(content)
          : _parser.parseZomato(content);

      if (orders.isEmpty) {
        _setResult(isSwiggy, 'No valid orders found in file.', false);
        return;
      }

      if (!mounted) return;
      final dao = context.read<OrdersDao>();
      final inserted = await dao.insertBatch(orders);
      final skipped = orders.length - inserted;

      final msg = inserted == 0
          ? 'All ${orders.length} orders already imported.'
          : skipped > 0
              ? 'Imported $inserted new orders. $skipped already existed.'
              : 'Imported $inserted orders successfully.';

      _setResult(isSwiggy, msg, inserted > 0 || skipped == orders.length);
    } catch (e) {
      _setResult(isSwiggy, 'Error: $e', false);
    }
  }

  void _setResult(bool isSwiggy, String msg, bool success) {
    if (!mounted) return;
    setState(() {
      if (isSwiggy) {
        _swiggyLoading = false;
        _swiggyResult = msg;
        _swiggySuccess = success;
      } else {
        _zomatoLoading = false;
        _zomatoResult = msg;
        _zomatoSuccess = success;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Import order history')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Import your order history from Swiggy and Zomato CSV exports. '
            'The app uses this data to learn your preferences, spot patterns, '
            'and make smarter recommendations — with or without an AI key.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          _howToExportTile(theme),
          const SizedBox(height: 24),
          _importCard(
            theme: theme,
            app: 'Swiggy',
            color: const Color(0xFFFC8019),
            icon: Icons.delivery_dining,
            loading: _swiggyLoading,
            result: _swiggyResult,
            success: _swiggySuccess,
          ),
          const SizedBox(height: 16),
          _importCard(
            theme: theme,
            app: 'Zomato',
            color: const Color(0xFFE23744),
            icon: Icons.restaurant,
            loading: _zomatoLoading,
            result: _zomatoResult,
            success: _zomatoSuccess,
          ),
          const SizedBox(height: 24),
          Text(
            'Your data stays on this device. Nothing is uploaded.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _importCard({
    required ThemeData theme,
    required String app,
    required Color color,
    required IconData icon,
    required bool loading,
    required String? result,
    required bool success,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Text(app,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: color, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            if (result != null) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: success
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      success ? Icons.check_circle_outline : Icons.info_outline,
                      size: 16,
                      color: success
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        result,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: success
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: color),
                onPressed: loading ? null : () => _import(app),
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.upload_file_outlined),
                label: Text(loading
                    ? 'Importing…'
                    : 'Select $app orders CSV'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _howToExportTile(ThemeData theme) {
    return ExpansionTile(
      leading: const Icon(Icons.help_outline),
      title: const Text('How to export your history'),
      childrenPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _exportStep(
          theme,
          'Swiggy',
          'Open swiggy.com in a browser → Account → My Account → '
              '"Download your data" → select Orders → submit. '
              'You\'ll receive a download link by email within 24 h.',
        ),
        const SizedBox(height: 10),
        _exportStep(
          theme,
          'Zomato',
          'Open zomato.com in a browser → Account → Privacy → '
              '"Download your data" → select Orders → submit. '
              'You\'ll receive a download link by email within 24–48 h.',
        ),
      ],
    );
  }

  Widget _exportStep(ThemeData theme, String app, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$app  ',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        Expanded(
          child: Text(text, style: theme.textTheme.bodySmall),
        ),
      ],
    );
  }
}
