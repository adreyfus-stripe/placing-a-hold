package com.stripe.sample;

import java.nio.file.Paths;

import static spark.Spark.get;
import static spark.Spark.post;
import static spark.Spark.staticFiles;
import static spark.Spark.port;

import com.google.gson.Gson;
import com.google.gson.annotations.SerializedName;

import com.stripe.Stripe;
import com.stripe.net.ApiResource;
import com.stripe.model.Event;
import com.stripe.model.EventDataObjectDeserializer;
import com.stripe.model.PaymentIntent;
import com.stripe.exception.*;
import com.stripe.net.Webhook;
import com.stripe.param.PaymentIntentCreateParams;

public class Server {
    private static Gson gson = new Gson();

    static class CreatePaymentBody {
        @SerializedName("items")
        Object[] items;

        @SerializedName("currency")
        String currency;

        public Object[] getItems() {
            return items;
        }

        public String getCurrency() {
            return currency;
        }
    }

    static class CreatePaymentResponse {
        private String publicKey;
        private String clientSecret;
        private String id;

        public CreatePaymentResponse(String publicKey, String clientSecret, String id) {
            this.publicKey = publicKey;
            this.clientSecret = clientSecret;
            this.id = id;
        }
    }

    static int calculateOrderAmount(Object[] items) {
        // Replace this constant with a calculation of the order's amount
        // Calculate the order total on the server to prevent
        // users from directly manipulating the amount on the client
        return 1400;
    }

    public static void main(String[] args) {
        port(4242);
        Stripe.apiKey = System.getenv("STRIPE_SECRET_KEY");

        staticFiles.externalLocation(
                Paths.get(Paths.get("").toAbsolutePath().getParent().getParent().toString() + "/client")
                        .toAbsolutePath().toString());

        post("/create-payment-intent", (request, response) -> {
            response.type("application/json");

            CreatePaymentBody postBody = gson.fromJson(request.body(), CreatePaymentBody.class);
            PaymentIntentCreateParams createParams = new PaymentIntentCreateParams.Builder()
                    .setCurrency(postBody.getCurrency()).setAmount(new Long(calculateOrderAmount(postBody.getItems())))
                    .setCaptureMethod(PaymentIntentCreateParams.CaptureMethod.MANUAL).build();
            // Create a PaymentIntent with the order amount and currency
            PaymentIntent intent = PaymentIntent.create(createParams);
            // Send public key and PaymentIntent details to client
            return gson.toJson(new CreatePaymentResponse(System.getenv("STRIPE_PUBLIC_KEY"), intent.getClientSecret(),
                    intent.getId()));
        });

        post("/webhook", (request, response) -> {
            String payload = request.body();
            String sigHeader = request.headers("Stripe-Signature");
            String endpointSecret = System.getenv("STRIPE_WEBHOOK_SECRET");

            Event event = null;

            try {
                event = Webhook.constructEvent(payload, sigHeader, endpointSecret);
            } catch (SignatureVerificationException e) {
                // Invalid signature
                response.status(400);
                return "";
            }

            switch (event.getType()) {
            case "payment_intent.amount_capturable_updated":
                EventDataObjectDeserializer deserializer = event.getDataObjectDeserializer();
                PaymentIntent intent = ApiResource.GSON.fromJson(deserializer.getRawJson(), PaymentIntent.class);
                System.out.println("❗Charging the card for:  " + Long.toString(intent.getAmountCapturable()));
                // You can capture an amount less than or equal to the amount_capturable
                // By default capture() will capture the full amount_capturable
                // To cancel a payment before capturing use .cancel()
                // (https://stripe.com/docs/api/payment_intents/cancel)
                intent.capture();
                break;
            case "payment_intent.succeeded":
                // Fulfill any orders, e-mail receipts, etc
                // To cancel the payment after capture you will need to issue a Refund
                // (https://stripe.com/docs/api/refunds)
                System.out.println("💰Payment received!");
                break;
            case "payment_intent.payment_failed":
                System.out.println("❌ Payment failed.");
                break;
            default:
                // Unexpected event type
                response.status(400);
                return "";
            }

            response.status(200);
            return "";
        });
    }
}