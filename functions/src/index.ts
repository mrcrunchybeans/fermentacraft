// functions/src/index.ts
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import Stripe from "stripe";
import type { Request, Response } from "express";

setGlobalOptions({ region: "us-central1", timeoutSeconds: 60, memory: "256MiB" });

admin.initializeApp();
const db = admin.firestore();

/* ──────────────────────────────────────────────────────────────────────────
 * Secrets
 * ────────────────────────────────────────────────────────────────────────── */
const STRIPE_SECRET = defineSecret("STRIPE_SECRET");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const RC_SECRET_KEY = defineSecret("RC_SECRET_KEY");

/** Stripe client (created on demand so hot-reload picks up new secrets). */
const stripe = () => new Stripe(STRIPE_SECRET.value(), { apiVersion: "2024-06-20" });

/* ──────────────────────────────────────────────────────────────────────────
 * Constants
 * ────────────────────────────────────────────────────────────────────────── */
const TRIAL_DAYS = 7;
const ENTITLEMENT_ID = "premium";
const USER_DATA_COLLECTIONS = ["tags", "recipes", "batches", "inventory", "shoppingList"] as const;

/* ──────────────────────────────────────────────────────────────────────────
 * Small helpers
 * ────────────────────────────────────────────────────────────────────────── */
const allowCors = (res: Response) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization, Origin");
};

const assertAuthed = (uid?: string): string => {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  return uid;
};

const setPremium = async (
  uid: string,
  active: boolean,
  extra: Record<string, unknown> = {}
) => {
  const ref = db.collection("users").doc(uid).collection("premium").doc("status");
  const now = admin.firestore.FieldValue.serverTimestamp();
  await ref.set({ active, updatedAt: now, ...extra }, { merge: true });
};

function toProductSummary(
  prod: string | Stripe.Product | Stripe.DeletedProduct
): { id: string; name: string } | null {
  if (typeof prod === "string") return null;
  if ("deleted" in prod && prod.deleted) return null;
  return { id: prod.id, name: prod.name };
}

function normalizeEmail(email: string): string {
  const e = email.trim().toLowerCase();
  const m = e.match(/^([^@]+)@(.+)$/);
  if (!m) return e;
  let [, local, domain] = m;
  if (domain === "gmail.com" || domain === "googlemail.com") {
    local = local.split("+")[0].replace(/\./g, "");
  }
  return `${local}@${domain}`;
}

/* ──────────────────────────────────────────────────────────────────────────
 * RevenueCat helpers
 * ────────────────────────────────────────────────────────────────────────── */
type RCMethod = "GET" | "POST" | "DELETE";
async function rcFetchV(
  version: "v2" | "v1",
  path: string,
  init?: RequestInit & { method?: RCMethod }
) {
  const url = `https://api.revenuecat.com/${version}${path}`;
  const r = await fetch(url, {
    method: init?.method ?? "GET",
    ...init,
    headers: {
      Authorization: `Bearer ${RC_SECRET_KEY.value()}`,
      "Content-Type": "application/json",
      Accept: "application/json",
      ...(init?.headers ?? {}),
    },
  });
  return { r, url };
}

/**
 * Grant a promotional entitlement using the RevenueCat v1 API.
 */
async function rcGrantPromo(
  uid: string,
  entitlementId = ENTITLEMENT_ID,
  opts?: { duration?: string; end_time?: string | number | Date; start_time?: string | number | Date }
): Promise<void> {
  const path = `/subscribers/${encodeURIComponent(uid)}/entitlements/${encodeURIComponent(entitlementId)}/promotional`;

  const toMs = (d: string | number | Date) =>
    Math.floor(typeof d === "number" ? d : new Date(d).getTime());

  const body: Record<string, unknown> = {};

  if (opts?.end_time) {
    body.end_time_ms = toMs(opts.end_time);
    if (opts.start_time) body.start_time_ms = toMs(opts.start_time);
  } else if (opts?.duration) {
    // Use RC’s native duration strings (e.g., "weekly", "monthly", "yearly", "lifetime")
    body.duration = opts.duration;
  }

  const { r } = await rcFetchV("v1", path, {
    method: "POST",
    body: Object.keys(body).length ? JSON.stringify(body) : undefined,
  });

  if (r.ok || r.status === 409) return; // 409 = already has an overlapping promo

  const txt = await r.text().catch(() => "");
  logger.error("RC v1 promo failed", { status: r.status, resp: txt });
  throw new HttpsError("internal", `RevenueCat grant failed: ${r.status} ${txt}`);
}



