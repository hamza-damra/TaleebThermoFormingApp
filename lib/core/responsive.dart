import 'package:flutter/material.dart';

class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 1200;
}

enum ScreenType { mobile, tablet, desktop }

class ResponsiveHelper {
  static ScreenType getScreenType(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < Breakpoints.mobile) {
      return ScreenType.mobile;
    } else if (width < Breakpoints.tablet) {
      return ScreenType.tablet;
    } else {
      return ScreenType.desktop;
    }
  }

  static bool isMobile(BuildContext context) {
    return getScreenType(context) == ScreenType.mobile;
  }

  static bool isTablet(BuildContext context) {
    return getScreenType(context) == ScreenType.tablet;
  }

  static bool isDesktop(BuildContext context) {
    return getScreenType(context) == ScreenType.desktop;
  }

  static bool isTabletOrDesktop(BuildContext context) {
    final type = getScreenType(context);
    return type == ScreenType.tablet || type == ScreenType.desktop;
  }

  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }
}

class ResponsiveValue<T> {
  final T mobile;
  final T tablet;
  final T? desktop;

  const ResponsiveValue({
    required this.mobile,
    required this.tablet,
    this.desktop,
  });

  T getValue(BuildContext context) {
    final screenType = ResponsiveHelper.getScreenType(context);
    switch (screenType) {
      case ScreenType.mobile:
        return mobile;
      case ScreenType.tablet:
        return tablet;
      case ScreenType.desktop:
        return desktop ?? tablet;
    }
  }
}

class ResponsivePadding {
  static EdgeInsets all(BuildContext context) {
    return EdgeInsets.all(ResponsiveHelper.isMobile(context) ? 12 : 24);
  }

  static EdgeInsets horizontal(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: ResponsiveHelper.isMobile(context) ? 12 : 24,
    );
  }

  static EdgeInsets symmetric(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: ResponsiveHelper.isMobile(context) ? 12 : 24,
      vertical: ResponsiveHelper.isMobile(context) ? 8 : 16,
    );
  }
}

class ResponsiveFontSize {
  static double title(BuildContext context) {
    return ResponsiveHelper.isMobile(context) ? 18 : 24;
  }

  static double subtitle(BuildContext context) {
    return ResponsiveHelper.isMobile(context) ? 16 : 20;
  }

  static double body(BuildContext context) {
    return ResponsiveHelper.isMobile(context) ? 14 : 16;
  }

  static double small(BuildContext context) {
    return ResponsiveHelper.isMobile(context) ? 12 : 14;
  }

  static double header(BuildContext context) {
    return ResponsiveHelper.isMobile(context) ? 16 : 18;
  }
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ScreenType screenType) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenType = ResponsiveHelper.getScreenType(context);
        return builder(context, screenType);
      },
    );
  }
}

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget tablet;
  final Widget? desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.tablet,
    this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, screenType) {
        switch (screenType) {
          case ScreenType.mobile:
            return mobile;
          case ScreenType.tablet:
            return tablet;
          case ScreenType.desktop:
            return desktop ?? tablet;
        }
      },
    );
  }
}
