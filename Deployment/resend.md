# Resend production setup

Status: `minortale.com` is verified in Resend. All application mail uses
`MinorTale <hello@minortale.com>` through Action Mailer.

## Application configuration

- Read the existing API key server-side from
  `Rails.application.credentials.dig(:smtp, :resend_api_key)`.
  Never copy the key into this file, source code, browser code, or logs.
- The `resend` gem is integrated through Rails Action Mailer. Production uses
  the `:resend` delivery method.
- `RESEND_FROM_EMAIL` configures the full From value. Kamal sets it to
  `MinorTale <hello@minortale.com>`, which is also the application default.
- `APP_HOST` is the single canonical hostname used for production assets,
  controller URLs, mailer links, and route URL generation. Kamal sets it to
  `minortale.com`; generated links use HTTPS.
- The Kamal proxy accepts both `minortale.com` and `www.minortale.com`.
- Development keeps its normal local delivery behavior unless
  `RESEND_DELIVERY_ENABLED=true` is set. When enabled, it sends through Resend.
- Automated tests remain on Action Mailer's `:test` delivery method and never
  send real messages.
- Gift delivery preserves the chosen locale and provides HTML and plain-text
  versions. The gift records queued, sent, and failed states, and the sender can
  retry a failed delivery with a newly generated invitation link.
- Invitation tokens are encrypted in the application database, and delivery jobs
  carry only an opaque attempt ID. The same attempt ID is sent to Resend as its
  idempotency key, including failure retries. Keep the Rails secret key base
  stable across web and queue processes so queued links can be decrypted.
- Configure application, proxy, and hosting access logs to redact `/gifts/*`
  paths. Claims still require the exact verified Gmail account, but invitation
  URLs contain private giftcard content and should be treated as sensitive.

Development mail links currently use `localhost:3000`; these only work on the
machine running the app. Email delivery and publicly reachable invitation links
are separate requirements. Do not advertise local invitation links as usable by
remote recipients.

## Deployment verification

1. Keep the Resend API key in Rails credentials and confirm the production key
   can send from `minortale.com`.
2. Keep the domain's SPF and DKIM records in the verified state shown by Resend.
3. Configure the OAuth applications with these callback URLs:
   `https://minortale.com/users/auth/google_oauth2/callback` for Google and
   `https://minortale.com/users/auth/microsoft_v2_auth/callback` for Microsoft.
4. Deploy and restart both web and queue processes so they load the sender and
   canonical host settings.
5. Send the admin production email check to an authorized administrator and
   confirm receipt, sender alignment, HTML/plain-text content, and HTTPS links.
6. Send a gift only to an explicitly chosen Gmail recipient, then confirm the
   complete sign-in, onboarding, and claim journey. Provider acceptance alone
   does not prove inbox delivery.

Gmail-only gifting is a separate product restriction. Verifying a sender domain
does not authorize adding Outlook or other recipient providers.

## References

- [Resend Rails integration](https://resend.com/docs/send-with-rails)
- [Resend Ruby integration](https://resend.com/docs/send-with-ruby)
- [Simulated delivery tests](https://resend.com/docs/dashboard/emails/send-test-emails)
