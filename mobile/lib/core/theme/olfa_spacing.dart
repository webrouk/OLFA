import 'package:flutter/widgets.dart';

/// 4-pt spacing scale and the radius set used across the app.
abstract final class OlfaSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20; // default page gutter
  static const double xxl = 24;
  static const double xxxl = 32;

  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: xl);
}

abstract final class OlfaRadius {
  static const double chip = 19;
  static const double input = 14;
  static const double button = 14;
  static const double card = 18;
  static const double sheet = 26;
  static const double navBar = 24;
  static const double profileCard = 26;

  static BorderRadius all(double r) => BorderRadius.all(Radius.circular(r));
}

abstract final class OlfaSize {
  static const double buttonHeight = 52;
  static const double inputHeight = 52;
  static const double navBarHeight = 68;
  static const double navBarMargin = 14;
  static const double minTap = 44;

  /// Space that scrollable content must leave for the floating nav bar.
  static double navBarClearance(BuildContext context) =>
      navBarHeight + navBarMargin + 12 + MediaQuery.paddingOf(context).bottom;
}
