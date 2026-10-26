# Signal Duel score backend

Separate AWS SAM stack: one DynamoDB table (`board` partition key, lowercased `nameKey` sort key), one Node.js 24 Lambda and public function URL. No shared table, deployment, or AWS credentials are included here.

## Local verification

```sh
cd /Users/lotte/local-business/tasks/godot-games-20261026-1-4/publish/signal-duel/score-backend
npm ci
npm test
```

Tests exercise validation, HTTP responses, pagination/ranking, conditional DynamoDB command inputs and error handling with an injected fake `send` client. They do not access AWS. `template.yaml` is parsed locally as YAML; no cloud deployment has been performed.

## API contract

- `GET /?board=stage-01` through `stage-24`, or `GET /?board=survival` → `{"entries":[{"nickname":"Ace","score":123}]}`. At most ten entries, highest scores first; equal scores sort by nickname. Empty board → `{"entries":[]}`.
- `POST /` with JSON `{"nickname":"Ace","board":"stage-01","score":123}` → `{"updated":true}` when a new personal best was stored, otherwise `{"updated":false}`. `Content-Type: application/json` is expected by browsers. No other JSON fields are allowed.
- Nickname is 2–16 Korean or ASCII letters, digits, spaces, underscores or hyphens, no leading/trailing spaces. ASCII names are case-insensitive per board (`Ace` and `ace` share one best). Score must be a JSON integer from 0 through 1,000,000,000. Request body max 4096 bytes. Invalid input returns 400; unsupported methods 405; server failure 500.

Updates use one conditional `UpdateItem` (`attribute_not_exists(score) OR score < proposedScore`), so concurrent lower or equal scores cannot replace a better one. GET queries **every** page of the board and sorts in Lambda; this is simple but reads the full board on every request and is not suitable for very large/high-traffic leaderboards. A score-sorted index or materialized top-N would be needed at scale. Results are eventually consistent with concurrent writes (no strongly consistent snapshot across pages).

## Deployment instructions (not executed)

When an operator explicitly approves deployment and has authenticated AWS/SAM CLI access:

```sh
npm ci
sam build --template-file template.yaml
sam deploy --guided --parameter-overrides AllowedOrigin=https://your-game.example
```

Deploy as a **new stack**. `AllowedOrigin` is the exact HTTPS site origin (no path or trailing slash), not the API URL. After deployment, take `ScoreUrl` from the stack output and configure the Godot game's leaderboard base URL with it; keep the trailing slash from the Lambda URL. For a non-browser Godot native client, CORS is irrelevant, but a web export must match the origin. Deleting the stack retains the DynamoDB table by design; remove it separately only when data loss is intended. Neither a URL nor table is created by this repository alone.

**Security:** The function URL uses `AuthType: NONE`. Anybody with the URL can read, submit, impersonate nicknames, or spoof scores; CORS is browser policy, *not* authentication. There is no score attestation, per-user identity, rate limit, or anti-cheat. Add those before treating rankings as trusted. Public use can incur DynamoDB/Lambda charges.
