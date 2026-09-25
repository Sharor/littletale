# Architecture

DigitalOcean Droplet
│
├── Kamal
│   ├── Rails web
│   ├── Rails jobs
│   ├── sqlite etc.
│   │
│   ├── Grafana Alloy
│   │    ├── Docker metrics
│   │    ├── host metrics
│   │    └── Docker logs
│   │
│   ├── Prometheus  ← metrics
│   ├── Loki        ← logs
│   └── Grafana     ← dashboards / alerts
│
└── persistent storage

# Metrics
server/docker: 
CPU, RAM, disk, container restarts, network usage, etc.


Rails: 
HTTP request rate
HTTP error rate
p50 / p95 / p99 response time

Puma
 ├─ workers
 ├─ threads
 ├─ busy threads
 └─ queue/backlog

ActiveRecord
 ├─ query duration
 ├─ connection pool usage
 └─ connection wait time

Solid Queue / Sidekiq
 ├─ queue depth
 ├─ job latency
 ├─ failures
 └─ processing rate

Ruby
 ├─ GC time
 ├─ allocations
 ├─ heap
 └─ RSS


 # Dashboard idea
┌─────────────────────────────────────────────┐
│              Rails Production               │
├──────────┬──────────┬──────────┬────────────┤
│  RPS     │ p95      │ errors   │ jobs       │
│   41     │ 231 ms   │ 0.08%    │ 14 queued  │
├──────────┴──────────┴──────────┴────────────┤
│                                             │
│ HTTP latency p50 / p95 / p99                │
│ ▁▁▂▃▂▂▄▅▂▁▁▂▃                            │
│                                             │
├──────────────────────┬──────────────────────┤
│ Puma threads         │ DB connections       │
│ ███████░░░ 7/10      │ ████████░░ 8/10      │
├──────────────────────┴──────────────────────┤
│ Docker CPU / memory                         │
│ ▁▂▂▃▆█▅▃▂▂▃                               │
├─────────────────────────────────────────────┤
│ Logs                                        │
│ ERROR ActiveRecord::QueryCanceled ...       │
│ WARN  Job retry ...                         │
└─────────────────────────────────────────────┘