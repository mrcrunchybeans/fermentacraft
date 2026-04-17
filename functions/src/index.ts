// functions/src/index.ts
/* eslint-disable @typescript-eslint/no-explicit-any */

import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import Stripe from "stripe";
import type { Request, Response } from "express";

/* ──────────────────────────────────────────────────────────────────────────
 * Global Functions Config
 * ────────────────────────────────────────────────────────────────────────── */
setGlobalOptions({ region: "us-central1", timeoutSeconds: 60, memory: "256MiB" });

/* ──────────────────────────────────────────────────────────────────────────
 * Firebase Admin Init
 * ────────────────────────────────────────────────────────────────────────── */
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

/* ──────────────────────────────────────────────────────────────────────────
 * Secrets
 * ────────────────────────────────────────────────────────────────────────── */
const STRIPE_SECRET = defineSecret("STRIPE_SECRET");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const RC_SECRET_KEY = defineSecret("RC_SECRET_KEY");

/** Lazily constructed Stripe client (picks up rotated secrets). */
const stripe = () => new Stripe(STRIPE_SECRET.value(), { apiVersion: "2024-06-20" });

/* ──────────────────────────────────────────────────────────────────────────
 * Constants
 * ────────────────────────────────────────────────────────────────────────── */
const TRIAL_DAYS = 7; // Subscription trial (Premium)
const ENTITLEMENT_ID = "premium"; // RevenueCat entitlement
const OFFLINE_PRO_PRICE_ID = "price_1S4n7wE9CXcdIoFtyl8t9cMZ"; // One-time price for Offline-Pro

const USER_DATA_COLLECTIONS = [
  "tags",
  "recipes",
  "batches",
  "inventory",
  "shoppingList",
] as const;

/* ──────────────────────────────────────────────────────────────────────────
 * Helpers
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

const serverNow = () => admin.firestore.FieldValue.serverTimestamp();

const setPremiumStatusDoc = async (uid: string, data: Record<string, unknown>) => {
  await db.doc(`users/${uid}/premium/status`).set(
    { updatedAt: serverNow(), ...data },
    { merge: true }
  );
};

const setPremium = async (uid: string, active: boolean, extra: Record<string, unknown> = {}) =>
  setPremiumStatusDoc(uid, { active, ...extra });

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

/** Verify Firebase ID token from `Authorization: Bearer <token>` header. */
async function verifyFirebaseToken(authorization?: string): Promise<string> {
  if (!authorization?.startsWith("Bearer ")) {
    throw new Error("Missing or invalid Authorization header");
  }
  const idToken = authorization.substring("Bearer ".length);
  const decoded = await admin.auth().verifyIdToken(idToken);
  return decoded.uid;
}

/* ──────────────────────────────────────────────────────────────────────────
 * RevenueCat Helpers
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

async function rcGrantPromo(
  uid: string,
  entitlementId = ENTITLEMENT_ID,
  opts?: { duration?: string; end_time?: string | number | Date; start_time?: string | number | Date }
): Promise<void> {
  const path = `/subscribers/${encodeURIComponent(uid)}/entitlements/${encodeURIComponent(
    entitlementId
  )}/promotional`;
  const toISO = (d: string | number | Date) => new Date(d).toISOString();

  const body: Record<string, unknown> = {};
  // Use != null to allow end_time=0 as a valid value (falsy check would reject 0)
  if (opts?.end_time != null) {
    body.expires_at = toISO(opts.end_time);
    if (opts.start_time != null) body.starts_at = toISO(opts.start_time);
  } else if (opts?.duration) {
    body.duration = opts.duration; // "weekly" | "monthly" | "yearly" | "lifetime"
  }

  logger.info("RC promo request", {
    url: `https://api.revenuecat.com/v1${path}`,
    method: "POST",
    body,
  });

  const { r } = await rcFetchV("v1", path, {
    method: "POST",
    body: Object.keys(body).length ? JSON.stringify(body) : undefined,
  });

  if (r.ok || r.status === 409) return; // 409 = already granted overlapping promo
  const txt = await r.text().catch(() => "");
  logger.error("RC v1 promo failed", { status: r.status, resp: txt });
  throw new HttpsError("internal", `RevenueCat grant failed: ${r.status} ${txt}`);
}

async function rcGetSubscriber(uid: string): Promise<any | null> {
  const { r } = await rcFetchV("v1", `/subscribers/${encodeURIComponent(uid)}`);
  if (r.status === 404) return null;
  if (!r.ok) {
    const text = await r.text().catch(() => "");
    throw new HttpsError("internal", `RevenueCat GET failed: ${r.status} ${text}`);
  }
  return r.json();
}

function rcHasActiveEntitlement(sub: any, entitlementId = ENTITLEMENT_ID): boolean {
  try {
    const ent = sub?.subscriber?.entitlements?.[entitlementId];
    if (!ent) return false;
    const expires = ent.expires_date;
    if (expires == null) return true; // no expiry ⇒ lifetime
    const ts = Date.parse(expires);
    if (Number.isNaN(ts)) return false;
    return ts > Date.now();
  } catch {
    return false;
  }
}

/* ──────────────────────────────────────────────────────────────────────────
 * Stripe: Checkout (Auto-detect mode by Price)
 *  - If Price.recurring exists => subscription (Premium)
 *  - Else => one-time payment (Offline-Pro)
 * ────────────────────────────────────────────────────────────────────────── */
