// functions/src/index.ts
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { setGlobalOptions } from "firebase-functions/v2";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import Stripe from "stripe";
import type { Request, Response } from "express";

setGlobalOptions({ region: "us-central1", timeoutSeconds: 60, memory: "256MiB" });

admin.initializeApp();
const db = admin.firestore();

// ─── Secrets ────────────────────────────────────────────────────────────────
const STRIPE_SECRET = defineSecret("STRIPE_SECRET");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const RC_SECRET_KEY = defineSecret("RC_SECRET_KEY");

// Stripe client factory
const stripe = () => new Stripe(STRIPE_SECRET.value(), { apiVersion: "2024-06-20" });

// ─── Constants ──────────────────────────────────────────────────────────────
const TRIAL_DAYS = 7; // universal 7-day trial
const ENTITLEMENT_ID = "premium"; // RevenueCat entitlement id

// ─── Helpers ────────────────────────────────────────────────────────────────
const allowCors = (res: Response) => {
  // TODO: restrict to your production origins
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization, Origin");
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

// ─── RevenueCat helpers ─────────────────────────────────────────────────────
async function rcFetch(path: string, init?: RequestInit) {
  const url = `https://api.revenuecat.com${path}`;
  const resp = await fetch(url, {
    ...init,
    headers: {
      "Authorization": `Bearer ${RC_SECRET_KEY.value()}`,
      "Content-Type": "application/json",
      ...(init?.headers ?? {}),
    },
  });
  return resp;
}

async function rcGetSubscriber(uid: string): Promise<any | null> {
  const r = await rcFetch(`/v1/subscribers/${encodeURIComponent(uid)}`, { method: "GET" });
  if (r.status === 404) return null;
  if (!r.ok) {
    const text = await r.text().catch(() => "");
    throw new HttpsError("internal", `RevenueCat GET failed: ${r.status} ${text}`);
  }
  return r.json();
}

/** Heuristic: treat entitlement as active if exists and (no expires_date or future). */
function rcHasActiveEntitlement(sub: any, entitlementId = ENTITLEMENT_ID): boolean {
  try {
    const ent = sub?.subscriber?.entitlements?.[entitlementId];
    if (!ent) return false;

    const expires = ent.expires_date; // may be null for lifetime promo
    if (expires == null) return true;
    const ts = Date.parse(expires);
    if (Number.isNaN(ts)) return false;
    return ts > Date.now();
  } catch {
    return false;
  }
}

async function rcGrantPromo(uid: string, entitlementId = ENTITLEMENT_ID): Promise<void> {
  const r = await rcFetch(
    `/v1/subscribers/${encodeURIComponent(uid)}/entitlements/${encodeURIComponent(entitlementId)}`,
    {
      method: "POST",
      body: JSON.stringify({ effective_date: "now", expires_date: null }),
    }
  );
  if (!r.ok) {
    const text = await r.text().catch(() => "");
    throw new HttpsError("internal", `RevenueCat grant failed: ${r.status} ${text}`);
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  Checkout (callable): data { priceId, successUrl, cancelUrl }
// ────────────────────────────────────────────────────────────────────────────
export const createCheckout = onCall({ secrets: [STRIPE_SECRET] }, async (req) => {
  try {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const { priceId, successUrl, cancelUrl } = (req.data ?? {}) as {
      priceId?: string; successUrl?: string; cancelUrl?: string;
    };
    if (!priceId || !successUrl || !cancelUrl) {
      throw new HttpsError("invalid-argument", "Missing priceId/successUrl/cancelUrl");
    }

    const s = stripe();

    // Validate price upfront (surfaces live/test mismatches clearly)
    let price;
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

// ────────────────────────────────────────────────────────────────────────────
/** Checkout (HTTP): desktop; Authorization: Bearer <Firebase ID token> */
// ────────────────────────────────────────────────────────────────────────────
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
      if (!decoded?.uid) return void res.status(401).json({ error: "Invalid ID token" });
      const uid = decoded.uid;

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

// ────────────────────────────────────────────────────────────────────────────
/** Billing Portal (callable): returns portal URL for current user */
// ────────────────────────────────────────────────────────────────────────────
export const createBillingPortal = onCall({ secrets: [STRIPE_SECRET] }, async (request) => {
  try {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    // Find stored Stripe customer ID (written by webhook)
    const snap = await db.collection("users").doc(uid).collection("premium").doc("status").get();
    const customer = snap.data()?.customer as string | undefined;
    if (!customer) throw new HttpsError("not-found", "No Stripe customer found.");

    const s = stripe();
    const session = await s.billingPortal.sessions.create({
      customer,
      // You noted you don't have /account yet; send users back home/app root:
      return_url: "https://app.fermentacraft.com/",
    });

    return { url: session.url };
  } catch (err: any) {
    logger.error("createBillingPortal error", { message: err?.message, raw: err });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err?.message ?? "Portal failed");
  }
});

// ────────────────────────────────────────────────────────────────────────────
/** Prices (callable) */
// ────────────────────────────────────────────────────────────────────────────
export const getStripePrices = onCall({ secrets: [STRIPE_SECRET] }, async (req) => {
  try {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

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

// ────────────────────────────────────────────────────────────────────────────
/** Prices (HTTP) */
// ────────────────────────────────────────────────────────────────────────────
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
      if (!decoded?.uid) return void res.status(401).json({ error: "Invalid ID token" });

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

// ────────────────────────────────────────────────────────────────────────────
/** Stripe Webhook → mirrors premium to Firestore */
// ────────────────────────────────────────────────────────────────────────────
export const stripeWebhook = onRequest(
  { secrets: [STRIPE_SECRET, STRIPE_WEBHOOK_SECRET] },
  async (req: Request, res: Response): Promise<void> => {
    type StripeRequest = Request & { rawBody: Buffer };
    const sig = req.headers["stripe-signature"] as string | undefined;

    let event: Stripe.Event;
    try {
      const rawBody = (req as StripeRequest).rawBody;
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
          if (uid) {
            await setPremium(uid, true, {
              source: "stripe",
              customer: sess.customer ?? null,
              subscriptionId: sess.subscription ?? null,
            });
          }
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
          // Optional: log others
          break;
      }

      res.json({ received: true });
    } catch (e) {
      logger.error("Webhook handler error:", e);
      res.status(500).send("Webhook handler error");
    }
  }
);
// ────────────────────────────────────────────────────────────────────────────
//  Unified refresh: check RC → allowlist → grant promo → mirror Firestore
//  Call this from ALL platforms for "Refresh status".
// ────────────────────────────────────────────────────────────────────────────
export const syncPremiumFromRC = onCall({ secrets: [RC_SECRET_KEY] }, async (req) => {
  const uid = req.auth?.uid;
  const email = (req.auth?.token?.email as string | undefined)?.trim().toLowerCase();
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

  try {
    // 1) Ask RevenueCat first
    const sub = await rcGetSubscriber(uid);
    if (sub && rcHasActiveEntitlement(sub, ENTITLEMENT_ID)) {
      await setPremium(uid, true, { source: "rc" });
      return { ok: true, active: true, source: "rc" };
    }

    // 2) Not active in RC → see if allowlisted to grant promo
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

// 3) Allowlisted → grant promo in RC (idempotent enough for our use)
await rcGrantPromo(uid, ENTITLEMENT_ID);

// 4) Immediately mirror Firestore so status is visible without second press
const now = admin.firestore.FieldValue.serverTimestamp();
await db.collection("rc_grants").doc(uid).set(
  { premium: true, at: now, by: "syncPremiumFromRC" },
  { merge: true }
);
await setPremium(uid, true, { source: "rc_promo", grantedAt: now });

// 5) Return success right away
return { ok: true, active: true, source: "rc_promo", granted: true, instant: true };
  } catch (err: any) {
    logger.error("syncPremiumFromRC error", { message: err?.message, raw: err });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("internal", err?.message ?? "Refresh failed");
  }
});

// ────────────────────────────────────────────────────────────────────────────
//  Legacy: keep until all clients call syncPremiumFromRC
// ────────────────────────────────────────────────────────────────────────────
export const ensureTesterPremium = onCall({ secrets: [RC_SECRET_KEY] }, async (req) => {
  try {
    const uid = req.auth?.uid;
    const email = (req.auth?.token.email as string | undefined)?.trim().toLowerCase();
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
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

    // Idempotency
    const grantRef = db.collection("rc_grants").doc(uid);
    const grantSnap = await grantRef.get();
    if (grantSnap.exists && grantSnap.get("premium") === true) {
      await setPremium(uid, true, { source: "rc_promo" });
      return { ok: true, already: true };
    }

    // Grant
    await rcGrantPromo(uid, ENTITLEMENT_ID);

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