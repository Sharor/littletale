# Character Image Screening Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for the coupled persistence and generation tasks. Independent provider/UI work may use superpowers:subagent-driven-development. Follow TDD for each task.

**Goal:** Screen character requests once per identical input and user, expose admin review, and prevent duplicate paid generation.

**Architecture:** Reusable screening assessments hold immutable inputs and moderation decisions. Character-specific requests reference assessments and own generation attempts; append-only events preserve user-linked history. Workers claim work atomically and never automatically repeat uncertain paid requests.

**Tech Stack:** Rails 8, PostgreSQL, Active Job/Solid Queue, Active Storage, CarrierWave, Turbo, ruby-openai, Minitest.

**Spec:** `docs/superpowers/specs/2026-09-08-character-image-screening-design.md`

## Global constraints

- Run Rails and tests from WSL, with the isolated test databases on ports 5435 and 5436.
- Apply migrations immediately to development and test databases; restart running Rails processes after schema changes.
- Write failing behavioral tests before application changes and run the full `bin/rails test` before handoff.
- Never expose needs-review reasons to owners. Rejections must have a public reason.
- Review blocks only the affected request, never the owner account.
- Reuse identical assessment inputs within an owner across characters, but not across owners.
- Keep generation action counts separate from decision events; retain existing quota limits.
- Do not automatically retry a paid provider request with an uncertain outcome.
- Preserve existing completed characters and existing unrelated workspace changes.

## Task 1: Persist assessments, requests, decisions, and attempts

Files: new migration; `app/models/character_image_{assessment,request,decision,generation_attempt}.rb`; modify `app/models/{character,user}.rb`; new model tests.

Interfaces: `CharacterImageRequest.submit!(character)` returns the current request; `assessment.resolve!(outcome:, source:, internal_reason:, public_reason: nil, reviewer: nil)` appends a decision and resolves all current subscribers. Requests expose `screening_status`, `public_reason`, `current?`, and `generation_attempt`.

- [ ] Write tests for submission without generation usage, identical same-owner photo uploads across characters, separate owners, changed prompts, append-only outcome history, deletion retention, and unchanged submission reuse.
- [ ] Run `bin/rails test test/models/character_image_request_test.rb`; establish failures before implementation.
- [ ] Create the four record types plus the reusable assessment, immutable snapshot and fingerprint, unique indexes, optional retained character references, and user associations.
- [ ] Apply `bin/rails db:migrate` and `bin/rails db:prepare RAILS_ENV=test` immediately.
- [ ] Run focused model tests and inspect persisted state using assertions such as:

```ruby
assert_no_difference("ActionLog.count") { request = CharacterImageRequest.submit!(character) }
assert_equal "checking", character.reload.current_image_request.screening_status
assert_equal first.assessment_id, second.assessment_id
```

## Task 2: Moderate immutable inputs

Files: `app/services/character_image_moderation.rb`, `app/jobs/screen_character_image_job.rb`, provider and job tests.

Interface: `CharacterImageModeration.call(assessment)` returns a hash with `outcome`, `internal_reason`, `public_reason`, and sanitized `metadata`. `ScreenCharacterImageJob.perform(assessment_id)` claims and resolves one assessment.

- [ ] Write stubbed HTTP tests for clear/flagged results, invalid image bytes/type/size, malformed responses, text-only category coverage, timeout retries, and duplicate worker delivery.
- [ ] Run provider/job tests and observe failures.
- [ ] Validate actual image data, build text/image moderation input from the snapshot, route clear results to approved and flagged/uncertain results to review, and reject invalid uploads with a public reason.
- [ ] Implement at most three screening attempts with a durable claim; preserve deduplication through failures.
- [ ] Verify the important branch directly:

```ruby
assert_equal "needs_review", result.fetch(:outcome)
assert_nil result[:public_reason]
```

## Task 3: Reserve and execute paid generation once

Files: `app/services/character_image_generation.rb`, `app/jobs/generate_character_image_job.rb`, request/attempt models, `app/models/illustration.rb`, existing character job wrappers and tests.

Interfaces: `request.enqueue_generation!` atomically reserves usage and one attempt. `GenerateCharacterImageJob.perform(attempt_id)` claims only a current approved request. The generation adapter consumes the assessment snapshot and writes the result to the attempt before publishing to the character.

- [ ] Write failing tests for zero calls on unapproved/stale inputs, duplicate jobs, shared-owner quota races, valid completion, refusals, timeouts, malformed image output, and local persistence failure.
- [ ] Run focused tests.
- [ ] Lock owner/request in consistent order; reserve the attempt and existing `setup_illustration` action once. Claim the attempt atomically before the external call.
- [ ] Remove retry loops from character-generation paths; route legacy queued jobs through screening rather than direct generation.
- [ ] Persist provider refusal as a request-specific rejection event. Record uncertain outcomes without another external call. Require a usable persisted illustration before completed status.
- [ ] Verify replay behavior:

