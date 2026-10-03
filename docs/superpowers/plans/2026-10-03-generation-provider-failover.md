# Generation Provider Failover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add administrator-controlled OpenAI/Gemini routing and automatically route future generation requests to Gemini after 16 availability failures among the latest 20 eligible OpenAI requests.

**Architecture:** Add an OpenAI-compatible provider facade so existing generation state machines retain their behavior while adapters own provider-specific HTTP contracts. Persist a singleton routing setting and append-only outcome history; evaluate the automatic threshold under a database lock after each eligible OpenAI result.

**Tech Stack:** Rails 8, Active Record/SQLite, Faraday, ruby-openai, Minitest, WebMock, ERB/Tailwind.

**Spec:** `docs/superpowers/specs/2026-10-03-generation-provider-failover-design.md`

## Global Constraints

- Run Rails and all `bin/rails` commands from WSL.
- Use test-driven development for every task and run `bin/rails test` before handoff.
- Apply the additive migration to development and test immediately; never reset, drop, replace, or schema-load a non-test database.
- Keep OpenAI as the default and do not activate Gemini automatically during deployment.
- Never replay the request that crosses the threshold or any uncertain paid image request.
- Store no prompts, images, story text, or provider response bodies in provider request history.
- Use `GEMINI_API_KEY`; default text/image models are `gemini-3.8-flash` and `gemini-3.1-flash-image`, with environment overrides.
- Send Gemini interactions with `store: false`.
- Preserve existing storybook design tokens, EB Garamond display text, Inter body/actions, and `--fable-wine` action/focus styling.
- Production Gemini activation remains blocked on the product owner's resolution of Google's under-18 API-client restriction.

## Review Focus

- A request that started before Automatic was enabled must not enter the new observation window; cover in Task 1.
- Concurrent qualifying outcomes must produce one stable switch without corrupting the singleton setting; cover in Task 1.
- A tracking-write failure must not mask a successful provider result or replace the original provider exception; cover in Task 2.
- A Gemini completed response without the required text/image block must be an invalid response and must not count as downtime; cover in Task 3.
- Switching providers while an image call is running must not replay or reroute that request; cover in Task 4.

---

### Task 1: Persistent routing state and threshold

**Files:**
- Create: `db/migrate/20261003120000_add_generation_provider_routing.rb`
- Create: `app/models/generation_provider_setting.rb`
- Create: `app/models/generation_provider_request.rb`
- Create: `test/models/generation_provider_setting_test.rb`
- Modify: `db/schema.rb`

**Interfaces:**
- Produces: `GenerationProviderSetting.current`, `#provider`, `#change_mode!(mode)`, and `#evaluate_automatic_switch!`; `GenerationProviderRequest.record!(provider:, operation:, model:, outcome:, started_at:, finished_at:, http_status: nil, error_class: nil, external_request_id: nil)`.
- Consumes: no new interfaces.

- [ ] **Step 1: Write failing routing-state tests** for lazy OpenAI defaults, direct manual modes, Automatic resetting to OpenAI, fewer than 20 observations, 15/20 failures, 16/20 failures, excluded outcomes, pre-window requests, no automatic return, and concurrent evaluation producing one switch.
- [ ] **Step 2: Run `bin/rails test test/models/generation_provider_setting_test.rb`** and confirm failures are caused by missing tables/classes.
- [ ] **Step 3: Add the reversible migration and models** with exact enums/validations, a unique singleton key, append-only request data, indexed eligible-window lookup, and locked threshold evaluation.
- [ ] **Step 4: Run `bin/rails db:migrate` and `bin/rails db:prepare RAILS_ENV=test`** from WSL, then rerun the focused model test and expect green.
- [ ] **Step 5: Commit** with `feat: add generation provider routing state`.

### Task 2: Provider facade, OpenAI adapter, and outcome recording

**Files:**
- Create: `app/services/generation_providers.rb`
- Create: `app/services/generation_providers/client.rb`
- Create: `app/services/generation_providers/openai.rb`
- Create: `app/services/generation_providers/errors.rb`
- Create: `test/services/generation_providers/client_test.rb`
- Create: `test/services/generation_providers/openai_test.rb`

**Interfaces:**
- Consumes: `GenerationProviderSetting.current.provider` and `GenerationProviderRequest.record!` from Task 1.
- Produces: `GenerationProviders.client(operation:)`; facade methods `#chat(parameters:)`, `#moderations(parameters:)`, `#images`, `#generate(parameters:)`, and `#edit(parameters:)`; normalized `GenerationProviders::InvalidResponse` and `GenerationProviders::ContentRejected` errors.

- [ ] **Step 1: Write failing facade tests** proving provider capture at request start, OpenAI parameter/response pass-through, success/refusal/configuration/request/availability/invalid outcomes, request metadata sanitization, and that tracking failures preserve provider results and original exceptions.
- [ ] **Step 2: Run `bin/rails test test/services/generation_providers/client_test.rb test/services/generation_providers/openai_test.rb`** and confirm missing-interface failures.
- [ ] **Step 3: Implement the smallest facade and OpenAI adapter** with capability response validation and error classification; record outcomes after calls without storing request or response bodies.
- [ ] **Step 4: Rerun the focused tests** and expect green.
- [ ] **Step 5: Commit** with `feat: route provider calls through tracked facade`.

### Task 3: Gemini Interactions adapter

**Files:**
- Create: `app/services/generation_providers/gemini.rb`
- Create: `test/services/generation_providers/gemini_test.rb`

