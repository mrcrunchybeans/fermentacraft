import 'package:firebase_core/firebase_core.dart';

// Base for ingest endpoints served behind Cloudflare:
// → https://log.fermentacraft.com
String functionsBaseUrl() => 'https://log.fermentacraft.com';

// Optional: original Cloud Functions base (not used by ingest, kept for fallbacks)
// → https://<region>-<projectId>.cloudfunctions.net
String buildFunctionsBaseUrl({String region = 'us-central1'}) {
  final projectId = Firebase.app().options.projectId;
  return 'https://$region-$projectId.cloudfunctions.net';
}

// Optional: Firebase Hosting base if you need it elsewhere
// → https://<projectId>.web.app
String hostingBaseUrl() {
  final projectId = Firebase.app().options.projectId;
  return 'https://$projectId.web.app';
}
