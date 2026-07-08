import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:local_auth/local_auth.dart';
import '../theme/expnd_theme.dart';
import '../theme/sf_icons.dart';
import '../widgets/neopop.dart';

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlock;
  const LockScreen({super.key, required this.onUnlock});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = LocalAuthentication();
  bool _failed = false;
  // A specific, human-readable reason shown under the button when auth can't
  // proceed (locked out, not enrolled, etc.) instead of a silent failure.
  String? _error;
  bool _useFace = true;

  // Label/icon for the available biometric. iOS uses Face ID / Touch ID; on
  // Android the fingerprint sensor should read as "Fingerprint", not Touch ID.
  String get _methodLabel => _useFace
      ? 'Face ID'
      : Platform.isIOS
          ? 'Touch ID'
          : 'Fingerprint';
  String get _methodIcon => _useFace ? 'faceid' : 'touchid';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    try {
      final types = await _auth.getAvailableBiometrics();
      _useFace = types.contains(BiometricType.face);
    } catch (_) {}
    if (mounted) setState(() {});
    _authenticate();
  }

  Future<void> _authenticate() async {
    try {
      final canCheck =
          await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canCheck) {
        // No biometric hardware/OS support at all — there's no PIN fallback,
        // so let the user in rather than trapping them behind a lock they
        // can never satisfy.
        widget.onUnlock();
        return;
      }
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock XPND Finance',
        biometricOnly: true,
      );
      if (!mounted) return;
      if (ok) {
        setState(() {
          _failed = false;
          _error = null;
        });
        widget.onUnlock();
      } else {
        setState(() {
          _failed = true;
          _error = null;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    }
  }

  /// Maps local_auth platform error codes to a friendly, actionable line.
  /// Codes are the string constants the plugin reports on PlatformException.
  String _messageFor(PlatformException e) {
    switch (e.code) {
      case 'NotAvailable':
      case 'NotEnrolled':
        return 'No $_methodLabel is set up on this device. '
            'Add one in your device settings to unlock.';
      case 'LockedOut':
        return 'Too many attempts. Wait a moment, then try again.';
      case 'PermanentlyLockedOut':
        return '$_methodLabel is locked. Unlock your device with its '
            'passcode first, then reopen the app.';
      case 'PasscodeNotSet':
        return 'Set a device passcode to use $_methodLabel.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Material(
      color: oc.bg,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
              child: Column(
                children: [
                  if (_error != null || _failed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                          _error ?? 'Authentication failed. Try again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: ExpndColors.red)),
                    ),
                  NeoPopButton(
                    onPressed: _authenticate,
                    faceColor: ExpndColors.gold,
                    depthColor: ExpndColors.goldDark,
                    depth: 4,
                    cornerRadius: 6,
                    child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(sfIcon(_methodIcon),
                                size: 18, color: ExpndColors.ink),
                            const SizedBox(width: 10),
                            Text(
                              'Unlock with $_methodLabel',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: ExpndColors.ink),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
