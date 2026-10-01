# Lulu sandbox Orders operations

Orders is an administrator-only pilot that sends retained storybook editions to Lulu's sandbox. The integration is permanently pinned to `https://api.sandbox.lulu.com`; production Lulu orders require a separate code change and rollout.

The pilot supports one copy of one fixed 5 × 8 inch premium-color saddle-stitch booklet per order. The Lulu product identifier is `0500X0800.FC.PRE.SS.060UW444.GXX`. Interior files contain 4–48 pages in multiples of four, and the app adds only the blank pages needed for binding.

## Configuration

Store the sandbox API credentials in the encrypted Rails credentials for the deployed environment:

```yaml
lulu:
  client: sandbox_client_id
  secret: sandbox_client_secret
```

The application reads these through `RAILS_MASTER_KEY`; no Lulu secret belongs in `.kamal/secrets` or `config/deploy.yml`.

Kamal supplies two non-secret settings:

```yaml
LULU_ORDERS_ENABLED: "false"
LULU_ASSET_HOST: "https://littletale.com"
```

`LULU_ASSET_HOST` must be a public HTTPS origin that routes to this application. Lulu receives artifact-specific signed URLs for the retained interior and cover PDFs. Each URL expires after six hours and exposes no order or delivery data. Normal order pages and PDF previews still require an enabled administrator session.

Before enabling the pilot, verify configuration from the deployed Rails console without printing either credential:

```ruby
Lulu::Configuration.base_url
# => "https://api.sandbox.lulu.com"
Lulu::Configuration.credentials_ready?
# => true
Lulu::Configuration.asset_host_ready?
# => true
```

## Rollout

1. Keep `LULU_ORDERS_ENABLED` set to `"false"` for the first deployment.
2. Deploy the release so its migrations, public artifact route, and jobs are present. Restart any standalone Rails or job process after migration; the current Kamal setup runs Solid Queue through Puma with `SOLID_QUEUE_IN_PUMA=true`.
3. Confirm `GET /up` succeeds at `LULU_ASSET_HOST`. From an administrator account, temporarily enable the flag in the intended environment and create a synthetic order with no customer data.
4. Prepare the PDFs and open both previews. Confirm the title, story order, illustrations, all Danish and Greek characters, the final multiple-of-four page count, and the 5.25 × 8.25 inch interior and 10.25 × 8.25 inch cover sizes.
5. Run Lulu validation, choose a returned shipping method, and request a quote. Confirm the provider accepts the exact preset and returns the expected cover dimensions and currency.
6. Place one clearly synthetic sandbox order. Confirm the Orders page records one Lulu job ID and reaches the provider's `UNPAID` status. Complete the sandbox payment simulation in Lulu's sandbox portal, then use **Refresh status** to confirm the updated state.
7. Leave the flag enabled only for the administrator pilot after those checks pass. Ordinary users receive a not-found response even when they guess an Orders URL.

No real customer order should be used for a smoke test. Sandbox jobs never enter Lulu's live production workflow.

## Worker and failure handling

PDF preparation, Lulu file validation, quotes, submission reconciliation, and status refresh all use the default Solid Queue queue. Check application logs and Solid Queue health if an order stays in a local preparing, validating, quoting, submitting, or refreshing state.

Provider validation and address errors appear on step three. Correct the delivery address or regenerate the files, then request validation and a new quote. A changed address invalidates the previous validation and quote.

Submission uses the order's stable `submission_uuid` as Lulu's `external_id`. If the POST times out, the app marks the result uncertain and searches Lulu for that exact external ID six times. It does not repeat the POST. If the order reaches `submission_needs_review`:

1. Copy the local `submission_uuid` from an authorized Rails console without copying the delivery address.
2. Search the Lulu sandbox portal or API for the exact external ID.
3. If Lulu has the job, record its ID and status through a reviewed repair rather than submitting again.
4. If Lulu has no job, investigate the original response and logs before permitting a new explicit submission. Never clear the UUID merely to retry an uncertain request.

Known provider rejections end in `submission_failed` and retain the sanitized provider message. Submitted jobs are polled until a terminal or action-required status such as `UNPAID`, `REJECTED`, `ERROR`, `SHIPPED`, or `CANCELED`; an administrator can request another status refresh from the order.

## Disable and rollback

Set `LULU_ORDERS_ENABLED` to `"false"` and redeploy to remove Orders from navigation and block order routes plus all mutating Lulu jobs. Existing order records and retained files remain. Signed artifact URLs already issued remain usable only until their six-hour expiry.

Do not roll back the three print-order migrations to disable the pilot. A code rollback does not reverse submitted Lulu jobs, and removing the tables would destroy retained editions and reconciliation identifiers. Preserve the data and disable the flag while any sandbox job is being investigated.
