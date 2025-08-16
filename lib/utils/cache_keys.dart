class CacheKeys {
  static const prefix = 'fc_';

  static const stripePrices = '${prefix}stripe_prices';
  static const featureGate  = '${prefix}feature_gate';
  static const userState    = '${prefix}user_state';

  static bool hasPrefix(String key) => key.startsWith(prefix);
}
  
