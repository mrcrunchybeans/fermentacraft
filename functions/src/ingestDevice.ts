import { onRequest } from "firebase-functions/v2/https";
import type { Request, Response } from "express";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();


// Normalize gravity: if Plato, convert to SG
const platoToSG = (p: number) => 1 + p / (258.6 - ((p / 258.2) * 227.1));

export const ingestDevice = onRequest({ cors: true }, async (req: Request, res: Response) => {
  try {
    // Short query params for device UIs
    const deviceId = (req.query.d as string) || "";
    const uid      = (req.query.u as string) || "";
    const batchId  = (req.query.b as string) || "";
    const k        = (req.query.k as string) || ""; // shared secret

    if (!deviceId || !uid || !batchId || !k) {
      res.status(400).json({ ok: false, error: "missing_params" });
      return;
    }

    // Verify device
    const devRef = db.doc(`users/${uid}/devices/${deviceId}`);
    const devSnap = await devRef.get();
    if (!devSnap.exists) {
      res.status(404).json({ ok: false, error: "device_not_found" });
      return;
    }

    const dev = devSnap.data() as any;
    if (dev.secret !== k) {
      res.status(403).json({ ok: false, error: "bad_secret" });
      return;
    }
    if (dev.linkedBatchId !== batchId) {
      res.status(409).json({ ok: false, error: "device_not_linked_to_batch" });
      return;
    }

    // Parse body (iSpindel/GravityMon HTTP POST JSON)
    const body: any = typeof req.body === "string" ? JSON.parse(req.body) : (req.body || {});
    // gravity (SG or Plato), corr-gravity, temperature (°C typically), angle, battery
    let sg: number | undefined;
    const gformat = String(body["gravity-format"] ?? body.gravityFormat ?? "G").toUpperCase();

    if (body["corr-gravity"] != null) {
      const g = Number(body["corr-gravity"]);
      sg = gformat === "P" ? platoToSG(g) : g;
    } else if (body.gravity != null) {
      const g = Number(body.gravity);
      sg = gformat === "P" ? platoToSG(g) : g;
    }

    const tempC = body.temperature != null ? Number(body.temperature) : undefined;
    if (!sg || !isFinite(sg)) {
      res.status(422).json({ ok: false, error: "bad_gravity" });
      return;
    }

    const now = new Date();

    // Rate limiting / downsampling — compare to last saved
    const stateRef = devRef.collection("_state").doc("ingest");
    const stateSnap = await stateRef.get();
    const state = stateSnap.data() ?? {};
    const lastAt: Date | undefined = state.lastSavedAt?.toDate?.() ?? undefined;
    const lastSg: number | undefined = typeof state.lastSg === "number" ? state.lastSg : undefined;
    const lastTempC: number | undefined = typeof state.lastTempC === "number" ? state.lastTempC : undefined;

    const minMinutes = 10;
    const minSgDelta = 0.0005;
    const minTempDelta = 0.2;

    const minutesSince = lastAt ? (now.getTime() - lastAt.getTime()) / 60000 : Number.POSITIVE_INFINITY;
    const sgDelta = lastSg != null ? Math.abs(sg - lastSg) : Number.POSITIVE_INFINITY;
    const tempDelta = (lastTempC != null && tempC != null) ? Math.abs(tempC - lastTempC) : Number.POSITIVE_INFINITY;

    const shouldSave = minutesSince >= minMinutes || (sgDelta >= minSgDelta || tempDelta >= minTempDelta);

    // Always update device heartbeat
    await devRef.set({
      lastSeen: now,
      lastSg: sg,
      lastTempC: tempC ?? lastTempC ?? null,
    }, { merge: true });

    if (!shouldSave) {
      res.json({ ok: true, saved: false });
      return;
    }

    const measDoc = {
      timestamp: now,
      sg,
      tempC: tempC ?? null,
      source: "device",
      deviceId,
      angle: body.angle != null ? Number(body.angle) : null,
      battery: body.battery != null ? Number(body.battery) : null,
    };

    const base = `users/${uid}/batches/${batchId}`;
    await db.collection(`${base}/measurements`).add(measDoc);    // downsampled stream
    await db.collection(`${base}/raw_measurements`).add({       // optional raw stream
      ...measDoc,
      ttl: now, // mark for Firestore TTL
    });

    await stateRef.set({
      lastSavedAt: now,
      lastSg: sg,
      lastTempC: tempC ?? lastTempC ?? null,
    }, { merge: true });

    res.json({ ok: true, saved: true });
  } catch (e: any) {
    console.error(e);
    res.status(500).json({ ok: false, error: "server", detail: String(e?.message || e) });
  }
});
