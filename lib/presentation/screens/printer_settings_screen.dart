import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../domain/entities/label_preset.dart';
import '../../domain/entities/print_result.dart';
import '../../domain/entities/printer_config.dart';
import '../../domain/entities/printer_language.dart';
import '../providers/printing_provider.dart';

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
            children: [
              _PrintersSection(provider: provider),
              const SizedBox(height: 24),
              _CopiesSection(provider: provider),
            ],
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
      builder: (context) => PrinterFormDialog.add(),
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
    final provider = context.watch<PrintingProvider>();
    final preset = DefaultPresets.getById(printer.labelPresetId) ??
        provider.presets.firstWhere(
          (p) => p.id == printer.labelPresetId,
          orElse: () => DefaultPresets.defaultPreset,
        );

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${printer.ip}:${printer.port}',
                style: GoogleFonts.robotoMono(
                  fontSize: 13,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _MetaChip(
                    icon: Icons.code_rounded,
                    label: printer.language.displayName,
                  ),
                  _MetaChip(
                    icon: Icons.crop_free_rounded,
                    label: formatPresetSize(preset),
                  ),
                ],
              ),
            ],
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
                  value: 'test_connection',
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_find, size: 18),
                      const SizedBox(width: 8),
                      Text('اختبار الاتصال', style: GoogleFonts.cairo()),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'test_print',
                  child: Row(
                    children: [
                      const Icon(Icons.print_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('اختبار الطباعة', style: GoogleFonts.cairo()),
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
          builder: (context) => PrinterFormDialog.edit(printer: printer),
        );
        if (result != null && context.mounted) {
          await provider.updatePrinter(result);
        }
        break;
      case 'test_connection':
        if (!context.mounted) return;
        _showTestConnectionDialog(context);
        break;
      case 'test_print':
        if (!context.mounted) return;
        _showTestPrintDialog(context);
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
            Flexible(
              child: Text(
                result
                    ? 'تم الاتصال بالطابعة بنجاح'
                    : 'فشل الاتصال بالطابعة',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  color: result ? Colors.green : Colors.red,
                ),
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

  void _showTestPrintDialog(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text('جاري إرسال اختبار الطباعة...', style: GoogleFonts.cairo()),
          ],
        ),
      ),
    );

    final PrintResult result = await context
        .read<PrintingProvider>()
        .testPrint(printer);

    if (!context.mounted) return;
    Navigator.of(context).pop(); // close loading

    final success = result.isSuccess;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: success ? Colors.green : Colors.red,
              size: 26,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                success ? 'تم إرسال اختبار الطباعة' : 'فشل اختبار الطباعة',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  color: success ? Colors.green : Colors.red,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          success
              ? 'إذا لم تطبع الطابعة، تأكد من نوع الطابعة وحجم الملصق'
              : (result.errorMessage ?? 'فشل إرسال اختبار الطباعة'),
          style: GoogleFonts.cairo(),
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

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 11,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Printer Form Dialog (Add + Edit) ────────────────────────────────

class PrinterFormDialog extends StatefulWidget {
  final PrinterConfig? initial;
  final bool isEdit;

  const PrinterFormDialog._({this.initial, required this.isEdit});

  factory PrinterFormDialog.add() =>
      const PrinterFormDialog._(isEdit: false);

  factory PrinterFormDialog.edit({required PrinterConfig printer}) =>
      PrinterFormDialog._(initial: printer, isEdit: true);

  @override
  State<PrinterFormDialog> createState() => _PrinterFormDialogState();
}

