import 'package:cloud_firestore/cloud_firestore.dart';
import '../pages/devices_page.dart'; // for DeviceLite & DevicesRepo

class FirestoreDevicesRepo implements DevicesRepo {
  final String uid;
  FirestoreDevicesRepo(this.uid);

  CollectionReference<Map<String, dynamic>> get _coll =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('devices');

  @override
  Future<List<DeviceLite>> listDevices() async {
    final qs = await _coll.get();
    return qs.docs.map((d) {
      final m = d.data();
      return DeviceLite(
        id: d.id,
        name: (m['name'] as String?) ?? 'Device',
        assignedBatchName: m['linkedBatchName'] as String?, // optional; store if you want
        lastReadingAt: (m['lastSeen'] as Timestamp?)?.toDate(),
        endpointUrl: m['endpointUrl'] as String?,
        online: _isOnline((m['lastSeen'] as Timestamp?)?.toDate()),
      );
    }).toList();
  }

  bool _isOnline(DateTime? lastSeen) {
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen) <= const Duration(minutes: 10);
  }

  @override
  Future<void> addDevice({required String name, String? endpointUrl}) async {
    await _coll.add({
      'name': name,
      if (endpointUrl != null) 'endpointUrl': endpointUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> renameDevice(String deviceId, String newName) {
    return _coll.doc(deviceId).update({'name': newName});
  }

  @override
  Future<void> deleteDevice(String deviceId) {
    return _coll.doc(deviceId).delete();
  }

  @override
  Future<void> testPing(String deviceId) async {
    // Whatever your device listens for; here we just set a field the device could observe.
    await _coll.doc(deviceId).update({'testPingAt': FieldValue.serverTimestamp()});
  }

  @override
  Future<void> calibrate(String deviceId) async {
    // Stub—integrate with your calibrate flow if you have one.
    await _coll.doc(deviceId).update({'calibrateRequestedAt': FieldValue.serverTimestamp()});
  }
}