async function rcGetSubscriber(uid: string): Promise<any | null> {
  const r = await rcFetchV("v1", `/subscribers/${encodeURIComponent(uid)}`);
  if (r.r.status === 404) return null;
  if (!r.r.ok) {
    const text = await r.r.text().catch(() => "");
    throw new HttpsError("internal", `RevenueCat GET failed: ${r.r.status} ${text}`);
  }
  return r.r.json();
}

function rcHasActiveEntitlement(sub: any, entitlementId = ENTITLEMENT_ID): boolean {
  try {
    const ent = sub?.subscriber?.entitlements?.[entitlementId];
    if (!ent) return false;
    const expires = ent.expires_date;
    if (expires == null) return true;
    const ts = Date.parse(expires);
    if (Number.isNaN(ts)) return false;
    return ts > Date.now();
  } catch {
    return false;
  }
}

/* ──────────────────────────────────────────────────────────────────────────
 * Stripe Functions
 * ────────────────────────────────────────────────────────────────────────── */
// ... (All your Stripe and other functions remain unchanged) ...
export const createCheckout = onCall({ secrets: [STRIPE_SECRET] }, async (req) => {
  try {
    const uid = assertAuthed(req.auth?.uid);
    const { priceId, successUrl, cancelUrl } = (req.data ?? {}) as {
      priceId?: string; successUrl?: string; cancelUrl?: string;
    };
    if (!priceId || !successUrl || !cancelUrl) {
      throw new HttpsError("invalid-argument", "Missing priceId/successUrl/cancelUrl");
    }
    const s = stripe();
    let price: Stripe.Price;
    try {
      price = await s.prices.retrieve(priceId, { expand: ["product"] });
      if (!price.active) throw new HttpsError("failed-precondition", "Price is inactive");
    } catch (err: any) {
      logger.error("Price lookup failed", { priceId, err: err?.message });
      throw new HttpsError("invalid-argument", `Invalid or mismatched price: ${priceId}`);
    }
    const session = await s.checkout.sessions.create({
      mode: "subscription",
      line_items: [{ price: price.id, quantity: 1 }],
      success_url: `${successUrl}?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: cancelUrl,
      client_reference_id: uid,
      metadata: { uid },
      payment_method_collection: "always",
      subscription_data: {
        metadata: { uid },
        trial_period_days: TRIAL_DAYS,
      },
      allow_promotion_codes: true,
    });
    return { url: session.url };
  } catch (err: any) {
    logger.error("createCheckout error", { message: err?.message, type: err?.type, raw: err });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err?.message ?? "Checkout failed");
  }
});

export const createCheckoutHttp = onRequest(
  { secrets: [STRIPE_SECRET] },
  async (req: Request, res: Response): Promise<void> => {
    allowCors(res);
    if (req.method === "OPTIONS") return void res.status(204).send("");
    try {
      const auth = req.headers.authorization || "";
      if (!auth.startsWith("Bearer ")) return void res.status(401).json({ error: "Missing Authorization header" });
      const idToken = auth.substring(7);
      const decoded = await admin.auth().verifyIdToken(idToken).catch(() => null);
      const uid = assertAuthed(decoded?.uid);
      const { priceId, successUrl, cancelUrl } = (req.body ?? {}) as {
        priceId?: string; successUrl?: string; cancelUrl?: string;
      };
      if (!priceId || !successUrl || !cancelUrl) {
        return void res.status(400).json({ error: "Missing priceId/successUrl/cancelUrl" });
      }
      const s = stripe();
      try {
        const p = await s.prices.retrieve(priceId);
        if (!p.active) return void res.status(412).json({ error: "Price is inactive" });
      } catch (err: any) {
        logger.error("Price lookup failed (HTTP)", { priceId, err: err?.message });
        return void res.status(400).json({ error: `Invalid or mismatched price: ${priceId}` });
      }
      const session = await s.checkout.sessions.create({
        mode: "subscription",
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: `${successUrl}?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: cancelUrl,
        client_reference_id: uid,
        metadata: { uid },
        payment_method_collection: "always",
        subscription_data: {
          metadata: { uid },
          trial_period_days: TRIAL_DAYS,
        },
        allow_promotion_codes: true,
      });
      res.json({ url: session.url });
    } catch (e: any) {
      logger.error("createCheckoutHttp error", e);
      res.status(500).json({ error: e?.message || "Server error" });
    }
  }
);

