import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../domain/entities/label_preset.dart';
import '../providers/printing_provider.dart';

class PresetSettingsScreen extends StatelessWidget {
  const PresetSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'أحجام الملصقات',
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
            children: [_PresetsSection(provider: provider)],
          );
        },
      ),
    );
  }
}

// ─── Presets Section ────────────────────────────────────────────────────────

class _PresetsSection extends StatelessWidget {
  final PrintingProvider provider;

  const _PresetsSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.straighten, size: 22, color: Color(0xFF1565C0)),
            const SizedBox(width: 8),
            Text(
              'أحجام الملصقات',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1565C0),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _showAddPresetDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                'إضافة حجم',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (provider.presets.isEmpty)
          _buildEmptyState(
            icon: Icons.straighten,
            message: 'لا توجد أحجام ملصقات',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: provider.presets
                .map(
                  (preset) => _PresetChip(
                    preset: preset,
                    isSelected: provider.selectedPreset?.id == preset.id,
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Future<void> _showAddPresetDialog(BuildContext context) async {
    final result = await showDialog<LabelPreset>(
      context: context,
      builder: (context) =>
          const _PresetFormDialog(title: 'إضافة حجم ملصق جديد'),
    );
    if (result != null && context.mounted) {
      await context.read<PrintingProvider>().addPreset(result);
    }
  }
}

class _PresetChip extends StatelessWidget {
  final LabelPreset preset;
  final bool isSelected;

  const _PresetChip({required this.preset, required this.isSelected});

  bool get _isCustom => !preset.id.startsWith('default_');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.read<PrintingProvider>().selectPreset(preset),
      onLongPress: _isCustom ? () => _showPresetOptions(context) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1565C0) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF1565C0) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.straighten,
              size: 20,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(width: 8),
            Text(
              preset.name,
              style: GoogleFonts.cairo(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
                color: isSelected ? Colors.white : Colors.black87,
              ),
            ),
            if (_isCustom) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.edit_note,
                size: 18,
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.8)
                    : Colors.grey,
              ),
            ],
            if (isSelected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle, size: 18, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }

  void _showPresetOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text('تعديل', style: GoogleFonts.cairo()),
              onTap: () {
                Navigator.of(ctx).pop();
                _editPreset(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text('حذف', style: GoogleFonts.cairo(color: Colors.red)),
              onTap: () {
                Navigator.of(ctx).pop();
                _deletePreset(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPreset(BuildContext context) async {
    final result = await showDialog<LabelPreset>(
      context: context,
      builder: (context) =>
          _PresetFormDialog(title: 'تعديل حجم الملصق', preset: preset),
    );
    if (result != null && context.mounted) {
      await context.read<PrintingProvider>().updatePreset(result);
    }
  }

  Future<void> _deletePreset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'حذف حجم الملصق',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'هل أنت متأكد من حذف "${preset.name}"؟',
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
      await context.read<PrintingProvider>().deletePreset(preset.id);
    }
  }
}

// ─── Preset Form Dialog ─────────────────────────────────────────────────────

class _PresetFormDialog extends StatefulWidget {
  final String title;
  final LabelPreset? preset;

  const _PresetFormDialog({required this.title, this.preset});

  @override
  State<_PresetFormDialog> createState() => _PresetFormDialogState();
}

class _PresetFormDialogState extends State<_PresetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;
  late final TextEditingController _marginController;

  static const _primaryColor = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.preset?.name ?? '');
    _widthController = TextEditingController(
      text: widget.preset?.widthMm.toString() ?? '',
    );
    _heightController = TextEditingController(
      text: widget.preset?.heightMm.toString() ?? '',
    );
    _marginController = TextEditingController(
      text: widget.preset?.marginMm.toString() ?? '2',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _marginController.dispose();
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
                child: const Icon(
                  Icons.straighten_rounded,
                  size: 36,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.title,
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
                      label: 'اسم الحجم',
                      icon: Icons.label_outline_rounded,
                      hint: 'مثال: 70×40 مم',
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'يرجى إدخال الاسم' : null,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _widthController,
                            label: 'العرض (مم)',
                            icon: Icons.width_full_rounded,
                            hint: '70',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'مطلوب';
                              final n = double.tryParse(v);
                              return (n == null || n <= 0) ? 'غير صالح' : null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _heightController,
                            label: 'الارتفاع (مم)',
                            icon: Icons.height_rounded,
                            hint: '40',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'مطلوب';
                              final n = double.tryParse(v);
                              return (n == null || n <= 0) ? 'غير صالح' : null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTextField(
                      controller: _marginController,
                      label: 'الهامش (مم)',
                      icon: Icons.space_bar_rounded,
                      hint: '2',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'مطلوب';
                        final n = double.tryParse(v);
                        return (n == null || n < 0) ? 'غير صالح' : null;
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
                        'حفظ البيانات',
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

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final preset = LabelPreset(
      id: widget.preset?.id ?? '',
      name: _nameController.text,
      widthMm: double.parse(_widthController.text),
      heightMm: double.parse(_heightController.text),
      marginMm: double.parse(_marginController.text),
    );
    Navigator.of(context).pop(preset);
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
