# Scrum Manager

Read-only Scrum dashboard for Fizzy cards.

## Features

- Discovers sprint tags from Fizzy tags beginning with `sprint`
- Lists available sprint dashboards on `/`
- Groups sprint cards by client board and board status
- Supports assignee and board filters
- Opens Fizzy cards in a new tab
- Supports manual refresh and polling intervals: off, 5 seconds, 10 seconds, 30 seconds
- Reads dashboard data from MongoDB so filtering does not call Fizzy
- Provides a Fizzy sync command for cron jobs
- Uses MongoDB as the local dashboard data store
- Follows Fizzy pagination using `Link` headers with `rel="next"`

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
FIZZY_LOG_HTTP=false
FIZZY_LOG_RESPONSE_BODY=true
FIZZY_LOG_BODY_LIMIT=12000
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
```

`MONGODB_URI` defaults to `mongodb://127.0.0.1:27017`.
`MONGODB_SERVER_SELECTION_TIMEOUT` is optional and defaults to `2` seconds.

## Fizzy Sync

The web app reads sprint and card data from MongoDB. It does not call Fizzy when filtering by assignee or board.

Run a full sync manually:

```bash
export $(grep -v '^#' .env | xargs)
bundle exec ruby bin/sync_fizzy
```

The sync command:

1. Fetches all Fizzy tags starting with `sprint`
2. Upserts those sprint tags into MongoDB
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
