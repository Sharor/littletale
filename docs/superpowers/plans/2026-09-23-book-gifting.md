# Book gifting plan

Status: implemented on `feature/book-gifting`; focused and full test suites pass.

## Intent and approach

Let a creator gift a completed, paid-for book by email or a copied invitation
link. Keep original ownership and generation costs with the creator. Grant the
matching Gmail account permanent read access after Google signup/login, without
starting a trial, spending recipient credits, or requiring a subscription. Retain
an immutable gifted edition of the text and images so deletion, regeneration,
account changes, or later owner actions cannot take the gift away.

## Confirmed requirements

- Only completed books funded by actual payment qualify. A paid user tier alone
  is insufficient; trial-funded and unfunded admin books do not qualify.
- Require recipient name, recipient email, sender callname, and giftcard message
  for both email and copied-link gifts.
- Accept only `gmail.com` recipient addresses for now, validated server-side as
  well as in the form. Outlook support is deferred.
- Use existing Google authentication. Require the authenticated verified email
  to match the invitation recipient; possession of a link alone is insufficient.
- Gifts survive owner deletion and other owner actions. Do not offer sender
  revocation of issued gifts. Persist the gift before sending so delivery errors
  do not destroy it. Pending invitations must also survive source deletion.
- Default gift language to the sender's settings, with English/Danish selection.
  Provide editable localized default gift text. Changing language must not
  overwrite an already customized message.
- Keep recipients' access independent of trial expiry and subscription status.

## Scope boundaries

In scope: eligibility checks, retained gifted editions and assets, email-bound
invitations, Google claim flow, read-only gift library, giftcard form and preview,
localized email, copied invitation links, delivery failure/retry handling, tests,
and the Resend setup guide at `/resend.md`.

Out of scope: ownership transfer, recipient editing or regeneration, anonymous
reading, Outlook login/recipients, new email authentication, scheduled sending,
printing, buying an existing trial book, and unrelated billing changes.

## Design decisions

### Retention and ownership

Keep the original `Book.user_id` and funding associations unchanged. Introduce a
retained edition containing the finished title, ordered page text, and durable
image assets. It is a read-only publication, not a second generated book and not
a recipient-owned `Book` that could enter funding or trial calculations.

Create the edition when issuing the gift, before a link or email is made
available. Reuse an edition for the same unchanged source content where practical.
Do not treat mutable source URLs as retained assets: deletion and image
replacement must leave the gifted images available. Failed asset retention must
not publish a broken invitation. Keep source/sender references optional for
retention purposes and preserve the sender callname on the gift itself.

Alternative considered: retain the original book using soft deletion. This is
smaller initially but leaves recipient content coupled to owner regeneration and
edits. An immutable edition better satisfies permanent gifting.

### Eligibility and claiming

Check a consumed book-credit reservation backed by a paid purchase or a paid
subscription period. Verify the actual funding-source fields during
implementation. Never infer payment from user tier or completion alone.

Each invitation references a retained edition, recipient details, sender
callname, message, locale, token digest, claim timestamp, recipient user, and
delivery state. Generate unpredictable tokens; do not expose them in logs or
analytics. Enforce uniqueness and transactional claiming so retries or concurrent
requests cannot create duplicate grants or change the recipient.

Normalize surrounding whitespace and case when matching email. Proposed first
release rule: do not strip Gmail dots or plus tags; ask senders to use the exact
email shown on the recipient's Google account. Reject lookalike domains and
non-Gmail Google Workspace addresses. Verify the Google email-verification signal
before authorizing a claim.

Preserve the invitation through OAuth, terms, and profile onboarding. An explicit
authenticated POST claims the invitation; GET requests and email scanners cannot
consume it. Wrong-account users receive a switch-account path without access to
book content. Proposed default: issued invitations do not expire; future link
rotation must preserve the underlying gift entitlement.

### Reading and trial access

