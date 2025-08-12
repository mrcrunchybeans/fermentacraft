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


// Stripe client factory (call it where you need it)
const stripe = () => new Stripe(STRIPE_SECRET.value(), { apiVersion: "2024-06-20" });

// ─── Constants ──────────────────────────────────────────────────────────────
const TRIAL_DAYS = 7; // universal 7-day trial

// ─── Helpers ────────────────────────────────────────────────────────────────
const allowCors = (res: Response) => {
  // TODO: lock this down to your app origins in prod
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
};

const setPremium = async (
  uid: string,
  active: boolean,
  extra: Record<string, unknown> = {}
) => {
  const ref = db.collection("users").doc(uid).collection("premium").doc("status");
  const now = admin.firestore.FieldValue.serverTimestamp();
  await ref.set({ active, updatedAt: now, source: "stripe", ...extra }, { merge: true });
};

function toProductSummary(
  prod: string | Stripe.Product | Stripe.DeletedProduct
): { id: string; name: string } | null {
  if (typeof prod === "string") return null;
  if ("deleted" in prod && prod.deleted) return null;
  return { id: prod.id, name: prod.name };
}

// ────────────────────────────────────────────────────────────────────────────
//  Checkout: callable (mobile/web)
//  data: { priceId: string, successUrl: string, cancelUrl: string }
// ────────────────────────────────────────────────────────────────────────────
export const createCheckout = onCall({ secrets: [STRIPE_SECRET] }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

  const { priceId, successUrl, cancelUrl } = (req.data ?? {}) as {
    priceId?: string;
    successUrl?: string;
    cancelUrl?: string;
  };
  if (!priceId || !successUrl || !cancelUrl) {
    throw new HttpsError("invalid-argument", "Missing priceId/successUrl/cancelUrl");
  }

  const s = stripe();
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
      // Or: trial_settings: { end_behavior: { missing_payment_method: "cancel" } },
    },
  });

  return { url: session.url };
});

// ────────────────────────────────────────────────────────────────────────────
//  Checkout: HTTP (desktop, uses Firebase ID token in Authorization: Bearer)
// ────────────────────────────────────────────────────────────────────────────
export const createCheckoutHttp = onRequest(
  { secrets: [STRIPE_SECRET] },
  async (req: Request, res: Response): Promise<void> => {
    allowCors(res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      const auth = req.headers.authorization || "";
      if (!auth.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
      }
      const idToken = auth.substring(7);
      const decoded = await admin.auth().verifyIdToken(idToken).catch(() => null);
      if (!decoded?.uid) {
        res.status(401).json({ error: "Invalid ID token" });
        return;
      }
      const uid = decoded.uid;

      const { priceId, successUrl, cancelUrl } = (req.body ?? {}) as {
        priceId?: string;
        successUrl?: string;
        cancelUrl?: string;
      };
      if (!priceId || !successUrl || !cancelUrl) {
        res.status(400).json({ error: "Missing priceId/successUrl/cancelUrl" });
        return;
      }

      const s = stripe();
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
      });

      res.json({ url: session.url });
    } catch (e: any) {
      logger.error("createCheckoutHttp error:", e);
      res.status(500).json({ error: e?.message || "Server error" });
    }
  }
);

// ────────────────────────────────────────────────────────────────────────────
/** Billing Portal: callable → returns a portal URL for the current user */
// ────────────────────────────────────────────────────────────────────────────
export const createBillingPortal = onCall(
  { secrets: [STRIPE_SECRET] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    // Find stored Stripe customer ID (written by webhook)
    const snap = await db
      .collection("users")
      .doc(uid)
      .collection("premium")
      .doc("status")
      .get();

    const customer = snap.data()?.customer as string | undefined;
    if (!customer) throw new HttpsError("not-found", "No Stripe customer found.");

    const s = stripe();
    const session = await s.billingPortal.sessions.create({
      customer,
      return_url: "https://app.fermentacraft.com/account", // update to your account page
    });

    return { url: session.url };
  }
);

// ────────────────────────────────────────────────────────────────────────────
/** Prices: callable (mobile/web) */
// ────────────────────────────────────────────────────────────────────────────
export const getStripePrices = onCall({ secrets: [STRIPE_SECRET] }, async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

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
});

