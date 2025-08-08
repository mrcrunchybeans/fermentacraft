import 'package:cloud_firestore/cloud_firestore.dart';

class FirestorePaths {
  static CollectionReference<Map<String, dynamic>> userRoot(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('_root'); // unused marker

  static CollectionReference<Map<String, dynamic>> coll(String uid, String name) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection(name);

  static DocumentReference<Map<String, dynamic>> doc(String uid, String name, String id) =>
      coll(uid, name).doc(id);

  // Special doc for settings
  static DocumentReference<Map<String, dynamic>> settingsDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('settings').doc('app');
}
