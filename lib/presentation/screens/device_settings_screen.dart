import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/config.dart';
import '../../data/datasources/auth_local_storage.dart';

class DeviceSettingsScreen extends StatefulWidget {
  /// If true, this is the initial setup flow (no back button, must save to proceed)
  final bool isSetup;
  final VoidCallback? onDeviceKeyConfigured;

  const DeviceSettingsScreen({
    super.key,
    this.isSetup = false,
    this.onDeviceKeyConfigured,
  });

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  final _keyController = TextEditingController();
  final _storage = AuthLocalStorage();
  bool _isLoading = false;
  bool _isTesting = false;
  bool _hasKey = false;
  bool _obscureKey = true;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadExistingKey();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingKey() async {
    final key = await _storage.getDeviceKey();
    if (key != null && key.isNotEmpty) {
      setState(() {
        _keyController.text = key;
        _hasKey = true;
      });
    }
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال مفتاح الجهاز');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      await _storage.saveDeviceKey(key);
      setState(() {
        _hasKey = true;
        _isLoading = false;
        _successMessage = 'تم حفظ مفتاح الجهاز بنجاح';
      });

      if (widget.isSetup && widget.onDeviceKeyConfigured != null) {
        widget.onDeviceKeyConfigured!();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل في حفظ المفتاح';
      });
    }
  }

  Future<void> _testConnection() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال مفتاح الجهاز أولاً');
      return;
    }

    setState(() {
      _isTesting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      // Save key first, then test bootstrap endpoint
      await _storage.saveDeviceKey(key);

      final uri = Uri.parse('${AppConfig.baseUrl}/palletizing-line/bootstrap');
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(uri);
      request.headers.set('X-Device-Key', key);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      httpClient.close();

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(body) as Map<String, dynamic>?;
      } catch (_) {}

      if (response.statusCode == 200 && data?['success'] == true) {
        setState(() {
          _isTesting = false;
          _hasKey = true;
          _successMessage = 'الاتصال ناجح - المفتاح صالح';
        });
      } else {
        setState(() {
          _isTesting = false;
          _errorMessage = 'المفتاح غير صالح أو الخادم رفض الاتصال';
        });
      }
    } catch (e) {
      setState(() {
        _isTesting = false;
        _errorMessage = 'فشل الاتصال بالخادم - تحقق من الشبكة والمفتاح';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.isSetup
          ? null
          : AppBar(
              title: Text(
                'إعدادات الجهاز',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.white,
                ),
              ),
              centerTitle: true,
              backgroundColor: const Color(0xFF1565C0),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isSetup) ...[
                const SizedBox(height: 40),
                _buildSetupHeader(),
                const SizedBox(height: 40),
              ],
              _buildInfoCard(),
              const SizedBox(height: 24),
              _buildKeyInput(),
              const SizedBox(height: 16),
              if (_errorMessage != null) _buildMessage(_errorMessage!, true),
              if (_successMessage != null)
                _buildMessage(_successMessage!, false),
              const SizedBox(height: 24),
              _buildSaveButton(),
              const SizedBox(height: 12),
              _buildTestButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSetupHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.devices_rounded,
            size: 56,
            color: Color(0xFF1565C0),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'إعداد الجهاز',
          style: GoogleFonts.cairo(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'يرجى إدخال مفتاح الجهاز للمتابعة',
          style: GoogleFonts.cairo(fontSize: 16, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'مفتاح الجهاز هو معرف أمان للاتصال بالخادم. يتم إعداده مرة واحدة بواسطة المسؤول.',
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: Colors.blue.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'مفتاح الجهاز (Device Key)',
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keyController,
          obscureText: _obscureKey,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            hintText: 'أدخل مفتاح الجهاز',
            hintStyle: GoogleFonts.cairo(color: Colors.grey.shade400),
            prefixIcon: Icon(Icons.key_rounded, color: Colors.grey.shade600),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureKey ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey.shade600,
              ),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
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
              borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          onChanged: (_) {
            if (_errorMessage != null || _successMessage != null) {
              setState(() {
                _errorMessage = null;
                _successMessage = null;
              });
            }
          },
        ),
        if (_hasKey)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: Colors.green.shade400,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'مفتاح محفوظ',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMessage(String message, bool isError) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isError ? Colors.red.shade200 : Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red.shade600 : Colors.green.shade600,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: isError ? Colors.red.shade700 : Colors.green.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _saveKey,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFF1565C0).withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isLoading
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            )
          : Text(
              widget.isSetup ? 'حفظ والمتابعة' : 'حفظ المفتاح',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  Widget _buildTestButton() {
    return OutlinedButton(
      onPressed: _isTesting ? null : _testConnection,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF1565C0),
        side: const BorderSide(color: Color(0xFF1565C0)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: _isTesting
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_tethering, size: 20),
                const SizedBox(width: 8),
                Text(
                  'اختبار الاتصال',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
    );
  }
}
