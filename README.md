# Scrum Manager

Read-only Scrum dashboard for Fizzy cards.

## Features

- Discovers sprint tags from Fizzy tags beginning with `sprint`
- Lists available sprint dashboards on `/`
- Groups sprint cards by client board and board status
- Supports assignee and board filters
- Opens Fizzy cards in a new tab
- Supports manual refresh from MongoDB
- Reads dashboard data from MongoDB so filtering does not call Fizzy
- Provides a Fizzy sync command for cron jobs
- Uses MongoDB as the local dashboard data store
- Syncs all Fizzy tags and displays card tags as color-coded badges
- Follows Fizzy pagination using `Link` headers with `rel="next"`
- Provides snapshot-based Burndown, Burnup, and Velocity reports

## Reports

The Burndown, Burnup, and Velocity reports use card counts, not story points. Sprint dates are estimated from the sprint tag's `created_at` and `SPRINT_DURATION_DAYS` (default: `10`).

Reports require MongoDB, Fizzy credentials, and a successful full sync. Each sync stores a snapshot of sprint cards and their status, board, and assignees. The first snapshot is only a baseline; run another sync to see progress. Earlier history cannot be reconstructed.

Run the focused report tests:

```bash
bundle exec ruby -Itest test/sprint_reports_test.rb
```

For a manual check, load `.env`, sync twice (with time or card changes between syncs), start the app, then open `http://localhost:4567/reports`:

```bash
export $(grep -v '^#' .env | xargs)
bundle exec ruby bin/sync_fizzy
bundle exec ruby bin/sync_fizzy
bundle exec rackup -p 4567
```

## Setup

```bash
bundle install
cp .env.example .env
```

Edit `.env`:

```bash
FIZZY_TOKEN=your_fizzy_personal_access_token
FIZZY_ACCOUNT_SLUG=6116053
MONGODB_URI=mongodb://127.0.0.1:27017
MONGODB_DATABASE=scrum_manager
MONGODB_SERVER_SELECTION_TIMEOUT=2
SPRINT_DURATION_DAYS=10
FIZZY_LOG_HTTP=false
FIZZY_LOG_RESPONSE_BODY=true
FIZZY_LOG_BODY_LIMIT=12000
```

Generate the required Rack session secret (64 bytes minimum):

```bash
printf 'SESSION_SECRET=%s\n' "$(openssl rand -hex 64)" >> .env
```

Load the environment and run the app:

```bash
export $(grep -v '^#' .env | xargs)
bundle exec ruby bin/sync_fizzy
bundle exec rackup -p 4567
```

Open:

```text
http://localhost:4567
```

## Status Rules

Cards are classified with this priority:

1. `closed == true` -> `Done`
2. `postponed == true` -> `Not Now`
3. `column.name` -> the Fizzy board column
4. no column -> `Maybe`

## Required Environment

```bash
FIZZY_TOKEN
FIZZY_ACCOUNT_SLUG
MONGODB_URI
MONGODB_DATABASE
MONGODB_SERVER_SELECTION_TIMEOUT
SESSION_SECRET
```

`MONGODB_URI` defaults to `mongodb://127.0.0.1:27017`.
`MONGODB_SERVER_SELECTION_TIMEOUT` is optional and defaults to `2` seconds.
`SESSION_SECRET` must be at least 64 bytes; generate it with `openssl rand -hex 64`.

## Fizzy Sync

The web app reads sprint and card data from MongoDB. It does not call Fizzy when filtering by assignee or board.

Run a full sync manually:

```bash
export $(grep -v '^#' .env | xargs)
bundle exec ruby bin/sync_fizzy
```

The sync command:

1. Fetches all Fizzy tags and stores them in MongoDB
2. Selects tags starting with `sprint` as dashboard sprints
3. Fetches cards for each sprint tag
4. Fetches full card details
5. Upserts cards and their sprint membership into MongoDB

Install a 30-minute cron job by copying and editing `config/cron.example`, then running:

```bash
crontab config/cron.example
```

## Fizzy HTTP Logging

To troubleshoot API responses, enable request/response logging:

```bash
FIZZY_LOG_HTTP=true
```

The bearer token is redacted in logs. Response bodies are logged by default and truncated to `FIZZY_LOG_BODY_LIMIT` bytes.

Useful troubleshooting run:

```bash
export $(grep -v '^#' .env | xargs)
FIZZY_LOG_HTTP=true bundle exec rackup -p 4567
```

Then open `/` and inspect the terminal output for the `/tags` responses.
