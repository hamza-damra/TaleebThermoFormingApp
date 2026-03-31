import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../domain/entities/printer_config.dart';
import '../providers/printing_provider.dart';
import '../widgets/printer_selector_dialog.dart';

class PrinterSettingsScreen extends StatelessWidget {
  const PrinterSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'إعدادات الطابعات',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1565C0),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Consumer<PrintingProvider>(
        builder: (context, provider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [_PrintersSection(provider: provider)],
          );
        },
      ),
    );
  }
}

// ─── Printers Section ───────────────────────────────────────────────────────

class _PrintersSection extends StatelessWidget {
  final PrintingProvider provider;

  const _PrintersSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.print, size: 22, color: Color(0xFF1565C0)),
            const SizedBox(width: 8),
            Text(
              'الطابعات',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1565C0),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _showAddPrinterDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                'إضافة طابعة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (provider.printers.isEmpty)
          _buildEmptyState(
            icon: Icons.print_disabled,
            message: 'لا توجد طابعات مضافة',
          )
        else
          ...provider.printers.map(
            (printer) => _PrinterCard(
              printer: printer,
              isSelected: provider.selectedPrinter?.id == printer.id,
              isDefault: printer.isDefault,
            ),
          ),
      ],
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

class _PrinterCard extends StatelessWidget {
  final PrinterConfig printer;
  final bool isSelected;
  final bool isDefault;

  const _PrinterCard({
    required this.printer,
    required this.isSelected,
    required this.isDefault,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 2 : 0.5,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? const BorderSide(color: Color(0xFF1565C0), width: 2)
            : BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF1565C0).withValues(alpha: 0.1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.print,
            color: isSelected ? const Color(0xFF1565C0) : Colors.grey[600],
            size: 24,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                printer.name,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? const Color(0xFF1565C0) : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDefault) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'افتراضي',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1565C0),
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${printer.ip}:${printer.port}',
            style: GoogleFonts.robotoMono(
              fontSize: 13,
              color: Colors.grey[600],
              letterSpacing: 0.5,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF1565C0),
                size: 24,
              ),
            PopupMenuButton<String>(
              onSelected: (value) => _handleAction(context, value),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'select',
                  child: Row(
                    children: [
                      const Icon(Icons.radio_button_checked, size: 18),
                      const SizedBox(width: 8),
                      Text('اختيار', style: GoogleFonts.cairo()),
                    ],
                  ),
                ),
                if (!isDefault)
                  PopupMenuItem(
                    value: 'default',
                    child: Row(
                      children: [
                        const Icon(Icons.star_outline, size: 18),
                        const SizedBox(width: 8),
                        Text('تعيين كافتراضي', style: GoogleFonts.cairo()),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 18),
                      const SizedBox(width: 8),
                      Text('تعديل', style: GoogleFonts.cairo()),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'test',
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_find, size: 18),
                      const SizedBox(width: 8),
                      Text('اختبار الاتصال', style: GoogleFonts.cairo()),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, size: 18, color: Colors.red),
                      const SizedBox(width: 8),
                      Text('حذف', style: GoogleFonts.cairo(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        onTap: () {
          context.read<PrintingProvider>().selectPrinter(printer);
        },
      ),
    );
  }

  void _handleAction(BuildContext context, String action) async {
    final provider = context.read<PrintingProvider>();

    switch (action) {
      case 'select':
        provider.selectPrinter(printer);
        break;
      case 'default':
        await provider.setDefaultPrinter(printer.id);
        break;
      case 'edit':
        final result = await showDialog<PrinterConfig>(
          context: context,
          builder: (context) => _EditPrinterDialog(printer: printer),
        );
        if (result != null && context.mounted) {
          await provider.updatePrinter(result);
        }
        break;
      case 'test':
        if (!context.mounted) return;
        _showTestConnectionDialog(context);
        break;
      case 'delete':
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              'حذف الطابعة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            content: Text(
              'هل أنت متأكد من حذف "${printer.name}"؟',
              style: GoogleFonts.cairo(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text('إلغاء', style: GoogleFonts.cairo()),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  'حذف',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await provider.deletePrinter(printer.id);
        }
        break;
    }
  }

  void _showTestConnectionDialog(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text('جاري اختبار الاتصال...', style: GoogleFonts.cairo()),
          ],
        ),
      ),
    );

    final result = await context.read<PrintingProvider>().testConnection(
      printer,
    );

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            Icon(
              result ? Icons.check_circle : Icons.error,
              color: result ? Colors.green : Colors.red,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              result ? 'الاتصال ناجح' : 'فشل الاتصال',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: result ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('حسناً', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }
}

// ─── Edit Printer Dialog ────────────────────────────────────────────────────

class _EditPrinterDialog extends StatefulWidget {
  final PrinterConfig printer;
  const _EditPrinterDialog({required this.printer});

  @override
  State<_EditPrinterDialog> createState() => _EditPrinterDialogState();
}

class _EditPrinterDialogState extends State<_EditPrinterDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ipController;
  late final TextEditingController _portController;

  static const _primaryColor = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.printer.name);
    _ipController = TextEditingController(text: widget.printer.ip);
    _portController = TextEditingController(text: widget.printer.port.toString());
  }

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
                child: const Icon(Icons.edit_rounded, size: 36, color: _primaryColor),
              ),
              const SizedBox(height: 16),
              Text(
                'تعديل الطابعة',
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
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text('حفظ التعديلات', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final updated = widget.printer.copyWith(
      name: _nameController.text,
      ip: _ipController.text,
      port: int.parse(_portController.text),
    );
    Navigator.of(context).pop(updated);
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
}

// ─── Helper ─────────────────────────────────────────────────────────────────

Widget _buildEmptyState({required IconData icon, required String message}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    ),
  );
}