export const createBillingPortal = onCall({ secrets: [STRIPE_SECRET] }, async (request) => {
  try {
    const uid = assertAuthed(request.auth?.uid);
    const snap = await db.collection("users").doc(uid).collection("premium").doc("status").get();
    const customer = snap.data()?.customer as string | undefined;
    if (!customer) throw new HttpsError("not-found", "No Stripe customer found.");
    const s = stripe();
    const session = await s.billingPortal.sessions.create({
      customer,
      return_url: "https://app.fermentacraft.com/",
    });
    return { url: session.url };
  } catch (err: any) {
    logger.error("createBillingPortal error", { message: err?.message, raw: err });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err?.message ?? "Portal failed");
  }
});

export const getStripePrices = onCall({ secrets: [STRIPE_SECRET] }, async (req) => {
  try {
    assertAuthed(req.auth?.uid);
    const priceIds = (req.data?.priceIds as string[] | undefined)?.filter(Boolean) ?? [];
    if (!priceIds.length) throw new HttpsError("invalid-argument", "priceIds required");
    const s = stripe();
    const items = await Promise.all(priceIds.map((id) => s.prices.retrieve(id, { expand: ["product"] })));
    return {
      prices: items.map((p) => ({
        id: p.id,
        unit_amount: p.unit_amount,
        currency: p.currency,
        interval: p.recurring?.interval ?? null,
        interval_count: p.recurring?.interval_count ?? 1,
        nickname: p.nickname ?? null,
        product: toProductSummary(p.product),
      })),
    };
  } catch (err: any) {
    logger.error("getStripePrices error", { message: err?.message, raw: err });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err?.message ?? "Prices failed");
  }
});

export const getStripePricesHttp = onRequest(
  { secrets: [STRIPE_SECRET] },
  async (req: Request, res: Response): Promise<void> => {
    allowCors(res);
    if (req.method === "OPTIONS") return void res.status(204).send("");
    try {
      const auth = req.headers.authorization || "";
      if (!auth.startsWith("Bearer ")) return void res.status(401).json({ error: "Missing Authorization header" });
      const idToken = auth.substring(7);
      const decoded = await admin.auth().verifyIdToken(idToken).catch(() => null);
      assertAuthed(decoded?.uid);
      const priceIds = (req.body?.priceIds as string[] | undefined)?.filter(Boolean) ?? [];
      if (!priceIds.length) return void res.status(400).json({ error: "priceIds required" });
      const s = stripe();
      const items = await Promise.all(priceIds.map((id) => s.prices.retrieve(id, { expand: ["product"] })));
      res.json({
        prices: items.map((p) => ({
          id: p.id,
          unit_amount: p.unit_amount,
          currency: p.currency,
          interval: p.recurring?.interval ?? null,
          interval_count: p.recurring?.interval_count ?? 1,
          nickname: p.nickname ?? null,
          product: toProductSummary(p.product),
        })),
      });
    } catch (e: any) {
      logger.error("getStripePricesHttp error", e);
      res.status(500).json({ error: e?.message || "Server error" });
    }
  }
);

