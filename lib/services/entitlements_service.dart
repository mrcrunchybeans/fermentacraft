import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

class EntitlementsService extends ChangeNotifier with WidgetsBindingObserver {
  EntitlementsService({
    required this.entitlementIds,
    this.webPollInterval = const Duration(seconds: 45),
  });

  /// Your preferred entitlement ids; used as a hint only.
  final List<String> entitlementIds;

  /// Web fallback polling (keeps things fresh without JS interop).
  final Duration webPollInterval;

  bool _loading = true;
  bool _isPremium = false;
  bool get loading => _loading;
  bool get isPremium => _isPremium;

  StreamSubscription<fb.User?>? _authSub;
  Timer? _pollTimer;
  Timer? _burstTimer;
  bool _initialized = false;
  bool _refreshInFlight = false;

  Future<void> init({bool attachToFirebaseAuth = true}) async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    // RC notifies us on purchase/restore/upgrades - only if available.
    try {
      Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);
    } catch (_) {
      // RevenueCat not configured, skip listener setup
      debugPrint('[EntitlementsService] RevenueCat listeners not available');
    }

    // Keep RC user aligned with Firebase Auth (highly recommended).
    if (attachToFirebaseAuth) {
      _authSub = fb.FirebaseAuth.instance.authStateChanges().listen((user) async {
        try {
          if (user == null) {
            await Purchases.logOut();
          } else {
            await Purchases.logIn(user.uid);
          }
        } catch (_) {/* ignore */}
        // ignore: discarded_futures
        forceRefresh(); // make sure we pick up any user-linked entitlements
      });
    }

    // Web: light polling to cover delayed web receipts/webhooks.
    if (kIsWeb) {
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(webPollInterval, (_) => refresh());
    }

    await forceRefresh(); // initial load with a cache-bust
  }

  /// Hard refresh: bust RC cache, then fetch.
  Future<void> forceRefresh() async {
    try { await Purchases.invalidateCustomerInfoCache(); } catch (_) {}
    await refresh();
  }

  /// Normal refresh (debounced).
  Future<void> refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final info = await Purchases.getCustomerInfo();
      _applyCustomerInfo(info);
    } catch (_) {
      if (_loading) {
        _loading = false;
        notifyListeners();
      }
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Call right after closing your paywall.
  /// Sync store, invalidate cache, refresh, then do a short burst of refreshes.
  Future<void> refreshAfterPaywall() async {
    try { await Purchases.syncPurchases(); } catch (_) {}
    try { await Purchases.invalidateCustomerInfoCache(); } catch (_) {}
    await refresh();
    _startBurstRefresh();
  }

  void _startBurstRefresh() {
    _burstTimer?.cancel();
    var remaining = 8; // ~40s total
    _burstTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      remaining--;
      await refresh();
      if (remaining <= 0 || _isPremium) t.cancel();
    });
  }

  void _applyCustomerInfo(CustomerInfo info) {
    // Consider ANY active entitlement or subscription as Premium.
    // (This removes dependency on exact entitlement ids during debugging.)
    final hasAnyEntitlement = info.entitlements.active.isNotEmpty;
    final hasListedEntitlement =
        entitlementIds.any((id) => info.entitlements.active[id] != null);
    final hasSubscription = info.activeSubscriptions.isNotEmpty;

    final premium = hasAnyEntitlement || hasSubscription || hasListedEntitlement;

    if (kDebugMode) {
      // Helpful diagnostics in console
      // ignore: avoid_print
      print('[RC] active entitlements: ${info.entitlements.active.keys.toList()}');
      // ignore: avoid_print
      print('[RC] active subscriptions: ${info.activeSubscriptions}');
      // ignore: avoid_print
      print('[RC] decided premium: $premium');
    }

    final changed = (_isPremium != premium) || _loading;
    _isPremium = premium;
    _loading = false;
    if (changed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: discarded_futures
      forceRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _burstTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
