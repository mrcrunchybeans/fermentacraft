import * as logger from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import Stripe from "stripe";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: "2024-06-20",
});

// Utility: verify Firebase ID token from Authorization: Bearer <token>
async function verifyFirebaseToken(authorization?: string) {
  if (!authorization?.startsWith("Bearer ")) {
    throw new Error("Missing or invalid Authorization header");
  }
  const idToken = authorization.substring("Bearer ".length);
  const decoded = await getAuth().verifyIdToken(idToken);
  return decoded.uid;
}

/**
 * Create a Stripe Checkout Session for Offline-Pro (one-time).
 * Pass Authorization: Bearer <Firebase ID token> in headers from the app.
 */
export const createCheckoutSession = onRequest(
  { cors: true, region: "us-central1" },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
      }

      const uid = await verifyFirebaseToken(req.headers.authorization);
      const { priceId } = req.body as { priceId: string };

      if (!priceId) {
        res.status(400).json({ error: "Missing priceId" });
        return;
      }

      const session = await stripe.checkout.sessions.create({
        mode: "payment",                     // <<< THE IMPORTANT BIT
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: "https://fermentacraft.com/checkout-success/",
        cancel_url: "https://fermentacraft.com/checkout-cancel/",
        // Optional niceties:
        allow_promotion_codes: true,
        billing_address_collection: "auto",
        // Tie back to your Firebase user for webhook grant:
        metadata: { uid },
        // If you also want an email receipt associated:
        customer_email: req.body.email || undefined,
      });

      res.json({ url: session.url });
    } catch (err: any) {
      logger.error("createCheckoutSession error", err);
      res.status(400).json({ error: err.message || "Unknown error" });
    }
  }
);