**Interfaces:**
- Consumes: the facade adapter contract and normalized errors from Task 2.
- Produces: OpenAI-compatible `chat`, image, and moderation responses backed by `POST /v1beta/interactions`, using `GEMINI_API_KEY`, `GEMINI_TEXT_MODEL`, and `GEMINI_IMAGE_MODEL`.

- [ ] **Step 1: Write failing WebMock contract tests** for plain and structured text, message/system conversion, `store: false`, model overrides, image generation/editing with multiple inline references, character screening with and without a photo, response normalization, request IDs, explicit safety rejection, missing output blocks, timeout, 429, and 5xx.
- [ ] **Step 2: Run `bin/rails test test/services/generation_providers/gemini_test.rb`** and confirm the adapter is missing.
- [ ] **Step 3: Implement the Faraday adapter** with explicit JSON schemas by operation, base64 media handling, no prompt/body logging, normalized OpenAI-shaped results, and sanitized provider errors.
- [ ] **Step 4: Rerun the Gemini and facade tests** and expect green.
- [ ] **Step 5: Commit** with `feat: add Gemini generation adapter`.

### Task 4: Route every generation call site

**Files:**
- Modify: `app/models/chatgpt.rb`
- Modify: `app/models/illustration.rb`
- Modify: `app/services/book_categorization.rb`
- Modify: `app/services/book_wardrobe_image_generation.rb`
- Modify: `app/services/book_wardrobe_planner.rb`
- Modify: `app/services/character_image_generation.rb`
- Modify: `app/services/character_image_moderation.rb`
- Modify: `test/models/chatgpt_test.rb`
- Modify: `test/models/illustration_test.rb`
- Modify: `test/services/book_categorization_test.rb`
- Modify: `test/services/book_wardrobe_image_generation_test.rb`
- Modify: `test/services/book_wardrobe_planner_test.rb`
- Modify: `test/services/character_image_generation_test.rb`
- Modify: `test/services/character_image_moderation_test.rb`
- Modify: `test/services/page_illustration_prompt_test.rb`

**Interfaces:**
- Consumes: `GenerationProviders.client(operation:)` from Task 2 and Gemini normalization from Task 3.
- Produces: all active provider calls use named operations through the facade while retaining current service return values and state transitions.

- [ ] **Step 1: Add failing integration assertions** showing each default client is the provider facade, an in-flight client retains its starting provider after an admin switch, and normalized Gemini safety blocks enter existing refusal/review paths.
- [ ] **Step 2: Run the affected model/service test files** and confirm the new routing assertions fail while existing behavior remains characterized.
- [ ] **Step 3: Replace direct `OpenAI::Client` construction** with operation-named facade clients, retaining dependency-injection seams and existing response validation.
- [ ] **Step 4: Run all affected model/service tests** and expect green, including credits, retries, moderation refusals, and unknown paid outcomes.
- [ ] **Step 5: Commit** with `feat: apply provider routing to generation flows`.

### Task 5: Admin controls and Gemini health check

**Files:**
- Create: `app/controllers/admin/generation_providers_controller.rb`
- Create: `app/services/health_checks/gemini.rb`
- Create: `test/controllers/admin/generation_providers_controller_test.rb`
- Create: `test/services/health_checks/gemini_test.rb`
- Modify: `app/controllers/admin/dashboard_controller.rb`
- Modify: `app/controllers/admin/health_checks_controller.rb`
- Modify: `app/views/admin/dashboard/index.html.erb`
- Modify: `config/routes.rb`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/da.yml`
- Modify: `config/locales/el.yml`
- Modify: `test/controllers/admin/dashboard_controller_test.rb`
- Modify: `test/controllers/admin/health_checks_controller_test.rb`

**Interfaces:**
- Consumes: routing setting/history from Task 1.
- Produces: admin-only `PATCH /admin/generation_provider`, provider dashboard status, credential validation, and non-generating Gemini metadata health check.

- [ ] **Step 1: Write failing controller/view/health tests** for authorization, all three modes, missing Gemini/OpenAI credential validation, unchanged state on rejection, status/window/switch rendering, Gemini health outcomes, and health-check exclusion from generation history.
- [ ] **Step 2: Run the focused controller and health tests** and confirm missing route/controller/service/UI failures.
- [ ] **Step 3: Implement the admin action, dashboard panel, translations, and Gemini check** using shared semantic classes and a responsive layout that leaves the sidebar untouched.
- [ ] **Step 4: Run the focused tests plus `test/controllers/localization_test.rb`** and expect green.
- [ ] **Step 5: Commit** with `feat: add admin provider controls`.

### Task 6: Deployment documentation and complete verification

**Files:**
- Modify: `.kamal/secrets.example`
- Modify: `config/deploy.yml`
- Modify: `README.md`
- Modify: `future.md`

**Interfaces:**
- Consumes: configuration and rollout requirements from Tasks 1-5.
- Produces: operator steps for credentials, model overrides, migration/restart, health verification, manual Gemini smoke tests, Automatic enablement, manual rollback, and the unresolved under-18 activation prerequisite.

- [ ] **Step 1: Update deployment examples and operations documentation** without real credentials; mark the roadmap item implemented but activation-dependent.
- [ ] **Step 2: Run `bin/rails test`** and require 0 failures and 0 errors.
- [ ] **Step 3: Run `bin/rails routes | rg generation_provider` and `bin/rails runner 'puts GenerationProviderSetting.current.attributes.slice("mode", "active_provider").to_json'`** to verify boot, route, and additive development data.
- [ ] **Step 4: Inspect the final diff** for prompt/image leakage, untracked direct OpenAI construction, unsafe request replay, locale gaps, and unrelated changes.
- [ ] **Step 5: Commit** with `docs: add provider failover operations guide`.