```ruby
2.times { GenerateCharacterImageJob.perform_now(attempt.id) }
assert_equal 1, provider_call_count
assert_equal 1, user.action_logs.for_action("setup_illustration").count
```

## Task 4: Integrate character creation and owner status

Files: character controller/model, illustration status partial, character index/edit/select views, owner status tests.

- [ ] Write failing tests for create/edit screening, persisted reload messages, immediate owner-scoped broadcasts, no internal reasons in HTML/JSON/Turbo, and replacement without duplicate work.
- [ ] Run focused controller/model tests.
- [ ] Replace direct generation dispatch with request submission; keep no-op edits from restarting generation.
- [ ] Render checking/review/rejection/failure/quota states from persisted public fields. Use an owner-scoped stream; avoid shared streams for private status.
- [ ] Verify rejection includes public explanation while pending review excludes internal evidence:

```ruby
assert_includes response.body, "waiting for an administrator"
assert_not_includes response.body, "private moderation evidence"
```

## Task 5: Add administrator review and rejection inspection

Files: `app/controllers/admin/character_image_assessments_controller.rb`, admin list/detail views, routes, console link, controller tests.

- [ ] Write failing tests for unauthenticated/non-admin access, rejection listing, source access, review resolution, required public rejection reason, double-clicks, and concurrent/stale decisions.
- [ ] Run the new controller tests.
- [ ] Add owner/status filtering, evidence/history display, protected source-photo delivery, and approve/reject actions for pending assessments.
- [ ] Resolve shared assessments once, notify current subscribers, and enqueue eligible requests through the existing guarded reservation method.
- [ ] Verify authorization has no side effect:

```ruby
assert_no_difference("CharacterImageDecision.count") { post approve_path }
assert_response :forbidden
```

## Task 6: Gate only dependent book work

Files: `app/models/book.rb`, character eligibility method, book/character selection controllers and views, book/page workers, tests.

Interface: `character.image_ready_for_book?` permits current approved completed images and usable legacy completed characters. `book.characters_ready_for_generation?` checks owner and eligibility for every selected character.

- [ ] Write failing tests for held requests, approved but unfinished images, stale inputs, cross-user IDs, legacy completed characters, and an unrelated eligible character/book for the same user.
- [ ] Run focused tests.
- [ ] Enforce eligibility in selection, book writes, and again before paid worker calls. Show actionable status for a dependent book without blocking unrelated books.
- [ ] Verify a held character does not affect another character's readiness or generation usage.

## Task 7: Recover interrupted local work and document rollout

Files: recovery job/rake task, operational README, focused recovery tests.

- [ ] Write failing tests for abandoned screening claims, reserved but unqueued attempts, and abandoned paid calls.
- [ ] Run recovery tests.
- [ ] Recover screening and unclaimed reservations safely; mark abandoned paid calls outcome_unknown without resubmission. Reuse already-returned image data for local processing when available.
- [ ] Document stopping old workers during rollout, migrations, restart, recovery command, and legacy handling.

## Task 8: Verify the complete workflow

- [ ] Run all focused tests for the modified paths.
- [ ] Run `bin/rails test` and resolve all failures with understood causes.
- [ ] Run `git diff --check` and review the changes against every spec section.
- [ ] Exercise upload, description, admin approval, rejection, replacement, and unrelated-user-work flows with stubbed provider responses.
- [ ] Report verified behavior and any remaining operational limitation; do not claim the app runs until database and runtime checks succeed.

## Execution notes

- Environment: the Windows Docker CLI started the isolated test services. Both development and test migrations were applied from WSL, and the running Rails server was restarted.
- Ruling: use a feature branch in the existing checkout to keep the active IDE and locally configured dependencies available; preserve user changes to AGENTS.md and codex-skills.


## Implementation and verification record

All eight implementation milestones are delivered. The checklist above records
how the work was broken down; the implementation uses `generation_model` rather
than Rails' reserved `model_name` attribute.

- Persistence, shared assessments, user-linked history, generation reservations,
  moderation/provider adapters, owner notifications, admin review, dependent-book
  gates, and recovery are implemented.
- Independent adapter/admin work was reviewed locally after subagent availability
  ended. Additional regression checks cover preserved moderation evidence, actual
  Turbo submissions, restored inputs, late results, and concurrent quota use.
- Final full suite: `bin/rails test` — 148 runs, 537 assertions, 0 failures,
  0 errors, 0 skips. Provider responses were stubbed; no paid image calls were made.
- Targeted RuboCop checked 23 feature Ruby files; formatting corrections applied.
  `git diff --check` passed.
- Local runtime smoke check after `bin/rails restart`: `/up` returned 200;
  `/admin/character_image_assessments` without login returned 403.
- Changes remain on `feature/character-image-screening`; no deployment or merge
  is part of this implementation. Existing user changes in AGENTS.md and
  codex-skills were preserved.
