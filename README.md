# Scrum Manager

Read-only Scrum dashboard for Fizzy cards.

## Features

- Discovers sprint tags from Fizzy tags beginning with `sprint`
- Lists available sprint dashboards on `/`
- Groups sprint cards by client board and board status
- Supports assignee and board filters
- Opens Fizzy cards in a new tab
- Supports manual refresh and polling intervals: off, 5 seconds, 10 seconds, 30 seconds
- Uses a 5-second in-memory cache by default
- No database

## Setup

```bash
bundle install
cp .env.example .env
```

Edit `.env`:

```bash
FIZZY_TOKEN=your_fizzy_personal_access_token
FIZZY_ACCOUNT_SLUG=6116053
CACHE_TTL_SECONDS=5
```

Load the environment and run the app:

```bash
export $(grep -v '^#' .env | xargs)
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
```

`CACHE_TTL_SECONDS` is optional and defaults to `5`.
