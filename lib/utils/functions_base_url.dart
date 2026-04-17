// lib/utils/functions_base_url.dart
import 'package:firebase_core/firebase_core.dart';

String buildFunctionsBaseUrl({String region = 'us-central1'}) {
  final projectId = Firebase.app().options.projectId;
  return 'https://$region-$projectId.cloudfunctions.net';
}
