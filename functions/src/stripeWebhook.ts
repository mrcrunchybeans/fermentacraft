import * as logger from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import Stripe from "stripe";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: "2024-06-20",
});

export const stripeWebhook = onRequest(
  { region: "us-central1", secrets: ["STRIPE_WEBHOOK_SECRET"] },
  async (req, res) => {
    const sig = req.headers["stripe-signature"] as string | undefined;
    if (!sig) {
      res.status(400).send("Missing stripe-signature");
      return;
    }

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        req.rawBody,
        sig,
        process.env.STRIPE_WEBHOOK_SECRET!
      );
    } catch (err: any) {
      logger.error("Webhook signature verification failed.", err.message);
      res.status(400).send(`Webhook Error: ${err.message}`);
      return;
    }

    // Handle successful one-time Checkout
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const uid = session.metadata?.uid;

      if (!uid) {
        logger.error("No uid in session.metadata; cannot grant proOffline");
      } else {
        const db = getFirestore();
        const ref = db.doc(`users/${uid}/premium/status`);
        await ref.set(
          {
            proOffline: true,
            proOfflineGrantedAt: new Date().toISOString(),
            lastStripeCheckoutId: session.id,
          },
          { merge: true }
        );
        logger.info(`Granted proOffline for uid=${uid}`);
      }
    }

    res.json({ received: true });
  }
);