type CheckoutPayload = {
  priceId?: string;
  successUrl?: string;
  cancelUrl?: string;
};

const missingArgs = "Missing priceId/successUrl/cancelUrl";

/** Callable version (from client SDKs). */
export const createCheckout = onCall({ secrets: [STRIPE_SECRET] }, async (req) => {
  try {
    const uid = assertAuthed(req.auth?.uid);
    const { priceId, successUrl, cancelUrl } = (req.data ?? {}) as CheckoutPayload;
    if (!priceId || !successUrl || !cancelUrl) {
      throw new HttpsError("invalid-argument", missingArgs);
    }

    const s = stripe();
    const price = await s.prices.retrieve(priceId, { expand: ["product"] });
    if (!price.active) throw new HttpsError("failed-precondition", "Price is inactive");

    const isSubscription = !!price.recurring;

    const session = await s.checkout.sessions.create({
      mode: isSubscription ? "subscription" : "payment",
      line_items: [{ price: price.id, quantity: 1 }],
      success_url: `${successUrl}?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: cancelUrl,
      client_reference_id: uid,
      metadata: { uid, priceId },
      allow_promotion_codes: true,
      // ⚠️ Only for subscriptions:
      ...(isSubscription ? ({ payment_method_collection: "always" as const }) : {}),
      ...(isSubscription
        ? {
            subscription_data: {
              metadata: { uid },
              trial_period_days: TRIAL_DAYS,
            },
          }
        : {}),
    });

    return { url: session.url };
  } catch (err: any) {
    logger.error("createCheckout error", { message: err?.message, type: err?.type, raw: err });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err?.message ?? "Checkout failed");
  }
});

/** HTTP version (with Firebase ID token in Authorization header). */
export const createCheckoutHttp = onRequest(
  { secrets: [STRIPE_SECRET] },
  async (req: Request, res: Response): Promise<void> => {
    allowCors(res);
    if (req.method === "OPTIONS") return void res.status(204).send("");

    try {
      const auth = req.headers.authorization || "";
      if (!auth.startsWith("Bearer ")) {
        return void res.status(401).json({ error: "Missing Authorization header" });
      }
      const idToken = auth.substring(7);
      const decoded = await admin.auth().verifyIdToken(idToken).catch(() => null);
      const uid = assertAuthed(decoded?.uid);

      const { priceId, successUrl, cancelUrl } = (req.body ?? {}) as CheckoutPayload;
      if (!priceId || !successUrl || !cancelUrl) {
        return void res.status(400).json({ error: missingArgs });
      }

      const s = stripe();
      const price = await s.prices.retrieve(priceId, { expand: ["product"] });
      if (!price.active) return void res.status(412).json({ error: "Price is inactive" });

      const isSubscription = !!price.recurring;

      const session = await s.checkout.sessions.create({
        mode: isSubscription ? "subscription" : "payment",
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: `${successUrl}?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: cancelUrl,
        client_reference_id: uid,
        metadata: { uid, priceId },
        allow_promotion_codes: true,
        // ⚠️ Only for subscriptions:
        ...(isSubscription ? ({ payment_method_collection: "always" as const }) : {}),
        ...(isSubscription
          ? {
              subscription_data: {
                metadata: { uid },
                trial_period_days: TRIAL_DAYS,
              },
            }
          : {}),
      });

      res.json({ url: session.url });
    } catch (e: any) {
      logger.error("createCheckoutHttp error", e);
      res.status(500).json({ error: e?.message || "Server error" });
    }
  }
);

