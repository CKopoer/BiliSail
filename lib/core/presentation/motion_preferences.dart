import 'package:flutter/widgets.dart';

bool shouldReduceMotion(BuildContext context) {
  // iOS Reduce Motion and the platform's animation-disable request are separate
  // accessibility flags. Either preference uses our existing reduced motion.
  final disableAnimations = MediaQuery.disableAnimationsOf(context);
  final reduceMotion = MediaQuery.reduceMotionOf(context);
  return disableAnimations || reduceMotion;
}
