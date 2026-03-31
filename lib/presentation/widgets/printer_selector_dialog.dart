import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../domain/entities/printer_config.dart';
import '../providers/printing_provider.dart';
import '../screens/printer_settings_screen.dart';

class PrinterSelectorDialog extends StatelessWidget {
  final VoidCallback? onPrinterSelected;

  static const _primaryColor = Color(0xFF1565C0);

  const PrinterSelectorDialog({super.key, this.onPrinterSelected});

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;
    final padding = isMobile ? 16.0 : 20.0;

    return Consumer<PrintingProvider>(
      builder: (context, provider, _) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 40,
            vertical: 24,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isMobile ? double.infinity : 420,
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with close button - RTL layout
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(padding, 12, padding, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'اختر الطابعة',
                            style: GoogleFonts.cairo(
                              fontWeight: FontWeight.bold,
                              fontSize: isMobile ? 18 : 20,
                              color: _primaryColor,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                            foregroundColor: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: Colors.grey.shade200),
                // Content
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
                    child: provider.printers.isEmpty
                        ? _buildNoPrintersContent(context)
                        : _buildPrintersList(context, provider),
                  ),
                ),
                // Bottom buttons - responsive layout
                Padding(
                  padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
                  child: isSmallScreen
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAddPrinterButton(context, isMobile),
                            const SizedBox(height: 10),
                            _buildSettingsButton(context, isMobile),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: _buildSettingsButton(context, isMobile)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildAddPrinterButton(context, isMobile)),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsButton(BuildContext context, bool isMobile) {
    return OutlinedButton.icon(
      onPressed: () {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PrinterSettingsScreen(),
          ),
        );
      },
      icon: const Icon(Icons.settings_outlined, size: 20),
      label: Text(
        'الإعدادات',
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.w600,
          fontSize: isMobile ? 14 : 15,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _primaryColor,
        side: const BorderSide(color: _primaryColor),
        padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildAddPrinterButton(BuildContext context, bool isMobile) {
    return ElevatedButton.icon(
      onPressed: () => _showAddPrinterDialog(context),
      icon: const Icon(Icons.add, size: 20),
      label: Text(
        'إضافة طابعة',
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          fontSize: isMobile ? 14 : 15,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: isMobile ? 12 : 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
    );
  }

  Widget _buildNoPrintersContent(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.print_disabled_outlined,
            size: 56,
            color: Colors.grey.shade400,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'لا توجد طابعات مضافة',
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'قم بإضافة طابعة للمتابعة',
          style: GoogleFonts.cairo(
            fontSize: 14,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPrintersList(BuildContext context, PrintingProvider provider) {
    return ListView.separated(
      shrinkWrap: true,
      itemCount: provider.printers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final printer = provider.printers[index];
        final isSelected = provider.selectedPrinter?.id == printer.id;

        return Material(
          color: isSelected
              ? _primaryColor.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () {
              provider.selectPrinter(printer);
              onPrinterSelected?.call();
              Navigator.of(context).pop();
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? _primaryColor : Colors.grey.shade200,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _primaryColor.withValues(alpha: 0.15)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.print_rounded,
                      color: isSelected ? _primaryColor : Colors.grey.shade600,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          printer.name,
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: isSelected ? _primaryColor : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${printer.ip}:${printer.port}',
                          style: GoogleFonts.robotoMono(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                ],
              ),
            ),
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
