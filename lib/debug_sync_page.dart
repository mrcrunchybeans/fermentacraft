// Debug sync download issues
// Add this to your app temporarily to diagnose the sync issue

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fermentacraft/services/firestore_sync_service.dart';
import 'package:fermentacraft/services/feature_gate.dart';
import 'package:fermentacraft/services/firestore_paths.dart';
import 'package:fermentacraft/services/firestore_user.dart';

class SyncDebugPage extends StatefulWidget {
  const SyncDebugPage({Key? key}) : super(key: key);

  @override
  State<SyncDebugPage> createState() => _SyncDebugPageState();
}

class _SyncDebugPageState extends State<SyncDebugPage> {
  final List<String> _logs = [];
  bool _testing = false;

  void _log(String message) {
    print('🔍 SYNC DEBUG: $message');
    setState(() {
      _logs.add('${DateTime.now().toIso8601String().substring(11, 19)}: $message');
    });
  }

  Future<void> _testSyncFlow() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _logs.clear();
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      final sync = FirestoreSyncService.instance;
      final gate = FeatureGate.instance;

      _log('=== SYNC DEBUG TEST ===');
      _log('User: ${user?.email ?? "NOT SIGNED IN"}');
      _log('UID: ${user?.uid ?? "null"}');
      _log('Allow Sync: ${gate.allowSync}');
      _log('Sync Enabled: ${sync.isEnabled}');

      if (user == null) {
        _log('❌ STOPPED: No user signed in');
        return;
      }

      if (!gate.allowSync) {
        _log('❌ STOPPED: Premium required for sync');
        return;
      }

      _log('✅ Prerequisites met, testing sync...');

      // Test 1: Can we ensure user doc?
      try {
        await FirestoreUser.instance.ensureUserDoc();
        _log('✅ User document ensured');
      } catch (e) {
        _log('❌ User document failed: $e');
        return;
      }

      // Test 2: Can we read from Firestore?
      try {
        final boxNames = ['batches', 'recipes', 'inventory', 'tags', 'shoppingList'];
        for (final boxName in boxNames) {
          _log('📥 Testing download for: $boxName');
          final snap = await FirestorePaths.coll(user.uid, boxName).get();
          _log('   Found ${snap.docs.length} documents in $boxName');
          
          if (snap.docs.isNotEmpty) {
            _log('   Sample doc: ${snap.docs.first.id}');
          }
        }
      } catch (e) {
        _log('❌ Firestore read failed: $e');
        return;
      }

      // Test 3: Try actual force sync
      _log('🔄 Running forceSync()...');
      try {
        await sync.forceSync();
        _log('✅ forceSync() completed');
      } catch (e) {
        _log('❌ forceSync() failed: $e');
      }

    } catch (e) {
      _log('❌ Unexpected error: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync Debug')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _testing ? null : _testSyncFlow,
              child: Text(_testing ? 'Testing...' : 'Test Sync Flow'),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                final isError = log.contains('❌');
                final isSuccess = log.contains('✅');
                
                return Container(
                  padding: const EdgeInsets.all(8.0),
                  margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: isError 
                        ? Colors.red.withOpacity(0.1)
                        : isSuccess 
                          ? Colors.green.withOpacity(0.1)
                          : null,
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: Text(
                    log,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: isError ? Colors.red : isSuccess ? Colors.green : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}