# Resend setup and future domain switch

Status: the gifting feature sends through Resend using Action Mailer. This guide
covers the temporary sender and the later switch to a verified domain.

## Temporary setup

- Use `LittleTale <onboarding@resend.dev>` as the temporary test sender.
- Read the existing API key server-side from
  `Rails.application.credentials.dig(:smtp, :resend_api_key)`.
  Never copy the key into this file, source code, browser code, or logs.
- The `resend` gem is integrated through Rails Action Mailer. Production uses
  the `:resend` delivery method.
- `RESEND_FROM_EMAIL` configures the full From value and defaults to the
  temporary sender above.
- Development keeps its normal local delivery behavior unless
  `RESEND_DELIVERY_ENABLED=true` is set. When enabled, it sends through Resend.
- Keep automated tests on Action Mailer's `:test` delivery method. Use local
  mailer previews while hosting is unavailable.
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

The shared `resend.dev` sender can deliver real inbox tests only to the email
associated with the Resend account. It is not a temporary production sender for
arbitrary Gmail recipients. If that account email is not Gmail, the full gifting
flow cannot use it under the Gmail-only product rule; use previews and mocked
delivery until a domain is verified. Do not weaken recipient validation or
silently redirect gifts to a testing inbox.

Resend also supplies simulated delivery/bounce addresses under `resend.dev`.
Use these only in isolated transport tests, not as accepted gift recipients.

Development mail links currently use `localhost:3000`; these only work on the
machine running the app. Email delivery and publicly reachable invitation links
are separate requirements. Do not advertise local invitation links as usable by
remote recipients.

## Instructions for the next agent when domain and hosting are ready

1. Obtain the chosen sending domain, From address, and public application
   hostname from the user; do not invent them.
2. Add the sending domain in Resend and publish the DNS records Resend provides.
   Wait for verification. A sending subdomain may differ from the app hostname.
3. Set `RESEND_FROM_EMAIL` to `LittleTale <gifts@YOUR_VERIFIED_DOMAIN>` with the
   real domain substituted. Keep the API key in Rails credentials and ensure it
   has permission to send from this domain.
4. Configure the actual public HTTPS hostname for mailer URLs. Production
   currently reads `ENV["HOSTS"]` in
   `config/environments/production.rb`; confirm it is one valid hostname for URL
   generation, not a comma-separated list. Check allowed hosts and Google OAuth
   callback configuration for the deployed app too.
5. Restart web and queue workers so both use the new sender and URL settings.
6. Run mailer, claim-flow, and full Rails tests from WSL. Check both languages,
   the exact email copy, the From value, and generated HTTPS invitation URLs.
7. After the user explicitly authorizes a live test and names a Gmail recipient,
   send one test gift. Confirm receipt and the full Google signup/login,
   onboarding, and gift-claim journey. API acceptance alone is not proof of
   inbox delivery. Never send real mail as part of automated tests.
8. Update the deployed `RESEND_FROM_EMAIL` value. Remove the temporary sender
   from deployed configuration and check that it cannot silently reappear in
   production.

Gmail-only gifting is a separate product restriction. Verifying a sender domain
does not authorize adding Outlook or other recipient providers.

## References

- [Resend Rails integration](https://resend.com/docs/send-with-rails)
- [Resend Ruby integration](https://resend.com/docs/send-with-ruby)
- [Shared sender restrictions](https://resend.com/docs/knowledge-base/403-error-resend-dev-domain)
- [Simulated delivery tests](https://resend.com/docs/dashboard/emails/send-test-emails)
