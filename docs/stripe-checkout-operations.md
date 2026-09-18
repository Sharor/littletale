# Stripe Checkout operations

Little Stories uses Stripe-hosted Checkout in one-time `payment` mode. Product `prod_VHc1FYY2QqVlJ0` must have an active one-time default Price. One confirmed Checkout purchase grants one book credit, five character-generation credits, and permanent Basic reading access.

## Credentials

Configure these Rails credentials separately in each environment:

```yaml
stripe:
  account: acct_...
  secret: sk_test_... # sk_live_... in production only
  publishable: pk_test_... # pk_live_... in production only
  webhook_secret: whsec_...
```

The server uses `stripe.secret` for Checkout and `stripe.webhook_secret` for signature verification. Before creating Checkout, it retrieves the account behind the secret key and requires its ID to match `stripe.account`. Hosted Checkout does not expose the secret key or require the publishable key in the browser. Development and test reject live-mode products; production rejects test-mode products.

## Webhook endpoint

Create a public HTTPS webhook endpoint at:

```text
POST https://YOUR_HOST/webhooks/stripe
```

Subscribe only to:

- `checkout.session.completed`
- `checkout.session.async_payment_succeeded`
- `checkout.session.async_payment_failed`
- `checkout.session.expired`

Copy that endpoint's signing secret into `stripe.webhook_secret`. Checkout redirects improve the browser experience, while the webhook remains the authoritative fulfillment path. Event IDs and Checkout outcome/object pairs are persisted so Stripe retries cannot grant duplicate credits.

## Deployment order

1. Configure a test product/Price and test credentials outside production.
2. Apply migrations with `bin/rails db:migrate` and restart Rails so model column data reloads.
3. Register the test webhook and complete a Checkout with Stripe's test payment method.
4. Verify Settings shows one book credit and Basic access, then resend the same webhook and confirm the balance does not change.
5. Configure the live webhook and `whsec_...` in production before enabling the purchase button.
6. Verify the production product's default Price, currency, amount, tax configuration, and live-mode flag in Stripe.

Failed webhook deliveries are visible in Stripe Workbench and can be resent. A failed local delivery must be replayed rather than repaired by manually changing balances. Refunds and disputes do not automatically revoke credits in this version; review them manually before changing any local entitlement.
