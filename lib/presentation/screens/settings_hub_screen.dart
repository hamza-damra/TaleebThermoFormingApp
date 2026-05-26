import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/config.dart';
import '../../core/responsive.dart';
import 'device_settings_screen.dart';
import 'printer_settings_screen.dart';

class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  static const _primaryColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final crossAxisCount = isMobile ? 1 : 2;
    final padding = isMobile ? 16.0 : 24.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'الإعدادات',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: _primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: isMobile ? 2.8 : 2.2,
                children: [
                  _SettingCard(
                    icon: Icons.print,
                    title: 'إعدادات الطابعات',
                    description: 'إدارة الطابعات وأحجام الملصقات',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrinterSettingsScreen(),
                      ),
                    ),
                  ),
                  // Device-key recovery path. The key is normally shipped as a
                  // hardcoded constant, but this entry lets an admin re-test the
                  // connection or change the configured key when the production app
                  // reports a device-key failure.
                  _SettingCard(
                    icon: Icons.settings_input_component_rounded,
                    title: 'إعدادات الجهاز',
                    description: 'إدارة مفتاح الجهاز واختبار الاتصال',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DeviceSettingsScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const _BuildBadge(),
          ],
        ),
      ),
    );
  }
}

/// Hotfix-only footer rendering the active build label + backend base URL.
/// Lets a field operator visually confirm which APK is running and which
/// server it points at — essential when diagnosing whether a tablet has the
/// fresh hotfix installed.
class _BuildBadge extends StatelessWidget {
  const _BuildBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build_circle_outlined,
                  size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Build: ${AppConfig.buildLabel}',
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.cloud_outlined,
                  size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'API: ${AppConfig.baseUrl}',
                  style: GoogleFonts.robotoMono(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  static const _primaryColor = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 36, color: _primaryColor),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey[400], size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
