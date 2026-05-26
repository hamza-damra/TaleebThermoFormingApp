import 'dart:async';
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

  /// Structured diagnostic from the last "Test connection" run. Rendered as a
  /// monospace panel under the buttons so an operator can read off the exact
  /// URL, HTTP status, parsed line count, etc. — no need to attach the tablet
  /// to a laptop for adb logcat in the common case.
  _BootstrapDiagnostic? _lastDiagnostic;

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
      _lastDiagnostic = null;
    });

    // Save key first, then test bootstrap endpoint. The full URL is
    // constructed exactly the same way Dio constructs it in production code
    // (baseUrl + '/palletizing-line/bootstrap') so a successful test here
    // proves the production code path will reach the backend too.
    await _storage.saveDeviceKey(key);
    final fullUrl = '${AppConfig.baseUrl}/palletizing-line/bootstrap';
    final uri = Uri.parse(fullUrl);

    int? statusCode;
    int bodyLength = 0;
    List<String> topKeys = const [];
    List<String> dataKeys = const [];
    int? linesCount;
    int? productTypesCount;
    String? firstLineUiMode;
    int? firstLineId;
    String? firstLineName;
    bool? firstLineAuthorized;
    bool? firstLineBlocked;
    String? exceptionType;
    String? exceptionMessage;

    try {
      final httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await httpClient.getUrl(uri);
      request.headers.set('X-Device-Key', key);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      statusCode = response.statusCode;
      final body = await response.transform(utf8.decoder).join();
      bodyLength = body.length;
      httpClient.close();

      Map<String, dynamic>? envelope;
      try {
        envelope = jsonDecode(body) as Map<String, dynamic>?;
      } catch (e) {
        exceptionType = 'FormatException';
        exceptionMessage = 'response body is not valid JSON: $e';
      }

      if (envelope != null) {
        topKeys = envelope.keys.toList();
        final data = envelope['data'];
        if (data is Map<String, dynamic>) {
          dataKeys = data.keys.toList();
          final lines = data['lines'];
          if (lines is List) {
            linesCount = lines.length;
            if (lines.isNotEmpty && lines.first is Map<String, dynamic>) {
              final firstLine = lines.first as Map<String, dynamic>;
              firstLineId = firstLine['lineId'] as int?;
              firstLineName = firstLine['lineName'] as String?;
              firstLineAuthorized = firstLine['authorized'] as bool?;
              firstLineBlocked = firstLine['blocked'] as bool?;
              firstLineUiMode = firstLine['lineUiMode'] as String?;
            }
          }
          final productTypes = data['productTypes'];
          if (productTypes is List) productTypesCount = productTypes.length;
        }
      }

      final success = statusCode == 200 && envelope?['success'] == true;
      setState(() {
        _isTesting = false;
        _hasKey = success;
        if (success) {
          _successMessage = 'الاتصال ناجح - المفتاح صالح';
        } else if (statusCode == 401 || statusCode == 403) {
          _errorMessage =
              'المفتاح غير صالح (HTTP $statusCode) — تحقق من قيمة المفتاح';
        } else if (statusCode == 404) {
          _errorMessage =
              'المسار غير موجود على الخادم (HTTP 404) — تحقق من baseUrl';
        } else {
          _errorMessage =
              'فشل الاتصال — HTTP $statusCode، راجع التفاصيل أدناه';
        }
      });
    } on SocketException catch (e) {
      exceptionType = 'SocketException';
      exceptionMessage = e.message;
    } on HandshakeException catch (e) {
      exceptionType = 'HandshakeException (TLS)';
      exceptionMessage = e.message;
    } on TimeoutException catch (e) {
      exceptionType = 'TimeoutException';
      exceptionMessage = e.message ?? 'request timed out';
    } catch (e) {
      exceptionType = e.runtimeType.toString();
      exceptionMessage = e.toString();
    }

    if (exceptionType != null) {
      setState(() {
        _isTesting = false;
        _errorMessage =
            'فشل الاتصال بالشبكة — $exceptionType: $exceptionMessage';
      });
    }

    setState(() {
      _lastDiagnostic = _BootstrapDiagnostic(
        url: fullUrl,
        statusCode: statusCode,
        bodyLength: bodyLength,
        topKeys: topKeys,
        dataKeys: dataKeys,
        linesCount: linesCount,
        productTypesCount: productTypesCount,
        firstLineId: firstLineId,
        firstLineName: firstLineName,
        firstLineAuthorized: firstLineAuthorized,
        firstLineBlocked: firstLineBlocked,
        firstLineUiMode: firstLineUiMode,
        exceptionType: exceptionType,
        exceptionMessage: exceptionMessage,
        deviceKeyLength: key.length,
      );
    });
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
              if (_lastDiagnostic != null) ...[
                const SizedBox(height: 16),
                _BootstrapDiagnosticPanel(diagnostic: _lastDiagnostic!),
              ],
              const SizedBox(height: 16),
              _buildBuildBadge(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBuildBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Build: ${AppConfig.buildLabel}',
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'API: ${AppConfig.baseUrl}',
            style: GoogleFonts.robotoMono(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
        ],
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

/// Snapshot of the most recent bootstrap probe — captured fields mirror the
/// release-build log lines (`[Bootstrap REQUEST/RESPONSE/RAW/PARSE]`) so an
/// operator can read the same diagnostic on-screen without `adb logcat`.
class _BootstrapDiagnostic {
  final String url;
  final int? statusCode;
  final int bodyLength;
  final List<String> topKeys;
  final List<String> dataKeys;
  final int? linesCount;
  final int? productTypesCount;
  final int? firstLineId;
  final String? firstLineName;
  final bool? firstLineAuthorized;
  final bool? firstLineBlocked;
  final String? firstLineUiMode;
  final String? exceptionType;
  final String? exceptionMessage;
  final int deviceKeyLength;

  const _BootstrapDiagnostic({
    required this.url,
    required this.statusCode,
    required this.bodyLength,
    required this.topKeys,
    required this.dataKeys,
    required this.linesCount,
    required this.productTypesCount,
    required this.firstLineId,
    required this.firstLineName,
    required this.firstLineAuthorized,
    required this.firstLineBlocked,
    required this.firstLineUiMode,
    required this.exceptionType,
    required this.exceptionMessage,
    required this.deviceKeyLength,
  });
}

class _BootstrapDiagnosticPanel extends StatelessWidget {
  final _BootstrapDiagnostic diagnostic;

  const _BootstrapDiagnosticPanel({required this.diagnostic});

  @override
  Widget build(BuildContext context) {
    final d = diagnostic;
    final ok = d.exceptionType == null && d.statusCode == 200;
    final color = ok ? Colors.green : Colors.orange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تشخيص الاتصال — Bootstrap probe',
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color.shade900,
            ),
          ),
          const Divider(height: 12),
          _row('URL', d.url),
          _row('HTTP status', d.statusCode?.toString() ?? 'no response'),
          _row('Body length', '${d.bodyLength} bytes'),
          _row('Device key length', '${d.deviceKeyLength}'),
          _row('Header name', 'X-Device-Key'),
          if (d.topKeys.isNotEmpty) _row('Top keys', d.topKeys.join(', ')),
          if (d.dataKeys.isNotEmpty) _row('data.* keys', d.dataKeys.join(', ')),
          _row('data.lines count', d.linesCount?.toString() ?? 'absent'),
          _row('data.productTypes count',
              d.productTypesCount?.toString() ?? 'absent'),
          if (d.firstLineId != null)
            _row('first line',
                'id=${d.firstLineId} number="${d.firstLineName ?? ""}"'),
          if (d.firstLineUiMode != null)
            _row('first line lineUiMode', d.firstLineUiMode!),
          if (d.firstLineAuthorized != null)
            _row('first line authorized', '${d.firstLineAuthorized}'),
          if (d.firstLineBlocked != null)
            _row('first line blocked', '${d.firstLineBlocked}'),
          if (d.exceptionType != null) ...[
            const Divider(height: 12),
            _row('Exception', d.exceptionType!),
            if (d.exceptionMessage != null) _row('Message', d.exceptionMessage!),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.robotoMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.robotoMono(
                fontSize: 11,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
