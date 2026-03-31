import '../core/constants/printing_constants.dart';

class UnitConverter {
  UnitConverter._();

  static int mmToDots(double mm) {
    return (mm * PrintingConstants.printerDpi / 25.4).round();
  }

  static double dotsToMm(int dots) {
    return dots * 25.4 / PrintingConstants.printerDpi;
  }

  static int dotsToBytes(int dots) {
    return (dots + 7) ~/ 8;
  }

  static int bytesToDots(int bytes) {
    return bytes * 8;
  }

  static int alignToBytes(int dots) {
    return dotsToBytes(dots) * 8;
  }
}
