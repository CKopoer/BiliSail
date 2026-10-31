import 'package:flutter/foundation.dart';

// iOS needs a provisioned multicast entitlement before SSDP can be offered.
bool get supportsDlnaCasting =>
    !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;
