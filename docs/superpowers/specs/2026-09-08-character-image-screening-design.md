# Character image screening design

## Agreed outcome

Screen character creation requests before paid image generation. Automatically
approve clear requests, hold uncertain requests for an administrator, and reject
requests that fail the application's acceptance rules. Notify the owner as soon
as a decision is persisted. Rejections include a public reason; pending review
never exposes its reason to the owner. Administrators can inspect both review
cases and rejections. Preserve user-linked decision history for future reporting.

Needs review blocks only the affected request, never the owner's account. Other
eligible characters and books may generate normally. A book using the affected
character must wait or have that character removed.

Wardrobe changes during book creation are a separate feature. Future wardrobe
variants should belong to a book and reference the original character, without
overwriting its source photo or identity. This feature does not infer that
pyjamas caused a provider refusal or reject ordinary clothing by keyword.

## Existing integration points

- `Character#setup_illustration` queues either `CartoonImageJob` for a photo or
  `GenerateImageJob` for a description, then records a `setup_illustration`
  action against the user and character.
- `Illustration#cartoonify` uses `gpt-image-1`; description generation uses
  `dall-e-3`. The photo path has an unbounded retry loop. The description path
  retries errors, including potentially permanent refusals.
- Character generation currently has pending, in-progress, and completed states.
  It lacks screening and durable failure states.
- Book page generation already records provider moderation failures and exposes
  failed books to administrators. Character screening should use the existing
  administrator identity checks and console navigation.
- Character views use Turbo broadcasts, including a shared `characters` stream.
  New status delivery must be scoped to the owner and contain public fields only.

## Architecture and alternatives

Use a background screening job, a provider adapter, and a versioned application
decision policy. Persist each request's immutable inputs, screening outcome, and
generation attempt separately. Jobs receive a request identifier, not a mutable
character description fetched later.

A synchronous check would delay uploads and tie requests to provider latency.
A manual-only queue would avoid automatic decision rules but require an admin
for every character. The selected asynchronous hybrid allows ordinary requests
to proceed and keeps uncertain cases out of paid generation.

## Scope

Include photo and description creation, relevant edits, request deduplication,
user notifications, administrator review and rejection inspection, historical
decision events, generation accounting, provider refusal handling, and server-side
book eligibility checks for newly screened characters.

Exclude wardrobe generation, image model migration, mass screening or regenerating
existing characters, a reporting dashboard, email/push notifications, and a general
rewrite of book generation. Preserve existing book failure investigation.

## Persisted records

### Character image request

Create `CharacterImageRequest` with owner `user_id`, optional `character_id`, a
stable original character identifier, an immutable input fingerprint, source kind,
photo blob reference where applicable, exact prompt snapshot, provider/model,
screening policy version, and timestamps. Retain request records when characters
are deleted; do not cascade-delete their history. Retain the referenced source
while it is needed for review; do not duplicate image bytes in audit JSON or logs.

Use explicit screening states: `checking`, `approved`, `needs_review`, `rejected`.
Store a separate internal reason code/details and public rejection reason. Store
the moderation response identifier, returned model, supported input categories,
flags, and scores for admin inspection. Do not put credentials, base64 images,
or signed download URLs in diagnostic metadata.

Introduce a reusable screening assessment keyed by owner, actual photo content
checksum, exact effective prompt, image-generation model/options, and policy
version, with a database unique index. Reuploading identical image bytes, even
under another filename or for another character owned by the same user, looks up
this assessment before calling moderation. Reuse approved, needs-review, and
rejected results; join an in-flight check instead of starting another. Identical
assessments have one admin review case. Never share assessments across owners.

Character requests reference this assessment but retain separate generation
attempts and current-request pointers. An unchanged request for the same character
reuses its successful illustration without another paid attempt or decision event.
A different character reuses screening evidence but remains subject to normal
generation accounting. Changed prompts, model/options, or policy versions require
a fresh assessment even if the image is identical. Display-only edits do not
generate a new image. This release detects byte-identical uploads; resized or
re-encoded copies are distinct inputs.

