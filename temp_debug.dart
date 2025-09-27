// Add this to your main app widget's initState or a debug page

void debugSyncIssues() {
  // This should be called from within your Flutter app
  Timer.periodic(Duration(seconds: 5), (timer) {
    final sync = FirestoreSyncService.instance;
    final gate = FeatureGate.instance;
    final user = FirebaseAuth.instance.currentUser;
    
    print('🔄 SYNC STATUS CHECK:');
    print('   User: ${user?.email ?? "Not signed in"}');
    print('   Premium: ${gate.premiumActive}');
    print('   Sync Enabled: ${sync.isEnabled}');
    print('   Allow Sync: ${gate.allowSync}');
    
    if (!gate.allowSync) {
      print('   ❌ ISSUE: Premium subscription required for sync');
    }
    
    if (timer.tick > 2) timer.cancel(); // Stop after a few checks
  });
}