/* ──────────────────────────────────────────────────────────────────────────
 * Stripe: (Optional) Explicit one-time checkout endpoint
 * ────────────────────────────────────────────────────────────────────────── */
export const createOneTimeCheckout = onRequest(
  { secrets: [STRIPE_SECRET], region: "us-central1" },
  async (req: Request, res: Response): Promise<void> => {
    allowCors(res);
    if (req.method === "OPTIONS") return void res.status(204).send("");
    try {
      if (req.method !== "POST") return void res.status(405).send("Method Not Allowed");

      const uid = await verifyFirebaseToken(req.headers.authorization);
      const { priceId, successUrl, cancelUrl } = (req.body ?? {}) as {
        priceId?: string;
        successUrl?: string;
        cancelUrl?: string;
      };

      if (!priceId) return void res.status(400).json({ error: "Missing priceId" });

      const s = stripe();
      const session = await s.checkout.sessions.create({
        mode: "payment", // one-time
        line_items: [{ price: priceId, quantity: 1 }],
        success_url:
          (successUrl ?? "https://fermentacraft.com/checkout-success") +
          "?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: cancelUrl ?? "https://fermentacraft.com/checkout-cancel",
        client_reference_id: uid,
        metadata: { uid, priceId },
        allow_promotion_codes: true,
        billing_address_collection: "auto",
        // ⛔️ Do NOT add payment_method_collection here (one-time payments)
        // ⛔️ Do NOT add subscription_data here (this is NOT a subscription)
      });

      res.json({ url: session.url });
    } catch (err: any) {
      logger.error("createOneTimeCheckout error", err);
      res.status(400).json({ error: err.message || "Unknown error" });
    }
  }
);

/* ──────────────────────────────────────────────────────────────────────────
 * Stripe: Billing Portal (subscriptions)
 * ────────────────────────────────────────────────────────────────────────── */