Link decision events to the shared assessment as well as the originating request
and owner. Requests reusing an assessment reference its history rather than
recording another automatic decision. Preserve assessment evidence independently
of the originating character's lifetime. Provider generation outcomes remain
request-specific and do not rewrite the screening outcome for other characters.

### Decision events

Create append-only `CharacterImageDecision` records linked to the request and
owner, with outcome, source (`automatic`, `admin`, or `provider`), internal reason,
public rejection reason where applicable, reviewer user ID for admin decisions,
and timestamp. Record approval, referral to review, and rejection as separate
events. A review followed by approval retains both events. Duplicate delivery or
double-clicking an admin action must not append the same transition twice.

Keep these records separate from `ActionLog` generation usage. Add user
associations and query scopes for outcome, date, and source. This supports future
counts of decisions and distinct requests without confusing them with charges.

### Generation attempt

Create `CharacterImageGenerationAttempt`, uniquely linked to a request for this
release, with state (`reserved`, `in_progress`, `completed`, `failed`, or
`outcome_unknown`), timestamps, provider request ID, failure metadata, resulting
illustration reference, and a link to its single existing `setup_illustration`
action log. One request permits one automatic paid generation attempt.

Reserve the attempt and usage action atomically while locking the user and
request. Preserve existing per-user and per-character limits. Screening and
admin review do not consume image-generation allowances. A successful approval
may remain waiting if the user has no generation allowance; show that separately
from moderation rejection. Admin reviewers do not confer their own quota bypass
on the character's owner.

## Screening and initial decision rules

Validate uploaded file size, declared type, and actual decodability before
provider submission. Reject unsupported or unreadable uploads with a specific
replacement instruction. The moderation adapter checks the exact generation
prompt and source image when present.

Use provider category flags as signals under an explicit policy, not invented
probability thresholds. Initial policy:

- Valid, unflagged results approve automatically.
- Flagged moderation results go to admin review to allow contextual assessment
  and avoid automatically condemning ordinary family photos.
- Invalid uploads reject automatically; an administrator can reject a reviewed
  request with a required public reason.
- An explicit image-generation moderation refusal rejects that request, retaining
  its prior approval event. Report the provider's supported reason in plain
  language. If it gives no category, say that the image service declined the
  request without a more specific reason; do not invent one.
- Missing or malformed moderation results, unsupported assessment data, and
  exhausted transient screening errors hold the request for review. Never treat
  a failed check as approval or a network error as a content rejection.

Moderation retries may use at most three attempts with backoff. Recovery must
not create duplicate outcome events. A timeout in screening does not trigger
image generation.

The moderation endpoint supports text and images, but some categories, including
`sexual/minors`, are text-only. Zero values for unsupported image categories are
not evidence that those categories were assessed. Approval means the application
check passed, not a guarantee that the image provider will accept the request.

Reference: https://developers.openai.com/api/docs/guides/moderation

## Admin review

Add an administrator-only list and detail screen under the existing console.
Allow filtering by needs-review, rejected, approved, and owner. Show source image
or description, exact submitted prompt, internal evidence, decision history, and
generation outcome. Authorize both the page and source-image access.

Only an administrator may approve or reject a current needs-review request.
Rejection requires a public explanation and may include a separate internal
note. Persist reviewer identity. Resolve under a lock: conflicting reviewers and
repeated submissions cannot produce two decisions or two generation attempts.
Stale requests remain inspectable but cannot regenerate a changed character.
Resolve a shared assessment once and update all linked current requests waiting
on that assessment. Each request still requires its own atomic generation claim
and quota check; repeated notifications cannot launch duplicate generation.
Rejected requests remain inspectable; replacing the input creates a new request.
Admin approval never overrides an image provider's refusal of the same request.

## Owner experience

- Checking: `Checking your character image…`
- Needs review: `Your character image is waiting for an administrator to review it.`
- Rejected: `Your character image was rejected: [public reason]` and an edit or
  replace action.
