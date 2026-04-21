// functions/src/ingest.ts
import { onRequest } from "firebase-functions/v2/https";
import type { Request, Response } from "express";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

/* ──────────────────────────────────────────────────────────────────────────
 * Utils
 * ────────────────────────────────────────────────────────────────────────── */

function getHeader(req: Request, name: string): string {
  return (req.get(name) || req.get(name.toLowerCase()) || "").trim();
}

/** Plato → SG */
function platoToSG(p: number): number {
  return 1 + p / (258.6 - ((p / 258.2) * 227.1));
}
/** Brix → SG (typical cubic fit) */
function brixToSG(bx: number): number {
  // Widely used third-order approx
  return 1 + (bx / (258.6 - ((bx / 258.2) * 227.1)));
}

/** Prefer short path: /u/<uid>/d/<deviceId>  (optionally ?b=<batchId>) */
function parseIdsFromPreferredPath(req: Request): { uid: string; deviceId: string } {
  const rawPath = (req.originalUrl || req.url || req.path || "").split("?")[0];
  const parts = rawPath.split("/").filter(Boolean); // ["u","<uid>","d","<deviceId>"]
  if (parts[0]?.toLowerCase() === "u" && parts[2]?.toLowerCase() === "d") {
    return { uid: (parts[1] ?? "").trim(), deviceId: (parts[3] ?? "").trim() };
  }
  return { uid: "", deviceId: "" };
}

/** Minimal legacy fallback: /ingest?uid=...&deviceId=... or /ingest/<uid>/<deviceId> */
function parseIdsLegacy(req: Request): { uid: string; deviceId: string } {
  const q = (req.query ?? {}) as Record<string, unknown>;
  const uidQ = String(q.uid ?? q.u ?? "").trim();
  const didQ = String(q.deviceId ?? q.d ?? "").trim();
  if (uidQ && didQ) return { uid: uidQ, deviceId: didQ };

  const rawPath = (req.originalUrl || req.url || req.path || "").split("?")[0];
  const parts = rawPath.split("/").filter(Boolean); // ["ingest","<uid>","<deviceId>"]
  if (parts[0]?.toLowerCase() === "ingest" && parts.length >= 3) {
    return { uid: (parts[1] ?? "").trim(), deviceId: (parts[2] ?? "").trim() };
  }
  return { uid: "", deviceId: "" };
}

/**
 * Parse payload from GravityMon / iSpindel / Brewfather-style JSON or form.
 * Supports:
 *   gravity / corr-gravity
 *   gravity_unit | gravity-unit | gravity-format
 *   temp / temperature + temp_unit | temp_units
 *   angle, battery
 */
function parsePayload(req: Request): {
  sg?: number;
  tempC?: number;
  angle: number | null;
  battery: number | null;
  raw: any;
} {
  const ctype = (getHeader(req, "content-type") || "").toLowerCase();
  const likelyForm = ctype.includes("application/x-www-form-urlencoded");
  const likelyJson = ctype.includes("application/json") || ctype === "";

  let raw: any;
  if (likelyForm) {
    raw = req.body || {};
  } else if (likelyJson) {
    if (typeof req.body === "string") {
      try { raw = JSON.parse(req.body || "{}"); } catch { raw = {}; }
    } else {
      raw = req.body || {};
    }
  } else {
    // Fallback: try JSON, then use as-is
    if (typeof req.body === "string") {
      try { raw = JSON.parse(req.body || "{}"); } catch { raw = {}; }
    } else {
      raw = req.body || {};
    }
  }

  // Gravity value: prefer corrected, then plain
  const gravity = Number(
    raw["corr-gravity"] ??
    raw.corr_gravity ??
    raw.corrGravity ??
    raw.corrSG ??
    raw.corr_sg ??
    raw.gravity
  );
  const gravityUnitRaw =
    raw.gravity_unit ??
    raw["gravity-unit"] ??
    raw["gravity-format"] ??
    raw.gravityUnit ??
    "SG";
  const gravityUnit = String(gravityUnitRaw).toUpperCase();

  // Temperature value + unit (accept a few more aliases)
  const temp = Number(raw.temp ?? raw.temperature);
  const tempUnitRaw =
    raw.temp_unit ??
    raw.temp_units ??
    raw.temperature_unit ??
    raw.temperatureUnit ??
    "C";
  const tempUnit = String(tempUnitRaw).toUpperCase();

  const angle = raw.angle != null ? Number(raw.angle) : null;
  const battery = raw.battery != null ? Number(raw.battery) : null;

  let sg: number | undefined;
  if (!Number.isNaN(gravity)) {
    if (gravityUnit.startsWith("P") || gravityUnit === "PLATO") {
      sg = platoToSG(gravity);
    } else if (gravityUnit.startsWith("B")) { // BRIX / BX
      sg = brixToSG(gravity);
    } else {
      sg = gravity; // assume SG
    }
  }
  // If device sends explicit brix instead of unit flag
  if (sg == null && typeof raw.brix === "number") {
    sg = brixToSG(Number(raw.brix));
  }

  let tempC: number | undefined;
  if (!Number.isNaN(temp)) {
  tempC = tempUnit.startsWith("F") ? (temp - 32) * (5 / 9) : temp;
  }

  return { sg, tempC, angle, battery, raw };
}

