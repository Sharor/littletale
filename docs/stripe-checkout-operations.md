# Stripe Checkout operations

Little Stories uses Stripe-hosted Checkout for one-time credit purchases and monthly subscriptions.

- Product `prod_VHc1FYY2QqVlJ0` must have an active one-time default Price. One confirmed purchase grants one book credit, five character-generation credits, and permanent Basic reading access.
- Product `prod_VInAXXEHxVHfXh` must have an active recurring default Price with a one-month interval. Each paid subscription invoice grants a hidden allowance of 50 books and 150 character generations for that billing period.

Subscription allowance is spent before visible credits. At renewal or subscription end, unused monthly allowance tops up the user's shared visible balance to at most 10 book credits and 20 character credits. Purchased and saved credits use that same visible balance: purchases can take it above those thresholds, and rollover never removes or replaces existing credits. The Settings page displays the shared visible balances but does not display the current monthly allowance.

## Credentials

Configure these Rails credentials separately in each environment:

```yaml
stripe:
  account: acct_...
  secret: sk_test_... # sk_live_... in production only
  publishable: pk_test_... # pk_live_... in production only
  webhook_secret: whsec_...
```

The server uses `stripe.secret` for Checkout and `stripe.webhook_secret` for signature verification. Before creating Checkout, it retrieves the account behind the secret key and requires its ID to match `stripe.account`. Hosted Checkout does not expose the secret key or require the publishable key in the browser. Development and test reject live-mode products; production rejects test-mode products. Enable and configure the Stripe customer portal before exposing subscription management; subscribers use it to update payment details or schedule cancellation.

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
- `invoice.paid`
- `customer.subscription.updated`
- `customer.subscription.deleted`

Copy that endpoint's signing secret into `stripe.webhook_secret`. Checkout redirects improve the browser experience, while the webhook remains the authoritative fulfillment path. A paid invoice, rather than the Checkout redirect, opens each monthly allowance. Event IDs, invoice IDs, billing-period starts, and Checkout outcome/object pairs are persisted so retries and out-of-order invoices cannot grant duplicate periods.

## Deployment order

1. Configure test one-time and monthly products/Prices and test credentials outside production. Confirm `prod_VInAXXEHxVHfXh` uses a monthly recurring Price.
2. Apply migrations with `bin/rails db:migrate` and restart Rails so model column data reloads.
3. Enable the Stripe customer portal and allow customers to cancel subscriptions at the end of the billing period.
4. Register the test webhook and complete both Checkout paths with Stripe's test payment method.
5. Verify a one-time purchase shows one book credit, then resend its webhook and confirm the balance does not change.
6. Verify a subscription permits generation while Settings shows zero visible credits. Resend the first `invoice.paid` event and confirm no second allowance is created.
7. Advance a Stripe test clock through renewal. Confirm unused allowance tops up visible balances only to 10 books and 20 characters, then confirm the new hidden allowance funds generation.
8. Schedule cancellation in the customer portal, advance to the period end, and confirm the final unused allowance is saved up to the same visible caps.
9. Configure the live webhook and customer portal in production before enabling the subscription button.
10. Verify both production products' default Prices, currency, amount, tax configuration, intervals, and live-mode flags in Stripe.

Rolling back the subscription migration deletes subscription periods, their hidden allowance credits, and any reservations against those credits. It preserves one-time purchased credits. Export or audit subscription balances before a production rollback if that history may be needed.

Failed webhook deliveries are visible in Stripe Workbench and can be resent. A failed local delivery must be replayed rather than repaired by manually changing balances. A failed renewal does not grant a new allowance; Stripe subscription updates keep the local billing status current. Refunds and disputes do not automatically revoke credits in this version; review them manually before changing any local entitlement.
