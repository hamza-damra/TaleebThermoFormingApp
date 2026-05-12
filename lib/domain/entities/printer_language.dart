enum PrinterLanguage {
  tspl,
  zpl;

  String get wireValue {
    switch (this) {
      case PrinterLanguage.tspl:
        return 'tspl';
      case PrinterLanguage.zpl:
        return 'zpl';
    }
  }

  String get displayName {
    switch (this) {
      case PrinterLanguage.tspl:
        return 'XPrinter / TSPL';
      case PrinterLanguage.zpl:
        return 'Zebra / ZPL';
    }
  }

  static PrinterLanguage fromWireValue(String? value) {
    switch (value) {
      case 'zpl':
        return PrinterLanguage.zpl;
      case 'tspl':
      default:
        return PrinterLanguage.tspl;
    }
  }
}
