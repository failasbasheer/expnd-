package com.failas.expnd

import io.flutter.embedding.android.FlutterFragmentActivity

// Must extend FlutterFragmentActivity (not FlutterActivity) so the local_auth
// biometric prompt has an AndroidX FragmentActivity host. Otherwise
// authenticate() throws `no_fragment_activity` at runtime.
class MainActivity : FlutterFragmentActivity()
