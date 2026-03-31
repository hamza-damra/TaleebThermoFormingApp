import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../domain/entities/printer_config.dart';
import '../providers/printing_provider.dart';
import '../screens/printer_settings_screen.dart';

class PrinterSelectorDialog extends StatelessWidget {
  final VoidCallback? onPrinterSelected;

  const PrinterSelectorDialog({super.key, this.onPrinterSelected});

  @override
  Widget build(BuildContext context) {
    return Consumer<PrintingProvider>(
      builder: (context, provider, _) {
        return AlertDialog(
          title: Text(
            'اختر الطابعة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: provider.printers.isEmpty
                ? _buildNoPrintersContent(context)
                : _buildPrintersList(context, provider),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PrinterSettingsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.settings, size: 18),
              label: Text('الإعدادات', style: GoogleFonts.cairo()),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddPrinterDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                'إضافة طابعة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNoPrintersContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.print_disabled, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          'لا توجد طابعات مضافة',
          style: GoogleFonts.cairo(fontSize: 16, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        Text(
          'قم بإضافة طابعة للمتابعة',
          style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  Widget _buildPrintersList(BuildContext context, PrintingProvider provider) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: provider.printers.length,
      itemBuilder: (context, index) {
        final printer = provider.printers[index];
        final isSelected = provider.selectedPrinter?.id == printer.id;

        return Card(
          elevation: isSelected ? 2 : 0,
          color: isSelected
              ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
              : null,
          child: ListTile(
            leading: Icon(
              Icons.print,
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            ),
            title: Text(
              printer.name,
              style: GoogleFonts.cairo(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              '${printer.ip}:${printer.port}',
              style: GoogleFonts.robotoMono(fontSize: 12),
            ),
            trailing: isSelected
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).primaryColor,
                  )
                : null,
            onTap: () {
              provider.selectPrinter(printer);
              onPrinterSelected?.call();
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }

  Future<void> _showAddPrinterDialog(BuildContext context) async {
    final result = await showDialog<PrinterConfig>(
      context: context,
      builder: (context) => const AddPrinterDialog(),
    );

    if (result != null && context.mounted) {
      await context.read<PrintingProvider>().addPrinter(result);
    }
  }
}

class AddPrinterDialog extends StatefulWidget {
  const AddPrinterDialog({super.key});

  @override
  State<AddPrinterDialog> createState() => _AddPrinterDialogState();
}

class _AddPrinterDialogState extends State<AddPrinterDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9100');
  bool _isTesting = false;
  bool? _testResult;

  static const _primaryColor = Color(0xFF1565C0);

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Container(
          constraints: BoxConstraints(maxWidth: isMobile ? 360 : 450),
          padding: EdgeInsets.all(isMobile ? 20 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.print_rounded, size: 36, color: _primaryColor),
              ),
              const SizedBox(height: 16),
              Text(
                'إضافة طابعة جديدة',
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 24),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildTextField(
                      controller: _nameController,
                      label: 'اسم الطابعة',
                      icon: Icons.label_outline_rounded,
                      hint: 'مثال: طابعة المستودع',
                      validator: (v) => (v == null || v.isEmpty) ? 'يرجى إدخال الاسم' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _ipController,
                      label: 'عنوان IP',
                      icon: Icons.lan_outlined,
                      hint: '192.168.1.100',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'يرجى إدخال IP';
                        final ipRegex = RegExp(r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$');
                        return !ipRegex.hasMatch(v) ? 'عنوان IP غير صالح' : null;
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _portController,
                      label: 'المنفذ',
                      icon: Icons.settings_ethernet_rounded,
                      hint: '9100',
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'يرجى إدخال المنفذ';
                        final p = int.tryParse(v);
                        return (p == null || p < 1 || p > 65535) ? 'غير صالح' : null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_testResult != null) _buildTestStatus(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('إلغاء', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _isTesting
                      ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                      : Expanded(
                          child: ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: Text('حفظ', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                          ),
                        ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: const Icon(Icons.wifi_find_rounded, size: 20),
                label: Text('اختبار الاتصال بالطابعة', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(foregroundColor: _primaryColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.cairo(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(fontSize: 14, color: Colors.grey[600]),
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: _primaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primaryColor, width: 2)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _buildTestStatus() {
    final success = _testResult!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: success ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: success ? Colors.green.shade200 : Colors.red.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(success ? Icons.check_circle_rounded : Icons.error_rounded, color: success ? Colors.green : Colors.red, size: 20),
          const SizedBox(width: 8),
          Text(
            success ? 'الاتصال بالطابعة ناجح' : 'فشل الاتصال بالطابعة',
            style: GoogleFonts.cairo(color: success ? Colors.green.shade800 : Colors.red.shade800, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final printer = PrinterConfig(
      id: '',
      name: _nameController.text,
      ip: _ipController.text,
      port: int.parse(_portController.text),
    );

    final result = await context.read<PrintingProvider>().testConnection(
      printer,
    );

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = result;
      });
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final printer = PrinterConfig(
      id: '',
      name: _nameController.text,
      ip: _ipController.text,
      port: int.parse(_portController.text),
      isDefault: true,
    );

    Navigator.of(context).pop(printer);
  }
}
