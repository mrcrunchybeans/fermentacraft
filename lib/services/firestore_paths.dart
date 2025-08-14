// lib/services/firestore_paths.dart
import 'package:cloud_firestore/cloud_firestore.dart';

typedef JsonMap = Map<String, dynamic>;

class FirestorePaths {
  FirestorePaths._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// /users/{uid}
  static DocumentReference<JsonMap> userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// /users/{uid}/{collection}
  static CollectionReference<JsonMap> coll(String uid, String name) =>
      userDoc(uid).collection(name);

  /// /users/{uid}/{collection}/{id}
  static DocumentReference<JsonMap> doc(String uid, String name, String id) =>
      coll(uid, name).doc(id);

  /// ✅ Single settings doc: /users/{uid}/settings/app
  static DocumentReference<JsonMap> settingsDoc(String uid) =>
      userDoc(uid).collection('settings').doc('app');

  /// Optional: /users/{uid}/premium/status
  static DocumentReference<JsonMap> premiumStatusDoc(String uid) =>
      userDoc(uid).collection('premium').doc('status');
}