Use dedicated received-gift library and reader routes, reusing suitable reader
presentation. Keep owner mutation routes scoped to `current_user.books`. Exempt
only gift access and its necessary onboarding steps from the expired-trial gate.
Do not subscribe recipient readers to owner book/editor Turbo streams or expose
generation controls. Reading must not depend on the original owner still existing.

### Email

English subject: `You got a gift from <user callname>!`

English body:

> Hello <name>, You have a gift from LittleTale!
>
> <custom message>
>
> [Create an account or sign in to open your gift]
>
> Hugs from your friends at LittleTale and <user callname>

Use configurable app branding, localized templates, escaped user text, and HTML
and plain-text versions. Keep the gift locale stable across background delivery.
Use Resend through Action Mailer with the existing `smtp.resend_api_key`
credential. Follow `/resend.md` for the temporary test sender and domain switch.
Distinguish queued, provider-accepted, and failed delivery; do not label API
acceptance as confirmed inbox delivery. Bound retries and prevent duplicate
submissions from generating uncontrolled mail sends.

## Sequential milestones and checklist

1. Verify funding evidence, Google verified-email handling, uploader deletion
   behavior, onboarding redirects, and reader/stream dependencies; write failing
   eligibility and authorization tests before implementation.
2. Add retained-edition and invitation persistence with validation, indexes, and
   durable asset retention. Apply migrations immediately from WSL with
   `bin/rails db:migrate` and `bin/rails db:prepare RAILS_ENV=test`; restart running
   Rails processes after schema changes.
3. Implement owner-only gift issuance for completed paid books, creating the
   retained edition before publishing a token. Test rejected trial/admin books
   and prove no extra creator or recipient charge.
4. Implement Gmail validation, verified-email matching, atomic claiming, and
   invitation continuity through existing Google authentication and onboarding.
5. Implement the received-gift library and reader with narrowly scoped trial
   exceptions; prove permanent access after source deletion, owner changes, and
   source regeneration, including retained images.
6. Build the mandatory giftcard form, editable localized message, preview, email
   action, and copy-link action using existing storybook tokens and typography.
7. Add Resend delivery, mailer previews, localized HTML/plain-text templates, and
   visible send failure/retry handling, following the root setup guide.
8. Run focused tests after each change, then `bin/rails test` from WSL. Verify
   phone/desktop layouts, keyboard use, and unchanged sidebar styling. Stop and
   ask if any failing test's intended behavior or cause is uncertain.
9. Validate configuration and queue processing locally, then follow `resend.md`
   for the verified-domain and public-host rollout. Keep real email testing
   separate from automated tests and require an explicitly authorized recipient.

## Validation and risks

- Prove paid purchase and subscription-funded eligibility; reject trial credits,
  unfinished books, released reservations, and unpaid sources.
- Prove required fields, Gmail-only addresses, email normalization, wrong-account
  rejection, unverified-email rejection, and OAuth cancellation/retry behavior.
- Exercise concurrent/repeated claims, invalid tokens, forwarded links, email
  scanners, duplicate send submissions, queue failures, and provider errors.
- Assert unchanged trial dates, credit balances, ownership, and funding records
  after invitation creation, claim, and reading.
- Prove pending and claimed gifts and all their image assets remain usable after
  source deletion, source updates, owner removal where supported, and subscription
  expiry. Owner deletion must not cascade into retained editions or invitations.
- Check HTML/JSON access and Turbo subscriptions; recipients cannot edit,
  regenerate, delete the original, access owner character data, or issue gifts.
- Verify both languages and preservation of custom text after language changes.
- Asset retention adds storage cost and needs explicit cleanup rules for failed
  edition creation. Do not purge retained assets referenced by issued gifts.
- Live delivery to arbitrary recipients remains blocked by Resend until a sending
  domain is verified; remote claiming also requires a reachable application URL.
- Proposed defaults needing review: exact Gmail matching without alias folding,
  non-expiring invitations, and immutable content as of gift issuance.