export const createBillingPortal = onCall({ secrets: [STRIPE_SECRET] }, async (request) => {
  try {
    const uid = assertAuthed(request.auth?.uid);
    const snap = await db.doc(`users/${uid}/premium/status`).get();
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

/* ──────────────────────────────────────────────────────────────────────────
 * Stripe: Price fetchers
 * ────────────────────────────────────────────────────────────────────────── */
export const getStripePrices = onCall({ secrets: [STRIPE_SECRET] }, async (req) => {
  try {
    assertAuthed(req.auth?.uid);
    const priceIds = (req.data?.priceIds as string[] | undefined)?.filter(Boolean) ?? [];
    if (!priceIds.length) throw new HttpsError("invalid-argument", "priceIds required");
    const s = stripe();
    const items = await Promise.all(
      priceIds.map((id) => s.prices.retrieve(id, { expand: ["product"] }))
    );
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
      const items = await Promise.all(
        priceIds.map((id) => s.prices.retrieve(id, { expand: ["product"] }))
      );
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

/* ──────────────────────────────────────────────────────────────────────────
 * Stripe: Webhook
 *  - Grants Offline-Pro on one-time payment (mode: "payment")
 *  - Mirrors subscription status for Premium
 * ────────────────────────────────────────────────────────────────────────── */
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
          const s = stripe();
          const base = event.data.object as Stripe.Checkout.Session;
          // Expand price to reliably read price id(s)
          const sess = await s.checkout.sessions.retrieve(base.id, {
            expand: ["line_items.data.price"],
          });

          const uid = (sess.metadata?.uid as string | undefined) ?? null;
          if (!uid) break;

          if (sess.mode === "payment") {
            // One-time purchase ⇒ Offline-Pro
            const linePriceId = sess.line_items?.data?.[0]?.price?.id;
            if (!linePriceId || linePriceId === OFFLINE_PRO_PRICE_ID) {
              await setPremiumStatusDoc(uid, {
                proOffline: true,
                source: "stripe",
                lastStripeCheckoutId: sess.id,
              });
              logger.info("Offline-Pro granted", { uid, session: sess.id });
            }
          } else {
            // Subscription ⇒ Premium active
            await setPremium(uid, true, {
              source: "stripe",
              lastStripeCheckoutId: sess.id,
            });
            logger.info("Premium (subscription) mirrored active", { uid, session: sess.id });
          }
          break;
        }

        case "charge.refunded": {
          // Optional: revoke Offline-Pro upon refund (business choice)
          const charge = event.data.object as Stripe.Charge;
          const uid = (charge.metadata?.uid as string | undefined) ?? null;
          if (uid) {
            await setPremiumStatusDoc(uid, { proOffline: false, source: "stripe" });
            logger.info("Offline-Pro revoked (refund)", { uid, charge: charge.id });
          }
          break;
        }

        case "invoice.payment_succeeded": {
          // Mirror subscription billing period
          const inv = event.data.object as Stripe.Invoice;
          const uid =
            (inv as any)?.subscription_details?.metadata?.uid ??
            inv.metadata?.uid ??
            null;
          if (uid) {
            const periodEnd =
              inv.lines?.data?.[0]?.period?.end ?? (inv as any)?.period_end ?? null;
            await setPremium(uid, true, { source: "stripe", currentPeriodEnd: periodEnd });
            logger.info("Premium mirrored via invoice.payment_succeeded", { uid });
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
            logger.info("Premium subscription updated", { uid, status: sub.status });
          }
          break;
        }

        case "customer.subscription.deleted": {
          const sub = event.data.object as Stripe.Subscription;
          const uid = sub.metadata?.uid ?? null;
          if (uid) {
            await setPremium(uid, false, { source: "stripe", status: sub.status });
            logger.info("Premium subscription deleted", { uid });
          }
          break;
        }

        default:
          // no-op
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
 * Unified refresh: RC → allowlist → promotional grant → Firestore mirror
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

    // Allowlist check (exact + gmail-normalized)
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

    // Grant long promotional (100y) instead of literal forever
    const expires = new Date();
    expires.setFullYear(expires.getFullYear() + 100);
    await rcGrantPromo(uid, ENTITLEMENT_ID, { end_time: expires });

    const now = serverNow();
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

    await grantRef.set({ premium: true, at: serverNow(), by: "ensureTesterPremium" }, { merge: true });
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
 * Promo code redemption (sideload/regional fallback)
 * Secured with:
 * - Firestore-stored codes (not hardcoded)
 * - Single-use tracking
 * - Rate limiting (3 attempts per user per hour)
 * - Audit logging
 * ────────────────────────────────────────────────────────────────────────── */
export const redeemPromoCode = onCall({ secrets: [] }, async (req) => {
  const uid = assertAuthed(req.auth?.uid);
  const code = (req.data?.code as string | undefined)?.trim().toUpperCase();

  if (!code) {
    throw new HttpsError("invalid-argument", "Promo code is required.");
  }

  try {
    // Rate limiting: check recent attempts
    const attemptsRef = db.collection("promo_attempts").doc(uid);
    const attemptsSnap = await attemptsRef.get();
    const attemptsData = attemptsSnap.data();
    const now = Date.now();
    const oneHourAgo = now - 60 * 60 * 1000;

    const recentAttempts = (attemptsData?.attempts as number[] | undefined)
      ?.filter((t: number) => t > oneHourAgo) || [];

    if (recentAttempts.length >= 3) {
      logger.warn("redeemPromoCode: rate limit exceeded", { uid, code });
      throw new HttpsError("resource-exhausted", "Too many attempts. Try again later.");
    }

    // Log this attempt
    await attemptsRef.set(
      { attempts: admin.firestore.FieldValue.arrayUnion(now), lastAttempt: now },
      { merge: true }
    );

    // Check if code exists and is valid
    const codeRef = db.collection("promo_codes").doc(code);
    const codeSnap = await codeRef.get();

    if (!codeSnap.exists) {
      logger.warn("redeemPromoCode: invalid code", { uid, code });
      throw new HttpsError("not-found", "Invalid promo code.");
    }

    const codeData = codeSnap.data()!;
    const grantType = codeData.type as "premium" | "proOffline" | undefined;
    const maxUses = (codeData.maxUses as number | undefined) || 1;
    const usedBy = (codeData.usedBy as string[] | undefined) || [];
    const expiresAt = codeData.expiresAt
      ? (codeData.expiresAt as admin.firestore.Timestamp).toMillis()
      : null;

    // Check expiration
    if (expiresAt && now > expiresAt) {
      logger.warn("redeemPromoCode: expired code", { uid, code, expiresAt });
      throw new HttpsError("failed-precondition", "This promo code has expired.");
    }

    // Check if already used by this user
    if (usedBy.includes(uid)) {
      logger.warn("redeemPromoCode: already used by user", { uid, code });
      throw new HttpsError("already-exists", "You have already used this promo code.");
    }

    // Check max uses
    if (usedBy.length >= maxUses) {
      logger.warn("redeemPromoCode: max uses exceeded", { uid, code, maxUses, usedCount: usedBy.length });
      throw new HttpsError("resource-exhausted", "This promo code has reached its usage limit.");
    }

    // Grant the entitlement
    if (grantType === "premium") {
      await setPremium(uid, true, { source: "promo", code, grantedAt: serverNow() });
      // Optionally grant RC entitlement as well
      try {
        const expires = new Date();
        expires.setFullYear(expires.getFullYear() + 100);
        await rcGrantPromo(uid, ENTITLEMENT_ID, { end_time: expires });
      } catch (rcErr) {
        logger.warn("redeemPromoCode: RC grant failed (not critical)", { uid, code, rcErr });
      }
    } else if (grantType === "proOffline") {
      await setPremiumStatusDoc(uid, { proOffline: true, source: "promo", code, grantedAt: serverNow() });
    } else {
      logger.error("redeemPromoCode: unknown grant type", { uid, code, grantType });
      throw new HttpsError("internal", "Invalid promo code configuration.");
    }

    // Mark code as used by this user
    await codeRef.update({
      usedBy: admin.firestore.FieldValue.arrayUnion(uid),
      lastUsedAt: serverNow(),
    });

    // Audit log
    await db.collection("promo_redemptions").add({
      uid,
      code,
      grantType,
      redeemedAt: serverNow(),
      email: req.auth?.token.email || null,
    });

    logger.info("redeemPromoCode: success", { uid, code, grantType });
    return {
      success: true,
      message: grantType === "premium" ? "Premium activated!" : "Pro-Offline activated!",
      grantType,
    };
  } catch (err: any) {
    if (err instanceof HttpsError) throw err;
    logger.error("redeemPromoCode: unexpected error", { uid, code, message: err?.message, raw: err });
    throw new HttpsError("internal", "An error occurred while redeeming the code.");
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
    const snap = await userRef.collection(coll).where("_meta.deleted", "==", true).limit(500).get();
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
              user: userRef.id,
              collection: coll,
              deleted: n,
            });
            totalDeleted += n;
          }
        } catch (err: any) {
          logger.error("purgeSoftDeletes: sweep error", {
            user: userRef.id,
            collection: coll,
            message: err?.message,
          });
        }
      }
    }

    logger.info("purgeSoftDeletes complete", { totalDeleted, usersScanned: userRefs.length });
  }
);

/* ──────────────────────────────────────────────────────────────────────────
 * Other function exports (keep your existing ingest endpoints)
 * ────────────────────────────────────────────────────────────────────────── */
export { ingestDevice } from "./ingestDevice";
export { ingest } from "./ingest";
export { onRecipeCreated, onBatchCreated, onDeviceLinked } from "./ga4Conversions";
