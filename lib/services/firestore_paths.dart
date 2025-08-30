// lib/services/firestore_paths.dart
import 'package:cloud_firestore/cloud_firestore.dart';

typedef JsonMap = Map<String, dynamic>;

class FirestorePaths {
  FirestorePaths._();

  static const _colUsers = 'users';
  static const _colDevices = 'devices';
  static const _colBatches = 'batches';
  static const _colMeasurements = 'measurements';
  static const _colRawMeasurements = 'raw_measurements';
  static const _colSettings = 'settings';
  static const _docAppSettings = 'app';
  static const _colPremium = 'premium';
  static const _docPremiumStatus = 'status';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  // /users/{uid}
  static DocumentReference<JsonMap> userDoc(String uid) =>
      _db.collection(_colUsers).doc(uid);

  // /users/{uid}/settings/app
  static DocumentReference<JsonMap> settingsDoc(String uid) =>
      userDoc(uid).collection(_colSettings).doc(_docAppSettings);

  // /users/{uid}/premium/status
  static DocumentReference<JsonMap> premiumStatusDoc(String uid) =>
      userDoc(uid).collection(_colPremium).doc(_docPremiumStatus);

  // /users/{uid}/devices
  static CollectionReference<JsonMap> devicesColl(String uid) =>
      userDoc(uid).collection(_colDevices);

  // /users/{uid}/devices/{deviceId}
  static DocumentReference<JsonMap> deviceDoc(String uid, String deviceId) =>
      devicesColl(uid).doc(deviceId);

  // /users/{uid}/batches/{batchId}
  static DocumentReference<JsonMap> batchDoc(String uid, String batchId) =>
      userDoc(uid).collection(_colBatches).doc(batchId);

  // /users/{uid}/batches/{batchId}/measurements
  static CollectionReference<JsonMap> batchMeasurements(String uid, String batchId) =>
      batchDoc(uid, batchId).collection(_colMeasurements);

  // /users/{uid}/batches/{batchId}/raw_measurements
  static CollectionReference<JsonMap> batchRawMeasurements(String uid, String batchId) =>
      batchDoc(uid, batchId).collection(_colRawMeasurements);

  // Generic helpers (optional, keep if you like them)
  static CollectionReference<JsonMap> coll(String uid, String name) =>
      userDoc(uid).collection(name);
  static DocumentReference<JsonMap> doc(String uid, String name, String id) =>
      coll(uid, name).doc(id);
}