class _PrinterFormDialogState extends State<PrinterFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  late PrinterLanguage _language;
  late String _labelPresetId;
  bool _isTesting = false;
  bool? _testResult;

  static const _primaryColor = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _ipController = TextEditingController(text: initial?.ip ?? '');
    _portController = TextEditingController(
      text: (initial?.port ?? 9100).toString(),
    );
    _language = initial?.language ?? PrinterLanguage.tspl;
    _labelPresetId =
        initial?.labelPresetId ?? DefaultPresets.defaultPreset.id;
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
          constraints: BoxConstraints(maxWidth: isMobile ? 380 : 480),
          padding: EdgeInsets.all(isMobile ? 20 : 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.isEdit ? Icons.edit_rounded : Icons.print_rounded,
                  size: 36,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.isEdit ? 'تعديل الطابعة' : 'إضافة طابعة جديدة',
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
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'يرجى إدخال الاسم'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _ipController,
                      label: 'عنوان IP',
                      icon: Icons.lan_outlined,
                      hint: '192.168.1.100',
                      keyboardType: TextInputType.number,
                      validator: _validateIp,
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _portController,
                      label: 'المنفذ',
                      icon: Icons.settings_ethernet_rounded,
                      hint: '9100',
                      keyboardType: TextInputType.number,
                      validator: _validatePort,
                    ),
                    const SizedBox(height: 16),
                    _buildLanguageDropdown(),
                    const SizedBox(height: 16),
                    _buildPresetTile(),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'إلغاء',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _isTesting
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(),
                        )
                      : Expanded(
                          child: ElevatedButton(
                            onPressed: _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'حفظ',
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: const Icon(Icons.wifi_find_rounded, size: 20),
                label: Text(
                  'اختبار الاتصال بالطابعة',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                ),
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
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _buildLanguageDropdown() {
    return DropdownButtonFormField<PrinterLanguage>(
      initialValue: _language,
      style: GoogleFonts.cairo(fontSize: 15, color: Colors.black87),
      items: PrinterLanguage.values
          .map(
            (lang) => DropdownMenuItem(
              value: lang,
              child: Text(lang.displayName, style: GoogleFonts.cairo()),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _language = value);
      },
      decoration: InputDecoration(
        labelText: 'نوع الطابعة',
        labelStyle: GoogleFonts.cairo(fontSize: 14, color: Colors.grey[600]),
        prefixIcon: const Icon(
          Icons.code_rounded,
          size: 20,
          color: _primaryColor,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _buildPresetTile() {
    final provider = context.watch<PrintingProvider>();
    final selected = _resolvePreset(_labelPresetId, provider);
    final displayName = formatPresetSize(selected);

    return InkWell(
      onTap: _openPresetPicker,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.crop_free_rounded,
              size: 20,
              color: _primaryColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'حجم الملصق',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    displayName,
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.grey.shade500,
            ),
          ],
        ),
      ),
    );
  }

  /// Resolves the [LabelPreset] referenced by [id], looking through the
  /// built-in catalogue first and falling back to custom presets stored in
  /// the local repository. Returns the global default when nothing matches.
  LabelPreset _resolvePreset(String id, PrintingProvider provider) {
    final builtIn = DefaultPresets.getById(id);
    if (builtIn != null) return builtIn;
    for (final p in provider.presets) {
      if (p.id == id) return p;
    }
    return DefaultPresets.defaultPreset;
  }

  Future<void> _openPresetPicker() async {
    final provider = context.read<PrintingProvider>();
    final defaults = DefaultPresets.all;
    // Only show custom presets with sane dimensions — this keeps any legacy
    // garbage rows (e.g. ones whose stored name was "h") out of the picker.
    final customs = provider.presets
        .where(
          (p) =>
              !p.id.startsWith('default_') &&
              p.widthMm >= 10 &&
              p.widthMm <= 200 &&
              p.heightMm >= 10 &&
              p.heightMm <= 200,
        )
        .toList();

    // If the printer is pointing at a saved id that is no longer in either
    // list (a legacy default the user never re-picked, for example) we still
    // surface it as the "current" entry so the saved size doesn't silently
    // vanish from the UI.
    final allIds = {
      ...defaults.map((p) => p.id),
      ...customs.map((p) => p.id),
    };
    LabelPreset? fallback;
    if (!allIds.contains(_labelPresetId)) {
      fallback = DefaultPresets.getById(_labelPresetId);
    }

    final result = await showModalBottomSheet<_PickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PresetPickerSheet(
        defaults: defaults,
        customs: customs,
        fallback: fallback,
        selectedId: _labelPresetId,
      ),
    );

    if (result == null || !mounted) return;

    switch (result.kind) {
      case _PickerResultKind.preset:
        setState(() => _labelPresetId = result.preset!.id);
        break;
      case _PickerResultKind.deleteCustom:
        await provider.deletePreset(result.preset!.id);
        if (_labelPresetId == result.preset!.id && mounted) {
          setState(() => _labelPresetId = DefaultPresets.defaultPreset.id);
        }
        break;
      case _PickerResultKind.addCustom:
        final created = await showDialog<LabelPreset>(
          context: context,
          builder: (_) => const _CustomSizeDialog(),
        );
        if (created == null || !mounted) return;
        final saved = await context.read<PrintingProvider>().addPreset(created);
        if (mounted) setState(() => _labelPresetId = saved.id);
        break;
    }
  }

  Widget _buildTestStatus() {
    final success = _testResult!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: success ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: success ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            success ? Icons.check_circle_rounded : Icons.error_rounded,
            color: success ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              success
                  ? 'تم الاتصال بالطابعة بنجاح'
                  : 'فشل الاتصال بالطابعة',
              style: GoogleFonts.cairo(
                color: success ? Colors.green.shade800 : Colors.red.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _validateIp(String? v) {
    if (v == null || v.isEmpty) return 'يرجى إدخال IP';
    final ipRegex = RegExp(
      r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$',
    );
    return !ipRegex.hasMatch(v) ? 'عنوان IP غير صالح' : null;
  }

  String? _validatePort(String? v) {
    if (v == null || v.isEmpty) return 'يرجى إدخال المنفذ';
    final p = int.tryParse(v);
    return (p == null || p < 1 || p > 65535) ? 'غير صالح' : null;
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final probe = PrinterConfig(
      id: widget.initial?.id ?? '',
      name: _nameController.text,
      ip: _ipController.text,
      port: int.parse(_portController.text),
      language: _language,
      labelPresetId: _labelPresetId,
    );

    final result = await context.read<PrintingProvider>().testConnection(
      probe,
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

    final initial = widget.initial;
    final saved = (initial ??
            const PrinterConfig(id: '', name: '', ip: ''))
        .copyWith(
      name: _nameController.text.trim(),
      ip: _ipController.text.trim(),
      port: int.parse(_portController.text),
      language: _language,
      labelPresetId: _labelPresetId,
      isDefault: widget.isEdit ? initial!.isDefault : true,
    );

    Navigator.of(context).pop(saved);
  }
}

// ─── Copies Section ─────────────────────────────────────────────────────────

class _CopiesSection extends StatelessWidget {
  final PrintingProvider provider;

  const _CopiesSection({required this.provider});

  static const _primaryColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.copy_all_rounded, size: 22, color: _primaryColor),
            const SizedBox(width: 8),
            Text(
              'عدد النسخ',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.print_rounded,
                    color: _primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'عدد النسخ لكل طبلية',
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'عدد الملصقات المطبوعة عند إنشاء طبلية جديدة',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: provider.copies > 1
                            ? () => provider.setCopies(provider.copies - 1)
                            : null,
                        icon: const Icon(Icons.remove_rounded, size: 20),
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        color: _primaryColor,
                        disabledColor: Colors.grey.shade400,
                      ),
                      Container(
                        constraints: const BoxConstraints(minWidth: 36),
                        alignment: Alignment.center,
                        child: Text(
                          '${provider.copies}',
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _primaryColor,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: provider.copies < 10
                            ? () => provider.setCopies(provider.copies + 1)
                            : null,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        color: _primaryColor,
                        disabledColor: Colors.grey.shade400,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

/// Formats a label preset as "{w}×{h} مم". Recomputing the display string
/// from dimensions (instead of trusting the stored `name`) makes the picker
/// resilient to garbage rows from earlier app versions where users could
/// type a free-form name like "h".
String formatPresetSize(LabelPreset p) =>
    '${_formatMm(p.widthMm)}×${_formatMm(p.heightMm)} مم';

String _formatMm(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

// ─── Preset picker bottom sheet ─────────────────────────────────────────────

enum _PickerResultKind { preset, deleteCustom, addCustom }

class _PickerResult {
  final _PickerResultKind kind;
  final LabelPreset? preset;
  const _PickerResult.preset(LabelPreset p)
      : kind = _PickerResultKind.preset,
        preset = p;
  const _PickerResult.deleteCustom(LabelPreset p)
      : kind = _PickerResultKind.deleteCustom,
        preset = p;
  const _PickerResult.addCustom()
      : kind = _PickerResultKind.addCustom,
        preset = null;
}

class _PresetPickerSheet extends StatelessWidget {
  final List<LabelPreset> defaults;
  final List<LabelPreset> customs;
  final LabelPreset? fallback;
  final String selectedId;

  const _PresetPickerSheet({
    required this.defaults,
    required this.customs,
    required this.fallback,
    required this.selectedId,
  });

  static const _primaryColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxHeight = mq.size.height * 0.7;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.crop_free_rounded,
                      color: _primaryColor,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'اختر حجم الملصق',
                      style: GoogleFonts.cairo(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (fallback != null)
                      _PresetRow(
                        preset: fallback!,
                        isSelected: fallback!.id == selectedId,
                        isCustom: false,
                        onTap: () => Navigator.of(context)
                            .pop(_PickerResult.preset(fallback!)),
                      ),
                    ...defaults.map(
                      (p) => _PresetRow(
                        preset: p,
                        isSelected: p.id == selectedId,
                        isCustom: false,
                        onTap: () => Navigator.of(context)
                            .pop(_PickerResult.preset(p)),
                      ),
                    ),
                    if (customs.isNotEmpty) ...[
                      const Divider(height: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: Text(
                          'أحجام مخصصة',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      ...customs.map(
                        (p) => _PresetRow(
                          preset: p,
                          isSelected: p.id == selectedId,
                          isCustom: true,
                          onTap: () => Navigator.of(context)
                              .pop(_PickerResult.preset(p)),
                          onDelete: () => Navigator.of(context)
                              .pop(_PickerResult.deleteCustom(p)),
                        ),
                      ),
                    ],
                    const Divider(height: 16),
                    ListTile(
                      onTap: () => Navigator.of(context)
                          .pop(const _PickerResult.addCustom()),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: _primaryColor,
                          size: 22,
                        ),
                      ),
                      title: Text(
                        'إضافة حجم مخصص',
                        style: GoogleFonts.cairo(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  final LabelPreset preset;
  final bool isSelected;
  final bool isCustom;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _PresetRow({
    required this.preset,
    required this.isSelected,
    required this.isCustom,
    required this.onTap,
    this.onDelete,
  });

  static const _primaryColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? _primaryColor.withValues(alpha: 0.15)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.crop_free_rounded,
          size: 20,
          color: isSelected ? _primaryColor : Colors.grey.shade600,
        ),
      ),
      title: Text(
        formatPresetSize(preset),
        style: GoogleFonts.cairo(
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          color: isSelected ? _primaryColor : Colors.black87,
        ),
      ),
      subtitle: isCustom
          ? Text(
              'حجم مخصص',
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected)
            const Icon(Icons.check_circle, color: _primaryColor, size: 22),
          if (isCustom && onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red.shade400,
              tooltip: 'حذف',
            ),
        ],
      ),
    );
  }
}

// ─── Custom size dialog ─────────────────────────────────────────────────────

class _CustomSizeDialog extends StatefulWidget {
  const _CustomSizeDialog();

  @override
  State<_CustomSizeDialog> createState() => _CustomSizeDialogState();
}

class _CustomSizeDialogState extends State<_CustomSizeDialog> {
  static const _primaryColor = Color(0xFF1565C0);
  static const double _minMm = 10;
  static const double _maxMm = 200;

  final _formKey = GlobalKey<FormState>();
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    if (v == null || v.trim().isEmpty) return 'مطلوب';
    final n = double.tryParse(v.trim());
    if (n == null) return 'أدخل رقمًا صالحًا';
    if (n < _minMm || n > _maxMm) return 'بين 10 و 200';
    return null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final w = double.parse(_widthController.text.trim());
    final h = double.parse(_heightController.text.trim());
    final preset = LabelPreset(
      id: '',
      // Name is recomputed from dimensions by `formatPresetSize` at render
      // time, so it doesn't matter what we store here — but keep it in the
      // same canonical format anyway for clarity in storage dumps.
      name: '${_formatMm(w)}×${_formatMm(h)} مم',
      widthMm: w,
      heightMm: h,
    );
    Navigator.of(context).pop(preset);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.aspect_ratio_rounded,
                  color: _primaryColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'إضافة حجم مخصص',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'القيم بالملليمتر (10–200)',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      controller: _widthController,
                      label: 'العرض (مم)',
                      icon: Icons.width_full_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(
                      controller: _heightController,
                      label: 'الارتفاع (مم)',
                      icon: Icons.height_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'إلغاء',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                      ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'إضافة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
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

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: _validate,
      style: GoogleFonts.cairo(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(fontSize: 13, color: Colors.grey[600]),
        prefixIcon: Icon(icon, size: 20, color: _primaryColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }
}