- Approved and running: `Generating your character…`
- Generation failure: a clear failure message, distinct from content rejection.
- Unknown provider outcome: explain that generation could not be confirmed and
  has stopped to avoid another charge.

Broadcast public status immediately after commit through an owner-scoped Turbo
stream, and render the same persisted state on reload. A disconnected owner sees
the decision when they next open the app. No email or push delivery in this scope.
Do not expose internal needs-review reasons through HTML, JSON, hidden fields,
Turbo payloads, image URLs, or general-purpose model serialization.

## Paid generation and concurrency

Generation workers verify that their request is current and approved and then
atomically claim its reserved attempt before calling the provider. Replayed jobs
return without another call. Publish a generated image only if the request is
still current when the response arrives. An old response cannot replace a newer
character image or approve newer inputs.

Remove internal automatic retry loops from the two character image paths. Do
not automatically repeat a paid request after a refusal, timeout, connection
interruption, worker crash after claiming, or local persistence failure. A timeout
may occur after the provider accepted the request. Record `outcome_unknown` and
retain the usage reservation when the outcome cannot be established. Do not
promise exactly-once external billing without provider guarantees.

Persist and reuse returned image data when possible if local processing fails;
retrying local work must not call image generation again. Completion requires a
persisted, usable illustration, not merely the absence of a raised exception.
Use a recovery check to identify abandoned attempts without issuing a new paid
request. Record generation failures separately from screening outcomes except
for explicit provider moderation rejection.

## Book integration and existing data

New screened characters require a current approved request and its successfully
generated illustration before selection and generation. Enforce ownership and
eligibility on all book selection/create/update paths and recheck at background
job execution before paid work. Do not rely on disabled UI controls alone.

Existing completed characters with a usable illustration remain usable as legacy
characters without fabricated approval events. Existing images are not regenerated.
Editing generation inputs brings a legacy character into screening. Incomplete
legacy characters enter screening when generation is next requested. Drain or
stop old workers during rollout so old queued jobs cannot bypass the new gates;
compatibility handling routes old character jobs through screening.

## Milestones and validation

1. Persist request versions, decision events, and generation attempts with database
   uniqueness and user associations. Test retained history after character deletion.
2. Implement deterministic policy tests and a stubbed provider adapter for photo,
   prompt, malformed response, unsupported category, and timeout cases.
3. Integrate screening with creation and edits. Prove unapproved requests produce
   zero image API calls and zero generation usage logs.
   Test concurrent repeat uploads across the same owner's characters for checking,
   approved, review, and rejected assessments. Test filename changes, changed
   prompts/policies, and separate owners to verify correct assessment reuse.
4. Implement atomic reservation and worker claims. Test duplicate enqueues,
   simultaneous quota use, changed input during screening/generation, worker
   redelivery, provider refusal, and unknown outcomes.
5. Implement admin review and owner updates. Test authorization, double decisions,
   immediate broadcasts, reload behavior, and absence of internal review reasons
   in every owner-visible response.
6. Gate book selection and worker execution. Test cross-user IDs, pending/rejected
   requests, approved-but-unfinished images, and legacy completed characters.
   Prove one held request does not block another character or unrelated book
   belonging to the same owner.
7. Apply migrations from WSL to development and test databases, restart running
   Rails processes after schema changes, and document worker rollout/recovery.
8. Run focused tests for each change and the full `bin/rails test` before handoff.
   Exercise the upload, description, approval, rejection, and replacement flows.

Use TDD for every implementation task: demonstrate the failing behavioral test,
make the smallest change, then run the focused tests. Provider responses in tests
are stubbed; verification does not spend money generating images. Run Rails from
WSL and start only `test_db` and `test_worker_db` for tests. Preserve database
volumes and the user's current unrelated workspace changes.

## Limits

This filter reduces avoidable generation calls but cannot predict all provider
refusals or diagnose the reported clothing case without evidence. The initial
policy deliberately routes flagged content to administrators; it does not claim
that a moderation score proves a photo is inappropriate. Unknown paid outcomes
favor preventing duplicate charges over automatically restoring progress.
