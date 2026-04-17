import { onDocumentCreated, FirestoreEvent } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import type { DocumentSnapshot } from "firebase-admin/firestore";

/**
 * GA4 Measurement Protocol events for app engagement optimization.
 *
 * SETUP:
 * 1. Get your GA4 Measurement ID (G-XXXXXXXX) from Firebase Console → Analytics → Data Attribution
 * 2. Create API secret in GA4 Admin → Data Streams → Measurement Protocol → Create
 * 3. Secrets are stored in .secrets/.env and accessed via defineSecret
 */

const GA4_MEASUREMENT_ID = defineSecret("GA_MEASUREMENT_ID");
const GA4_API_SECRET = defineSecret("GA_API_SECRET");

interface GA4EventPayload {
  client_id: string;
  user_id?: string;
  events: Array<{
    name: string;
    params: Record<string, string | number>;
  }>;
}

/**
 * Fire a GA4 event via Measurement Protocol API.
 * Uses Firebase UID as client_id for cross-session tracking.
 */
async function fireGA4Event(
  userId: string,
  eventName: string,
  params: Record<string, string | number> = {}
): Promise<void> {
  const measurementId = GA4_MEASUREMENT_ID.value();
  const apiSecret = GA4_API_SECRET.value();

  // Skip if not configured
  if (measurementId === "G-XXXXXXXXXX" || apiSecret === "YOUR_API_SECRET_HERE") {
    logger.warn("GA4 not configured - skipping event", { eventName, userId });
    return;
  }

  const payload: GA4EventPayload = {
    client_id: userId, // Firebase UID as client_id
    user_id: userId,
    events: [
      {
        name: eventName,
        params: {
          ...params,
          engagement_time_msec: 100,
          firebase_origin: "cloud_function",
        },
      },
    ],
  };

  const url = `https://www.google-analytics.com/mp/collect?measurement_id=${measurementId}&api_secret=${apiSecret}`;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text().catch(() => "unknown error");
      logger.error("GA4 Measurement Protocol error", {
        status: response.status,
        error: errorText,
        eventName,
        userId,
      });
      return;
    }

    logger.info(`GA4 event fired: ${eventName}`, { userId, params });
  } catch (err) {
    logger.error("GA4 fetch failed", { eventName, userId, error: String(err) });
  }
}

/**
 * Fire on recipe creation.
 * Key event for Google Ads optimization (engaged users who create recipes).
 */
export const onRecipeCreated = onDocumentCreated(
  "users/{uid}/recipes/{recipeId}",
  async (event: FirestoreEvent<DocumentSnapshot | undefined, { uid: string; recipeId: string }>) => {
    if (!event.data) {
      logger.warn("onRecipeCreated: no data");
      return;
    }

    const uid = event.params.uid;
    const recipeId = event.data.id;
    const recipeData = event.data.data();

    await fireGA4Event(uid, "create_recipe", {
      recipe_id: recipeId,
      recipe_type: recipeData?.recipeType ?? "unknown",
      has_ingredients: recipeData?.ingredients != null ? "true" : "false",
    });

    logger.info("Recipe creation tracked", { uid, recipeId });
  }
);

/**
 * Fire on batch creation.
 * Key event for Google Ads optimization (engaged users who start batches).
 */
export const onBatchCreated = onDocumentCreated(
  "users/{uid}/batches/{batchId}",
  async (event: FirestoreEvent<DocumentSnapshot | undefined, { uid: string; batchId: string }>) => {
    if (!event.data) {
      logger.warn("onBatchCreated: no data");
      return;
    }

    const uid = event.params.uid;
    const batchId = event.data.id;
    const batchData = event.data.data();

    await fireGA4Event(uid, "create_batch", {
      batch_id: batchId,
      batch_type: batchData?.type ?? "unknown",
      recipe_id: batchData?.recipeId ?? "none",
    });

    logger.info("Batch creation tracked", { uid, batchId });
  }
);

/**
 * Fire on first device linked to a batch.
 * Signal of deeper app engagement (hardware setup).
 */
export const onDeviceLinked = onDocumentCreated(
  "users/{uid}/batches/{batchId}/linked_devices/{deviceId}",
  async (event: FirestoreEvent<DocumentSnapshot | undefined, { uid: string; batchId: string; deviceId: string }>) => {
    if (!event.data) return;

    const uid = event.params.uid;
    const batchId = event.params.batchId;

    await fireGA4Event(uid, "link_device", {
      batch_id: batchId,
      device_id: event.data.id,
    });

    logger.info("Device link tracked", { uid, batchId });
  }
);