export const stripeWebhook = onRequest(
  { secrets: [STRIPE_SECRET, STRIPE_WEBHOOK_SECRET] },
  async (req: Request & { rawBody?: Buffer }, res: Response): Promise<void> => {
    const sig = req.headers["stripe-signature"] as string | undefined;
    let event: Stripe.Event;
    try {
      const rawBody = (req as any).rawBody as Buffer;
      const s = stripe();
      event = s.webhooks.constructEvent(rawBody, sig!, STRIPE_WEBHOOK_SECRET.value());
    } catch (err: any) {
      logger.error("Webhook signature verification failed:", err?.message || err);
      res.status(400).send(`Webhook Error: ${err?.message || "invalid signature"}`);
      return;
    }
    try {
      switch (event.type) {
       case "checkout.session.completed": {
  const sess = event.data.object as Stripe.Checkout.Session;
  const uid = (sess.metadata?.uid as string | undefined) ?? null;
  if (!uid) break;

  // If you want to scope specifically to your Pro-Offline price:
  const proOfflinePriceId = "price_1S4n7wE9CXcdIoFtyl8t9cMZ";

  if (sess.mode === "payment") {
    // One-time purchase → Pro-Offline lifetime
    const line = (sess.line_items?.data?.[0] || undefined) as any;
    const priceId = (line?.price?.id as string | undefined) ?? (sess.metadata?.priceId as string | undefined);

    // If you don’t expand line_items, you can skip this check and just set proOffline.
    if (!priceId || priceId === proOfflinePriceId) {
      await db.doc(`users/${uid}/premium/status`).set({
        proOffline: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        source: "stripe",
      }, { merge: true });
    }
  } else {
    // Subscription → Premium
    await db.doc(`users/${uid}/premium/status`).set({
      active: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "stripe",
    }, { merge: true });
  }
  break;
}
case "charge.refunded": {
  const charge = event.data.object as Stripe.Charge;
  const uid = (charge.metadata?.uid as string | undefined) ?? null;
  if (!uid) break;
  await db.doc(`users/${uid}/premium/status`).set({
    proOffline: false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    source: "stripe",
  }, { merge: true });
  break;
}
        case "invoice.payment_succeeded": {
          const inv = event.data.object as Stripe.Invoice;
          const uid = (inv as any)?.subscription_details?.metadata?.uid ?? inv.metadata?.uid ?? null;
          if (uid) {
            const periodEnd = inv.lines?.data?.[0]?.period?.end ?? (inv as any)?.period_end ?? null;
            await setPremium(uid, true, { source: "stripe", currentPeriodEnd: periodEnd });
          }
          break;
        }
        case "customer.subscription.updated": {
          const sub = event.data.object as Stripe.Subscription;
          const uid = sub.metadata?.uid ?? null;
          if (uid) {
            const active = sub.status === "active" || sub.status === "trialing";
            await setPremium(uid, active, {
              source: "stripe",
              cancelAtPeriodEnd: sub.cancel_at_period_end,
              currentPeriodEnd: sub.current_period_end,
              status: sub.status,
            });
          }
          break;
        }
        case "customer.subscription.deleted": {
          const sub = event.data.object as Stripe.Subscription;
          const uid = sub.metadata?.uid ?? null;
          if (uid) {
            await setPremium(uid, false, { source: "stripe", status: sub.status });
          }
          break;
        }
        default:
          break;
      }
      res.json({ received: true });
    } catch (e) {
      logger.error("Webhook handler error:", e);
      res.status(500).send("Webhook handler error");
    }
  }
);

/* ──────────────────────────────────────────────────────────────────────────
 * Unified refresh: check RC → allowlist → grant promo → mirror Firestore
 * ────────────────────────────────────────────────────────────────────────── */
export const syncPremiumFromRC = onCall({ secrets: [RC_SECRET_KEY] }, async (req) => {
  const uid = assertAuthed(req.auth?.uid);
  const email = (req.auth?.token?.email as string | undefined)?.trim().toLowerCase();
  try {
    const sub = await rcGetSubscriber(uid);
    if (sub && rcHasActiveEntitlement(sub, ENTITLEMENT_ID)) {
      await setPremium(uid, true, { source: "rc" });
      return { ok: true, active: true, source: "rc" };
    }
    if (!email) {
      await setPremium(uid, false, { source: "rc" });
      return { ok: true, active: false, source: "rc", reason: "no-email" };
    }
    const exactRef = db.collection("tester_allowlist").doc(email);
    const exactSnap = await exactRef.get();
    const gmailNorm = normalizeEmail(email);
    const normRef = db.collection("tester_allowlist").doc(gmailNorm);
    const normSnap = gmailNorm !== email ? await normRef.get() : null;
    const allowData = exactSnap.exists ? exactSnap.data() : normSnap?.data();
    const isApproved = !!(allowData && (allowData.approved === true || allowData.allowed === true));
    if (!isApproved) {
      await setPremium(uid, false, { source: "rc" });
      return { ok: true, active: false, source: "rc", reason: "not-allowlisted", email, gmailNorm };
    }

    // WORKAROUND: Grant a 100-year promotional instead of "forever" to satisfy the API.
    const expires = new Date();
    expires.setFullYear(expires.getFullYear() + 100);
    await rcGrantPromo(uid, ENTITLEMENT_ID, { end_time: expires });

    const now = admin.firestore.FieldValue.serverTimestamp();
    await db.collection("rc_grants").doc(uid).set(
      { premium: true, at: now, by: "syncPremiumFromRC" },
      { merge: true }
    );
    await setPremium(uid, true, { source: "rc_promo", grantedAt: now });
    return { ok: true, active: true, source: "rc_promo", granted: true, instant: true };
  } catch (err: any) {
    logger.error("syncPremiumFromRC error", { message: err?.message, raw: err });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err?.message ?? "Refresh failed");
  }
});

