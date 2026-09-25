# Stripe production checklist

1. Confirm product `prod_VHc1FYY2QqVlJ0` has an active one-time default Price with the intended amount, currency, and tax settings.
2. Configure production Rails credentials for `stripe.account`, `stripe.secret`, and `stripe.publishable` using live Stripe values.
3. Register `POST https://YOUR_HOST/webhooks/stripe` as a Stripe webhook endpoint.
4. Subscribe it to `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, and `checkout.session.expired`.
5. Store that endpoint's signing secret as `stripe.webhook_secret` in production credentials.
6. Run `bin/rails db:migrate` during deployment and restart the Rails and background-worker processes.
7. Complete one intentional live Checkout, verify Basic access plus one book credit, and confirm five character credits in the admin view.
8. Replay the successful webhook once and verify that no duplicate credits are granted.
9. Review failed webhook deliveries in Stripe Workbench; replay failures instead of editing balances manually.

See [the full Stripe Checkout operations guide](docs/stripe-checkout-operations.md) and [Stripe's webhook documentation](https://docs.stripe.com/webhooks).