// ────────────────────────────────────────────────────────────────────────────
/** Prices: HTTP (desktop) */
// ────────────────────────────────────────────────────────────────────────────
export const getStripePricesHttp = onRequest(
  { secrets: [STRIPE_SECRET] },
  async (req: Request, res: Response): Promise<void> => {
    allowCors(res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    try {
      const auth = req.headers.authorization || "";
      if (!auth.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
      }
      const idToken = auth.substring(7);
      const decoded = await admin.auth().verifyIdToken(idToken).catch(() => null);
      if (!decoded?.uid) {
        res.status(401).json({ error: "Invalid ID token" });
        return;
      }

      const priceIds = (req.body?.priceIds as string[] | undefined)?.filter(Boolean) ?? [];
      if (!priceIds.length) {
        res.status(400).json({ error: "priceIds required" });
        return;
      }

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
      logger.error("getStripePricesHttp error:", e);
      res.status(500).json({ error: e?.message || "Server error" });
    }
  }
);

// ────────────────────────────────────────────────────────────────────────────
/** Webhook: Stripe → Firestore */
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
            const periodEnd =
              inv.lines?.data?.[0]?.period?.end ?? (inv as any)?.period_end ?? null;
            await setPremium(uid, true, { currentPeriodEnd: periodEnd });
          }
          break;
        }

        case "customer.subscription.updated": {
          const sub = event.data.object as Stripe.Subscription;
          const uid = sub.metadata?.uid ?? null;
          if (uid) {
            const active = sub.status === "active" || sub.status === "trialing";
            await setPremium(uid, active, {
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
            await setPremium(uid, false, { status: sub.status });
          }
          break;
        }

        default:
          // log other events if you want
          break;
      }

      res.json({ received: true });
    } catch (e) {
      logger.error("Webhook handler error:", e);
      res.status(500).send("Webhook handler error");
    }
  }
);

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

export const ensureTesterPremium = onCall({ secrets: [RC_SECRET_KEY] }, async (req) => {
  const uid = req.auth?.uid;
  const email = (req.auth?.token.email as string | undefined)?.trim().toLowerCase();
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");
  if (!email) throw new HttpsError("failed-precondition", "Email required on account.");

  // 1) Check allowlist: exact + gmail-normalized, accept approved OR allowed
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

  // 2) Idempotency: already granted?
  const grantRef = db.collection("rc_grants").doc(uid);
  const grantSnap = await grantRef.get();
  if (grantSnap.exists && grantSnap.get("premium") === true) {
    // refresh mirror and return
    await db.doc(`users/${uid}/premium/status`).set(
      { active: true, source: "rc_promo", updatedAt: admin.firestore.FieldValue.serverTimestamp() },
      { merge: true }
    );
    return { ok: true, already: true };
  }

  // 3) Grant via RevenueCat API (promotional entitlement, lifetime)
  const rcSecret = RC_SECRET_KEY.value();
  const entitlementId = "premium"; // <-- change if your RC entitlement id differs
  const url = `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(uid)}/entitlements/${encodeURIComponent(entitlementId)}`;

  const resp = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${rcSecret}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ effective_date: "now", expires_date: null }),
  });

  if (!resp.ok) {
    const text = await resp.text();
    logger.error("RevenueCat grant failed", { status: resp.status, text });
    throw new HttpsError("internal", `RevenueCat grant failed: ${resp.status} ${text}`);
  }

  // 4) Record & mirror (client reads this doc; rules block client writes)
  await grantRef.set(
    { premium: true, at: admin.firestore.FieldValue.serverTimestamp(), by: "ensureTesterPremium" },
    { merge: true }
  );
  await db.doc(`users/${uid}/premium/status`).set(
    { active: true, source: "rc_promo", updatedAt: admin.firestore.FieldValue.serverTimestamp() },
    { merge: true }
  );

  logger.info("ensureTesterPremium: granted", { uid, email });
  return { ok: true, granted: true };
});
// ─── END ensureTesterPremium ────────────────────────────────────────────────