/* ──────────────────────────────────────────────────────────────────────────
 * Legacy: keep until all clients call syncPremiumFromRC
 * ────────────────────────────────────────────────────────────────────────── */
export const ensureTesterPremium = onCall({ secrets: [RC_SECRET_KEY] }, async (req) => {
  try {
    const uid = assertAuthed(req.auth?.uid);
    const email = (req.auth?.token.email as string | undefined)?.trim().toLowerCase();
    if (!email) throw new HttpsError("failed-precondition", "Email required on account.");
    const exactRef = db.collection("tester_allowlist").doc(email);
    const exactSnap = await exactRef.get();
    const gmailNorm = normalizeEmail(email);
    const normRef = db.collection("tester_allowlist").doc(gmailNorm);
    const normSnap = gmailNorm !== email ? await normRef.get() : null;
    const allowData = exactSnap.exists ? exactSnap.data() : normSnap?.data();
    const isApproved = !!(allowData && (allowData.approved === true || allowData.allowed === true));
    if (!isApproved) {
      logger.warn("ensureTesterPremium: not allowlisted", { uid, email, gmailNorm });
      return { ok: false, reason: "not-allowlisted", email, gmailNorm };
    }
    const grantRef = db.collection("rc_grants").doc(uid);
    const grantSnap = await grantRef.get();
    if (grantSnap.exists && grantSnap.get("premium") === true) {
      await setPremium(uid, true, { source: "rc_promo" });
      return { ok: true, already: true };
    }
    await grantRef.set(
      { premium: true, at: admin.firestore.FieldValue.serverTimestamp(), by: "ensureTesterPremium" },
      { merge: true }
    );
    await setPremium(uid, true, { source: "rc_promo" });
    logger.info("ensureTesterPremium: granted", { uid, email });
    return { ok: true, granted: true };
  } catch (err: any) {
    logger.error("ensureTesterPremium error", { message: err?.message, raw: err });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err?.message ?? "Grant failed");
  }
});

/* ──────────────────────────────────────────────────────────────────────────
 * Scheduled purge of soft-deleted user docs (every 3 days)
 * ────────────────────────────────────────────────────────────────────────── */
async function sweepUserCollection(
  userRef: admin.firestore.DocumentReference,
  coll: (typeof USER_DATA_COLLECTIONS)[number]
): Promise<number> {
  let deleted = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const snap = await userRef.collection(coll)
      .where("_meta.deleted", "==", true)
      .limit(500)
      .get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += snap.size;
    if (snap.size < 500) break;
  }
  return deleted;
}

export const purgeSoftDeletes = onSchedule(
  {
    schedule: "every 72 hours",
    timeZone: "Etc/UTC",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const userRefs = await db.collection("users").listDocuments();
    let totalDeleted = 0;
    for (const userRef of userRefs) {
      for (const coll of USER_DATA_COLLECTIONS) {
        try {
          const n = await sweepUserCollection(userRef, coll);
          if (n > 0) {
            logger.info("purgeSoftDeletes: collection purged", {
              user: userRef.id, collection: coll, deleted: n,
            });
            totalDeleted += n;
          }
        } catch (err: any) {
          logger.error("purgeSoftDeletes: sweep error", {
            user: userRef.id, collection: coll, message: err?.message,
          });
        }
      }
    }
    logger.info("purgeSoftDeletes complete", { totalDeleted, usersScanned: userRefs.length });
  }
);
export { ingestDevice } from "./ingestDevice";
export { ingest } from "./ingest";
