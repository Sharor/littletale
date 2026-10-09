# Book fonts and generation wizard

Status: implemented on 2026-10-09.

## Intent and approach

Extend the existing Rails book-generation form with a Stimulus wizard and a
font catalogue modeled on `BookArtStyle`. Keep one form mounted so navigation
preserves every field. Save incomplete input and the current step as a browser
draft; submit through the existing book creation endpoint only when the user
chooses Generate. Recommended persistence is same-browser recovery, pending
the user's preference about account-backed drafts.

## Scope boundaries

In scope:

- Font cards with real text previews, initially EB Garamond (default) and Inter,
  using the bundled font files. The selection controls story body text; cover
  headings and application controls retain the established typography.
- Persist a validated font key on new books, fixed after creation like art style.
  Retain it in new gift and print snapshots so copies survive source deletion.
- Five steps, in order: Reader (language, age and page count), Art style, Font,
  Story (title and plot), and Review (all choices plus the selected characters).
- Previous, Next, and a clickable step navigator. Allow free movement between
  steps, including partially completed ones; validate the whole form before
  generation and open the first step containing an error.
- Automatically save all editable fields, character IDs, and the active step
  after input changes and before navigation. Restore incomplete drafts after
  refresh; offer Start over and show whether progress was saved.
- Retain the current character-selection entry flow, funding checks, tier
  limits, parental approval, localization, and storybook design tokens.

Out of scope:

- Font uploads, a large font library, font-size controls, and changing fonts on
  existing books.
- Reworking character creation, book editing/regeneration, or generation jobs.
- Multiple named drafts or cross-device synchronization in the recommended
  browser-draft version.
- Regenerating existing print artifacts or changing legacy editions' appearance.

## Action checklist and milestones

### 1. Specify and prove the behavior

1. Confirm draft persistence scope and the initial font set. Trace the current
   form, reader, gift reader, print snapshots, and tutorial hooks; preserve
   existing user edits in the workspace.
2. Write failing model/controller and browser tests for font selection, step
   navigation, incomplete-draft refresh recovery, error recovery, and final
   submission. Add JavaScript tests for draft restoration and cleanup.

### 2. Implement fonts and retained editions

3. Add a `BookFont` catalogue with stable keys and explicit web/PDF mappings;
   add book and snapshot font fields and validations. Keep legacy books in
   EB Garamond and legacy print orders in Inter. Apply the additive migration
   immediately with `bin/rails db:migrate` and
   `bin/rails db:prepare RAILS_ENV=test` from WSL; restart running Rails processes.
4. Add accessible font radio cards and render the selected story font in the
   book reader, new gift copies, print previews, and PDF interiors. Use bundled
   fonts for previews and retain fallback behavior for story samples.

### 3. Implement navigation and draft recovery

5. Organize `books/new` into the five steps with one mounted form, a responsive
   step navigator, Previous/Next controls, and an editable review summary.
   Preserve the full-form fallback when JavaScript is unavailable.
6. Implement a focused Stimulus controller for navigation, focus management,
   review updates, and validation. Save without creating books, reserving
   credits, requesting parental approval, or enqueueing jobs.
7. Implement versioned, user-scoped browser drafts with input/change saves and
   a final flush before refresh/navigation. Restore selections and previews,
   handle unavailable storage, and clear only after successful creation or
   Start over. Server-rendered submission errors take precedence over cached
   values; explicit new character selections take precedence over stale IDs.

### 4. Validate and hand off

8. Run focused Rails, JavaScript, and browser tests. Verify both font choices,
   snapshot independence, supported-language glyphs, long-story pagination,
   refreshed incomplete forms, and recovery after rejected submissions.
9. Compare the wizard, character-selection page, and reader at phone and desktop
   widths, including keyboard navigation and unchanged sidebar styling. Build
   affected assets and run the full `bin/rails test` suite before handoff.

## Validation and risks

- Preserve blank values, unchecked controls, and partial numeric input in drafts;
  do not require a valid book to save progress.
- Restore the same active step and synchronize art/font previews. Navigation
  and Enter on intermediate steps must never submit generation accidentally.
- On final submission, validate hidden-step fields explicitly and reveal/focus
  the first invalid field. Preserve all input on validation, funding, parental
  approval, or network errors. Prevent repeated clicks from submitting twice.
- Filter restored character IDs against current ownership/readiness. Recheck
  tier limits and access on submission; cached values cannot grant permission.
- Handle malformed/outdated drafts, storage failures, changed users, and
  competing browser tabs without silently replacing the active form.
- Preserve legacy reader and PDF typography, including retained copies without
  a source book. Different fonts can alter PDF page counts; test existing page
  limits and verify Danish, English, Greek, and Spanish text.
- Draft recovery across devices requires account-backed persistence and draft
  endpoints; revise the persistence milestone if that option is selected.
- Follow TDD for each implementation slice. If a test failure has an uncertain
  cause or intended behavior, stop and ask for direction. Never reset or
  replace development/production databases.

Completion means the chosen font reaches new editions, all five steps are
freely navigable without input loss, refresh restores incomplete progress,
only Generate starts creation, and the required tests and visual checks pass.
