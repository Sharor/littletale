# Metrics, logs, and alerts after the first Kamal deployment

The application exposes Prometheus metrics at `/metrics`. The endpoint requires
the `METRICS_BEARER_TOKEN` bearer token. Grafana Alloy collects that endpoint,
host and Docker metrics, and Docker logs, then forwards them to Grafana Cloud.
The backend URLs and credentials are environment variables so Alloy can later
write to a self-hosted Prometheus-compatible and Loki stack without changing
the Rails instrumentation.

## Before booting Alloy

1. Create the Grafana Cloud Free stack. In **Connections**, choose the option to
   send metrics and logs with Alloy.
2. Create a Cloud Access Policy token with only `metrics:write` and `logs:write`.
3. Copy the Prometheus remote-write URL and instance ID into
   `METRICS_WRITE_URL` and `METRICS_USERNAME`.
4. Copy the Loki write URL and instance ID into `LOGS_WRITE_URL` and
   `LOGS_USERNAME`.
5. Put the access-policy token in `OBSERVABILITY_WRITE_TOKEN`.
6. Generate a separate random `METRICS_BEARER_TOKEN`, for example with
   `openssl rand -hex 32`. Give Rails and Alloy the same value. Do not reuse the
   Grafana Cloud token.
7. Put all values in `.kamal/secrets`. Never commit that file or paste its
   values into this guide.

The provisional production hostname is `littletale.com`. Update
`config/deploy.yml` and `RAILS_METRICS_HOST` if the final hostname differs.
Alloy scrapes the public HTTPS metrics endpoint, so DNS and the Kamal TLS proxy
must be working first.

## Boot and verify the collector

After the first successful application deployment:

```sh
bin/kamal accessory boot alloy
bin/kamal accessory logs alloy
```

The Alloy UI is bound to `127.0.0.1:12345` on the server and is not public.
Use SSH port forwarding if it is needed for diagnosis. In Grafana Cloud, confirm
that these queries return data:

```promql
up{job="rails"}
rails_http_requests_total
solid_queue_metrics_available
node_memory_MemTotal_bytes
container_memory_working_set_bytes
```

In Logs Drilldown, query `{environment="production"}` and confirm Rails output
appears. Gift invitation tokens under `/gifts/` are redacted before upload.
Alloy persists Docker log positions in `alloy-data` so a restart does not replay
the entire log history.

## Dashboard and alerts

Import `config/observability/dashboard.json` in Grafana. Select the stack's
Prometheus and Loki data sources when prompted.

Use `config/observability/alerts.yml` as the version-controlled source for the
Grafana-managed alert rules. Create an email contact point for
`davchristensen90@gmail.com`, send a test notification, and route the
`little-tale-production` alert group to it. The initial rules cover missing
Rails metrics, low host memory or disk, high HTTP error rate or p95 latency,
jobs with exhausted retries, queue backlog, unavailable queue metrics, and jobs
running longer than 15 minutes. Ordinary retries do not alert.

After creating the rules, deliberately test both firing and recovery:

- temporarily set the stuck-job threshold query to zero, then restore it;
- stop Alloy briefly to verify the missing-metrics alert, then restart it;
- confirm both alert and resolved emails arrive.

## Free-tier and resource checks

Grafana Cloud Free currently retains data for 14 days. Check the billing/usage
page after 24 hours and again after one week. The Alloy allowlist intentionally
drops most cAdvisor and node-exporter series to control cardinality. Logs are
the larger risk: keep Rails at `info`, investigate sudden volume growth, and do
not enable debug logging for long periods.

The Alloy container is intended to have a 256 MiB memory limit and half a CPU.
On a 1 GiB droplet, monitor peak memory while generating a complete story and
during a Kamal deployment. Move to a larger droplet if the host approaches the
memory alert or invokes the OOM killer. A 512 MiB droplet is not an assumed
production target.

## Troubleshooting and rollback

- A `401` from `/metrics` means the Rails and Alloy bearer tokens differ.
- `solid_queue_metrics_available 0` means Rails could not query the queue
  database; inspect application logs and the persistent SQLite volume.
- Remote-write `401` or `403` errors mean a URL, instance ID, token, or token
  scope is wrong.
- Missing container logs usually means Alloy cannot read the Docker socket.
- Stop collection with `bin/kamal accessory stop alloy`. This does not stop the
  Rails application or remove Alloy's persisted positions.

When moving to a dedicated metrics server, change the four write URL/username
values and the write token, then reboot Alloy. Dashboard JSON and Prometheus
rule expressions stay portable. Historical Grafana Cloud data is not migrated
by this configuration.