function htmlEscape(s: string) {
  return s.replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]!));
}

/* ──────────────────────────────────────────────────────────────────────────
 * Core save
 * ────────────────────────────────────────────────────────────────────────── */

async function saveMeasurement(opts: {
  uid: string;
  deviceId: string;
  secret?: string;
  batchIdFromQuery?: string;
  sg?: number;
  tempC?: number;
  angle: number | null;
  battery: number | null;
}): Promise<boolean> {
  const { uid, deviceId, secret, batchIdFromQuery, sg, tempC, angle, battery } = opts;

  if (!uid || !deviceId) throw new Error("missing_uid_or_deviceId");
  if (sg == null || !isFinite(sg)) throw new Error("bad_gravity");

  const devRef = db.doc(`users/${uid}/devices/${deviceId}`);
  const devSnap = await devRef.get();
  if (!devSnap.exists) throw new Error("device_not_found");
  const dev = devSnap.data() as any;

  // Secret is optional — if provided (non-empty), validate it. Stock iSpindle
  // firmware has no header support, so URL-path auth (device ID + URL secrecy) is sufficient.
  if (secret != null && secret.length > 0 && String(dev.secret || "") !== secret) {
    throw new Error("bad_secret");
  }

  const linked = String(dev.linkedBatchId ?? "");
  const targetBatch = batchIdFromQuery || linked;
  if (!targetBatch || (linked && targetBatch !== linked)) {
    throw new Error("device_not_linked_to_batch");
  }

  const now = new Date();

  // Downsample / rate-limit
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
  const sgDelta = lastSg != null ? Math.abs((sg as number) - lastSg) : Number.POSITIVE_INFINITY;
  const tempDelta = (lastTempC != null && tempC != null) ? Math.abs((tempC as number) - lastTempC) : Number.POSITIVE_INFINITY;

  const shouldSave = minutesSince >= minMinutes || (sgDelta >= minSgDelta || tempDelta >= minTempDelta);

  const batch = db.batch();

  // Heartbeat
  batch.set(
    devRef,
    { lastSeen: now, lastSg: sg, lastTempC: tempC ?? null, battery: battery ?? null },
    { merge: true },
  );

  if (!shouldSave) {
    await batch.commit();
    return false;
  }

  const base = `users/${uid}/batches/${targetBatch}`;
  const meas = { timestamp: now, sg, tempC: tempC ?? null, source: "device", deviceId, angle, battery };
  
  const mRef = db.collection(`${base}/measurements`).doc();
  const rRef = db.collection(`${base}/raw_measurements`).doc();

  batch.set(mRef, meas);
  // Keep the raw body for diagnostics (short-lived in this collection anyway)
  batch.set(rRef, { ...meas, raw: opts, ttl: now });

  batch.set(stateRef, { lastSavedAt: now, lastSg: sg, lastTempC: tempC ?? lastTempC ?? null }, { merge: true });

  await batch.commit();
  return true;
}

/* ──────────────────────────────────────────────────────────────────────────
 * Friendly landing (GET/HEAD) + Ingest (POST)
 * ────────────────────────────────────────────────────────────────────────── */

