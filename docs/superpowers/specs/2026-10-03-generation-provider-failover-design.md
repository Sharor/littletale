# Generation Provider Failover Design

## Intent

LittleStories must keep generating stories and illustrations during a sustained OpenAI outage. An administrator can route generation through OpenAI or Gemini, or enable automatic routing that begins on OpenAI and changes future requests to Gemini when OpenAI is consistently unavailable.

Success means every active text, image, and character-screening provider call honors the same global provider choice; the application records enough outcomes to make the automatic decision safely; and existing credit, retry, and uncertain-outcome protections remain intact.

## Provider eligibility and rollout constraints

Gemini image generation is paid-only. Production therefore uses a paid Gemini API project and a `GEMINI_API_KEY`. The integration uses Google's stateless Interactions API (`store: false`) so it does not opt into server-side conversation storage.

Google's Gemini API terms prohibit API clients directed toward or likely accessed by people under 18. LittleStories currently permits users aged 13 and older. Provider routing can be implemented and tested while OpenAI remains the default, but production activation of Gemini requires the product owner to resolve that eligibility mismatch. This design does not silently change the application's audience, terms, or age controls.

## Scope

In scope:

- Story generation, wardrobe planning, categorization, prompt revision, character screening, character images, wardrobe references, and page illustrations.
- Admin choices for `openai`, `gemini`, and `automatic`.
- Automatic OpenAI-to-Gemini switching after 16 availability failures among the latest 20 eligible OpenAI requests made since Automatic was enabled.
- Persistent provider request history, current routing state, switch reason, and switch time.
- OpenAI and Gemini connection checks on the admin dashboard.
- Deployment configuration and operational documentation for Gemini credentials and models.

Out of scope:

- Automatically returning from Gemini to OpenAI.
- Retrying the request that caused the threshold to be crossed.
- Routing between different providers inside one book or image request after that request starts.
- More providers, per-user routing, cost accounting, or provider quality scoring.
- Reworking existing book, character, credit, retry, or storage state machines.
- Changing the product's age policy without an explicit product decision.

## Architecture

### Compatibility client

`GenerationProviders.client(operation:)` returns an OpenAI-compatible facade with `chat`, `moderations`, `images.generate`, and `images.edit`. Existing generation services keep their current request and response shapes while selecting a provider through this facade.

The OpenAI adapter delegates to the existing `ruby-openai` client. The Gemini adapter calls the Gemini Interactions REST API through Faraday and normalizes successful text, image, and moderation responses into the shapes the existing services consume. Provider-specific request construction, response parsing, and error normalization stay inside their adapters.

The Gemini text model defaults to `gemini-3.8-flash`, and the image model defaults to `gemini-3.1-flash-image`. `GEMINI_TEXT_MODEL` and `GEMINI_IMAGE_MODEL` can override them without a code release. Gemini calls use `store: false`. Structured story, wardrobe, categorization, and screening calls use explicit JSON schemas and application validation still checks semantic correctness.

### Persistent routing state

`generation_provider_settings` contains one global row with:

- `mode`: `openai`, `gemini`, or `automatic`.
- `active_provider`: the provider used in Automatic mode.
- `automatic_window_started_at`: excludes requests that began before Automatic was enabled or reset.
- `switched_at` and `switch_reason`: admin-visible audit context.

The table is created additively and the row is created lazily with OpenAI defaults. An old application version ignores both new tables, so an overlapping deploy remains safe. The application must be rolled back before rolling back this migration because dropping the new tables destroys routing history.

`generation_provider_requests` is an append-only operational log containing provider, model, operation, outcome, HTTP status, error class, external request ID, and start/finish times. It stores no prompts, images, story text, or provider response bodies.

### Routing and threshold

A request captures the active provider at its start and retains that provider until it finishes. Changing the admin setting never moves an in-flight request.

Only these outcomes are eligible for the 20-request window:

- `succeeded`
- `availability_failure`

An availability failure is a connection failure, timeout, HTTP 429, or HTTP 5xx response. Content refusals, malformed responses, authentication or configuration failures, and other HTTP 4xx responses remain visible but do not enter the window.

After each eligible OpenAI result, the setting row is locked and the latest 20 eligible OpenAI requests whose `started_at` is at or after `automatic_window_started_at` are examined. With fewer than 20 observations, routing does not change. Once at least 20 observations exist, 16 or more availability failures in the latest 20 atomically change `active_provider` to Gemini and record the reason and time. Concurrent workers can record outcomes, but only the locked setting transition can switch providers.

Selecting OpenAI or Gemini routes future calls directly to that provider. Selecting Automatic resets the observation window and begins with OpenAI. Returning to OpenAI is an explicit admin action in this release.

### Error and retry behavior

The compatibility client records the outcome after a provider call and re-raises the original normalized error. Failure-history persistence must never replace a successful provider response or mask the original provider error.

Gemini safety blocks normalize to the existing content-refusal path. Gemini character screening sends the prompt and optional uploaded photo to a structured classifier. It automatically approves only a complete, unflagged result; flagged, blocked, incomplete, or ambiguous results enter the existing admin-review or unavailable paths.

Automatic switching affects the next request only. Existing rules continue to hold:

- A provider timeout or lost response does not trigger an automatic paid image replay.
- Character and wardrobe image requests with uncertain outcomes remain `outcome_unknown`.
- Page illustration reservations and retry limits do not change.
- Content refusals do not count as provider downtime.

## Admin experience

The admin dashboard shows a generation-provider panel using the existing storybook tokens and semantic controls. It displays the selected mode, actual active provider, eligible OpenAI failures out of the current window, switch reason/time, and whether both credentials are configured.

An admin-only update action changes the mode. Gemini and Automatic cannot be selected without the required Gemini credential; Automatic also requires OpenAI credentials. Missing configuration returns a visible validation message and leaves routing unchanged.

The production-health section gains a Gemini metadata check that authenticates without generating content. Health checks are never entered into generation history.

## Validation

Automated tests must cover:

- Default OpenAI behavior and manual OpenAI/Gemini selection.
- Automatic mode with fewer than 20 eligible observations, 15/20 failures, and 16/20 failures.
- Exclusion of refusals, invalid responses, authentication failures, health checks, and pre-window/in-flight requests.
- A concurrency-safe single switch and no automatic return.
- Gemini text, structured JSON, multiple-reference image, screening, successful parsing, content refusal, malformed response, timeout, 429, and 5xx contracts through WebMock.
- All active generation call sites routing through the compatibility client.
- Admin authorization, missing-credential validation, provider status rendering, and both health checks.
- Existing credit, retry, refusal, and uncertain-outcome tests.

Run `bin/rails db:migrate`, `bin/rails db:prepare RAILS_ENV=test`, focused provider and generation tests, and the complete `bin/rails test` suite from WSL. Restart Rails and every worker after the migration so all processes use the provider facade.

Production rollout keeps the initial mode at OpenAI. Configure and verify the paid Gemini project first, run both admin health checks, manually exercise representative text, screening, reference-image, and page-image operations with Gemini, then enable Automatic.
