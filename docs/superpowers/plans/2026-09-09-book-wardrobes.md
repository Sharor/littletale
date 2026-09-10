# Book wardrobe implementation

Approved scope: prefer one outfit per character across the whole story, but honor
explicit mixed activities and plan natural outfit transitions. Persist each outfit
and its dressed identity reference once per book generation; reuse them in original
pages and all page retries. Leave existing books and original characters unchanged.

1. Add attempt-scoped wardrobe plans, outfits, and stable page positions.
2. Plan the entire story and validate full character/page outfit coverage before paid reference generation.
3. Generate each distinct dressed reference once, retaining source snapshots and result attachments.
4. Gate page dispatch until every reference is ready; make duplicate jobs idempotent.
5. Use saved references and outfit instructions in original images and prompt revisions.
6. Surface preparation/failure state and retain audit data; recover unclaimed work without repeating uncertain paid calls.
7. Verify happy paths, mixed activities, legacy behavior, duplicate delivery, stale attempts, and failure handling.
8. Apply migration to development/test, restart Rails, run full suite and review.

Cost: one image call per distinct character/outfit in addition to existing page calls.
No paid provider calls during implementation verification. Visual consistency still
requires a real-provider visual check; prompt/reference reuse is tested locally.