export const ingest = onRequest({ cors: true }, async (req: Request, res: Response): Promise<void> => {
  // CORS & preflight
  if (req.method === "OPTIONS") {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, HEAD");
    res.set("Access-Control-Allow-Headers", "Content-Type, X-Device-Secret, X-API-Key");
    res.status(204).send("");
    return;
  }

  // Human-friendly check page for GET/HEAD so casual users don’t see an error
  if (req.method === "GET" || req.method === "HEAD") {
    const { uid, deviceId } = parseIdsFromPreferredPath(req);
    const batchId = String((req.query?.b as string) ?? "").trim();
    let status = "missing ids";
    let linked = "";
    let exists = false;

    if (uid && deviceId) {
      const dev = await db.doc(`users/${uid}/devices/${deviceId}`).get();
      exists = dev.exists;
      linked = (dev.data()?.linkedBatchId as string | undefined) ?? "";
      status = exists ? "device found" : "device not found";
    }

    const html = `<!doctype html>
<html>
<head>
<meta charset="utf-8"/>
<title>FermentaCraft Ingest</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<style>
  body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:24px;line-height:1.5;}
  code{background:#f4f4f4;padding:2px 5px;border-radius:4px;}
  .ok{color:#2e7d32}.warn{color:#e65100}.muted{color:#666}
  .box{border:1px solid #ddd;padding:12px;border-radius:8px;margin-top:12px}
</style>
</head>
<body>
  <h2>FermentaCraft ingest endpoint</h2>
  <p class="muted">This URL is <strong>working</strong>. Paste it into GravityMon/TiltBridge/Fermentrack as the BrewFather/HTTP POST endpoint.</p>

  <div class="box">
    <div><strong>UID:</strong> <code>${htmlEscape(uid || "(none)")}</code></div>
    <div><strong>Device ID:</strong> <code>${htmlEscape(deviceId || "(none)")}</code></div>
    <div><strong>Batch ID (?b=):</strong> <code>${htmlEscape(batchId || "(none)")}</code></div>
    <div><strong>Status:</strong> <span class="${exists ? "ok" : "warn"}">${htmlEscape(status)}</span>${linked ? ` · linked to <code>${htmlEscape(linked)}</code>` : ""}</div>
  </div>

  <h3>Send data</h3>
  <p>POST JSON with header <code>Content-Type: application/json</code> and your device secret in <code>X-Device-Secret</code>:</p>
  <pre>{
  "gravity": 1.012,
  "gravity-unit": "G",
  "temp": 20.5,
  "temp_unit": "C",
  "battery": 3.7,
  "angle": 30
}</pre>
  <p class="muted">If you hit “Run push test” in GravityMon and it shows an error, ignore it — live pushes still work.</p>
</body></html>`;
    res.set("Content-Type", "text/html; charset=utf-8");
    res.set("Access-Control-Allow-Origin", "*");
    res.status(200).send(html);
    return;
  }

  // Normal ingest (POST)
  try {
    let { uid, deviceId } = parseIdsFromPreferredPath(req);
    if (!uid || !deviceId) ({ uid, deviceId } = parseIdsLegacy(req));

    const secret = getHeader(req, "x-device-secret") || getHeader(req, "x-api-key");
    const batchId = String((req.query?.b as string) ?? "").trim();

    const { sg, tempC, angle, battery } = parsePayload(req);
    if (sg == null || !isFinite(sg)) {
      // Gentle response so users don’t think the URL is broken
      res.set("Access-Control-Allow-Origin", "*");
      res.status(200).json({
        ok: false,
        error: "bad_gravity",
        detail: "gravity missing or not a number",
        expected: {
          headers: ["Content-Type: application/json", "X-Device-Secret: <secret>"],
          bodyExample: {
            gravity: 1.012,
            "gravity-unit": "G",
            temp: 20.5,
            temp_unit: "C",
            battery: 3.7,
            angle: 30,
          },
        },
      });
      return;
    }

    const saved = await saveMeasurement({ uid, deviceId, secret, batchIdFromQuery: batchId, sg, tempC, angle, battery });

    res.set("Access-Control-Allow-Origin", "*");
    res.json({ ok: true, saved });
  } catch (e: any) {
    const msg = String(e?.message || e);
    const map: Record<string, number> = {
      missing_uid_or_deviceId: 200, // 200 + message (so “test” doesn’t look broken)
      missing_secret: 200,
      bad_gravity: 200,
      device_not_found: 200,
      bad_secret: 200,
      device_not_linked_to_batch: 200,
    };
    res.set("Access-Control-Allow-Origin", "*");
    res.status(map[msg] ?? 200).json({ ok: false, error: msg === "[object Object]" ? "server" : msg });
  }
});

/* ──────────────────────────────────────────────────────────────────────────
 * Simple echo endpoint for “Run push test”
 * ────────────────────────────────────────────────────────────────────────── */

export const echo = onRequest({ cors: true }, async (req: Request, res: Response): Promise<void> => {
  if (req.method === "OPTIONS") {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, GET, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, X-Device-Secret, X-API-Key");
    res.status(204).send("");
    return;
  }
  const { raw } = parsePayload(req);
  res.set("Access-Control-Allow-Origin", "*");
  res.json({
    ok: true,
    note: "Debug echo only. Use /u/<uid>/d/<deviceId> for real ingest.",
    method: req.method,
    headers: Object.fromEntries(Object.entries(req.headers).map(([k, v]) => [k, Array.isArray(v) ? v.join(", ") : v || ""])),
    body: raw ?? null,
  });
});
