import * as functions from "firebase-functions/v2";
import * as admin from "firebase-admin";
import axios from "axios";

const REVENUECAT_API_KEY = functions.defineSecret("REVENUECAT_API_KEY");

admin.initializeApp();
const db = admin.firestore();

/**
 * Cloud Function that triggers when a new document is added
 * to the tester_allowlist collection.
 */
exports.grantRevenueCatEntitlement = functions.firestore.onDocumentCreated({
  document: "tester_allowlist/{docId}",
  secrets: [REVENUECAT_API_KEY],
}, async (event) => {
  const revenueCatApiKey = REVENUECAT_API_KEY.value();

  const email = event.params.docId;
  functions.logger.info(`New email added to allowlist: ${email}`);

  try {
    const usersRef = db.collection("users");
    const userQuery = await usersRef
      .where("email", "==", email)
      .get();

    if (userQuery.empty) {
      functions.logger.warn(`No user found with email: ${email}`);
      return null;
    }

    const userDoc = userQuery.docs[0];
    const firebaseUid = userDoc.id;
    functions.logger.info(
      `Found Firebase UID for email ${email}: ${firebaseUid}`
    );

    const entitlementId = "YOUR_ENTITLEMENT_ID";
    const revenueCatUrl =
      `https://api.revenuecat.com/v1/subscribers/${firebaseUid}` +
      `/entitlements/${entitlementId}/promote`;

    const headers = {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${revenueCatApiKey}`,
    };

    await axios.post(revenueCatUrl, {}, {headers});
    functions.logger.info(
      `Successfully granted entitlement "${entitlementId}" to user ` +
      `with App User ID: ${firebaseUid}`
    );

    return null;
  } catch (error) {
    functions.logger.error("Error granting entitlement:", error);
    return null;
  }
});
