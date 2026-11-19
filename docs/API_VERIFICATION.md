# API verification

What Polox talks to, where in the code, and how far each one has been proven. A row says **Verified**
only when a real request went to the real service through the game's own code and the game did the
right thing with the answer. Everything else says exactly what is missing.

Last run: 10 November 2026 (live provider checks), Windows 11; Phone Link E2E and Info-folder lookup checks refreshed 15 November 2026 on final 1.29.0 code.

## How it was checked

- **Live check**: `tools/api_live_check.gd` sends one small request per service through the same
  scripts the game uses and prints what the game said. Keys are read from a settings file you name and
  are never printed.

  ```
  tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/api_live_check.gd -- --save-root=<empty scratch folder> [--settings=<settings.json>] [--paid]
  ```

  Without `--settings` it runs the keyless part (a made-up key must be refused in words that say so;
  public lists must contain the models Polox asks for; the map services must answer). `--paid` allows
  the requests that cost money on a real key.
- **Documentation**: each request shape and default model was compared with the service's own current
  documentation on the same day.
- **Automated tests**: every caller has tests against stand-in servers on 127.0.0.1 (`check.bat`), so
  timeouts, bad answers, refusals and retries are covered without a network.

## The table

| Service | Used for | Code | Real request and result | Status |
| --- | --- | --- | --- | --- |
| **Ollama** `POST /api/chat`, `GET /api/tags` (this PC) | Chats with friends, local and private | `scripts/ai/ai_client.gd` | Ollama 0.40.14: model list read; a chat answered (46.9 s cold, 2.4 s warm); a chat asking for a model that isn't installed switched to an installed one and said so; with Ollama switched off the game says it can't reach Ollama | **Verified** |
| **Google Gemini** `POST v1beta/openai/chat/completions`, `GET .../models` | Chats with friends | `scripts/ai/ai_client.gd`, `presets.gd` | Real key: answered in 8.6 s with `gemini-3.5-flash-lite` (listed as Stable in Google's model list); 62 models listed, the default among them. Made-up key: HTTP 400, "didn't accept the API key" | **Verified** |
| **Google Gemini** `POST v1beta/models/<model>:generateContent` | Home helper: reading what you tell Polox about your home; looking a home up with Google Search | `scripts/home/research.gd` | Real key: `gemini-3.6-flash` answered in the shape Polox asks for. Made-up key: "Google didn't accept the Gemini key" | **Verified** for reading. The search-grounded lookup was **not run** (it is the same request plus `tools: [{google_search: {}}]`) |
| **Venice** `POST /api/v1/chat/completions`, `GET /api/v1/models` | Chats with friends | `scripts/ai/ai_client.gd`, `presets.gd` | Public model list: 139 models, the default `zai-org-glm-5` among them. Made-up key: HTTP 401, "didn't accept the API key". `venice_parameters` match Venice's API page | **Not verified**: no Venice key here, so no successful chat |
| **Groq** `POST /openai/v1/chat/completions` | Chats with friends | `scripts/ai/ai_client.gd`, `presets.gd` | Every request from this network, with or without a key, gets HTTP 403 "Access denied. Please check your network settings" (Groq's website and documentation too). The game now says that Groq is refusing this network | **Blocked**: cannot be verified from this network. The default model `openai/gpt-oss-20b` and `reasoning_effort` are in Groq's reasoning documentation |
| **Anthropic** `POST /v1/messages` | Home helper: looking a home up (web search and web fetch) | `scripts/home/research.gd` | Made-up key: HTTP 401, "Anthropic didn't accept the API key". The request (`claude-opus-5-5`, adaptive thinking, `output_config.effort`, `web_search_20260209` / `web_fetch_20260209`, server-side fallback, `pause_turn` continuation, `refusal` and `max_tokens` stops) matches the current API reference | **Not verified**: no Anthropic key here, so no successful lookup |
| **OpenAI** `POST /v1/responses` | Home helper | `scripts/home/helper_http.gd` | Made-up key: HTTP 401, "refused this API key". The saved key reached OpenAI, which answered HTTP 429 `insufficient_quota` / `credit_balance_exhausted` (no credit on the account); the game now says the account has no credit left | **Not verified**: needs credit on the account |
| **Compatible endpoint** `POST <your URL>/chat/completions` | Chats (Custom server) and the home helper | `ai_client.gd`, `helper_http.gd` | Stand-in servers only | **Tested with stand-ins**; a real one depends on the server you point it at |
| **Claude Code** and **Codex** command-line helpers | Home helper, using your own sign-in | `research.gd`, `helper_codex.gd` | Not run: a lookup uses your subscription or up to 5 USD of credit | **Not verified** in this pass (stand-in programs in `tests/`) |
| **OpenStreetMap Nominatim** `GET /search` | Finding where an address is, after you agree | `scripts/home/osm.gd` | A public landmark was found at its real coordinates | **Verified** |
| **OpenStreetMap Overpass** `POST /api/interpreter` | Streets around a place, after you agree | `scripts/home/osm.gd` | French server: 234 map features, state "ready". Main server (overpass-api.de): no answer in 35 s twice and HTTP 502 once; the game said so, changed nothing, and pointed at Settings to pick the other server | **Verified** on one of the two servers; the other was down or busy, and that path is verified |
| **Tailscale** command line `status --json`, `serve status --json`, `serve --bg`, `serve ... off` | Phone Link away from home | `scripts/phone/tailscale.gd` | Tailscale found running, signed in, MagicDNS and HTTPS certificates on; 6 Serve mappings read, none public | **Verified** for reading. Switching a mapping on and off was not repeated in this pass (fixtures in `tests/`, and see [PHONE_TEST.md](PHONE_TEST.md)) |
| **Phone Link server** `/api/pairing`, `/api/pair`, `/api/status`, `/api/worlds`, `/api/cover`, `/api/session`, `/api/manifest`, `/api/file`, `/api/sync/begin`, `/api/sync/end`, `/api/ai`, `/api/home-helper`, `/api/export`, `/api/report`, `/api/unpair` | Your phone playing through your PC | `scripts/phone/phone_api.gd`, `phone_server.gd`; phone side `sync_client.gd`, `app_link.gd`, `app_check.gd`, `helper_pc.gd` | `check_phone.bat`: the real server on this PC's real addresses, the real phone version, pairing, sync both ways, a deliberate conflict, the AI proxy, attacks, and a headless phone-size browser | **Verified**: 9 of 9 end-to-end tests on 15 November 2026 with the 1.29.0 phone build (`c9a8a960cd5342a2`), a real browser included ([COMPATIBILITY.md](COMPATIBILITY.md)) |
| **Cloud folder sync** | The same worlds with the PC off | `scripts/sync/` | No web API at all: Polox reads and writes one file in a folder your own cloud app syncs | Tested with two simulated devices; a real cloud app between two devices is **not verified** (see [SYNC.md](SYNC.md)) |
| **Android document picker** (Storage Access Framework) | Cloud sync on Android | `native/android/.../CloudDocuments.java` | Compiles with the project's Gradle build | **Not verified** on a phone or emulator |
| **Updates** | | | Polox has no update check and never calls home | Nothing to verify |

## What every caller does when things go wrong

| Situation | Chats (`ai_client.gd`) | Home helpers (`research.gd`, `helper_http.gd`, `helper_pc.gd`) | Maps (`osm.gd`) | Phone Link sync (`sync_client.gd`) |
| --- | --- | --- | --- | --- |
| Timeout | 20 s (Ollama 90 s); retried up to twice with 1.5 s then 3 s waits | 5 to 10 minutes (reasoning with web search is slow); never retried, since a lookup can cost money | 35 s; one retry | Per request; the phone keeps its own copy and tries again each minute |
| Cancelled by the player | Stop (Settings > AI, while a test runs; `AIClient.cancel()`) ends a wait or a request at once, and nothing more is sent for it | Cancel stops the request or the wait before a retry, and nothing is applied | Cancel drops the answer | A sync in progress finishes or is abandoned whole |
| Answer isn't what was asked for | "sent back something unexpected" | Checked against a strict shape; anything else changes nothing | Checked element by element; anything else changes nothing | Hashes are compared before a file is used |
| Key refused or expired (401; 403 without a network refusal; Google's 400) | Says so, no retry | Says so, no retry | (no key) | "Not paired: pair this phone again (it keeps your saves)" |
| Network or region refused (403 "access denied", a block page, "Request not allowed"; Google's 400 "location is not supported") | Says the provider refuses this network; the key is not blamed; no retry | The same | | |
| Rate limit (429) | Waits what the provider asked, 1 to 60 s (`Retry-After` in seconds or as a date, `retry-after-ms`, Google's `retryDelay`), counting down, then retries; 8 s when it didn't say. Changing the provider or key ends the wait | With a `Retry-After`: waited once (1 to 60 s), then asked again. Without one: says so, no retry. Anthropic and Google get one or two extra tries when they are busy | Waits `Retry-After` before allowing Retry | |
| No credit left (402; 429 `insufficient_quota` / `credit_balance_exhausted`; Anthropic's 400 "credit balance is too low") | Says so, no retry, and nobody else in the queue is made to wait | Says so, no retry | | |
| Server error | Retried up to twice | One extra try at most | One retry for 502, 503, 504 | Tries again later |
| Offline | Friendly line; Phone Link chats fall back to offline lines | Says so | Saved streets keep working | "PC offline" and local play |
| Writing twice | Nothing is written until an answer is complete | Nothing is applied until you confirm the preview | The kept map is replaced only by a checked one | Revisions and hashes: the same change is never applied twice |

All three callers ask one place what kind of "no" an answer is (`scripts/ai/api_errors.gd`), so the
same answer is never a bad key in chats and a rate limit in a helper. `tests/test_api_keys.gd` holds
each provider's real wording for each kind.

## Whose key is whose

`scripts/ai/key_format.gd` reads the mark at the front of a key. A key known to be one service's is
never kept for, or sent to, another: Settings turns it away and says where it goes, a settings file
that has one misfiled is put right when it loads, and the request code checks again before sending.

| Mark | Whose | Where Polox keeps it |
| --- | --- | --- |
| `gsk_` | Groq | Settings > AI, Groq |
| `AIza`, `AQ.` (the newer kind) | Google Gemini | Settings > AI, Google Gemini (the Gemini home helper uses the same one) |
| `sk-ant-` | Anthropic | Settings > Light World > Helper setup, Claude API key |
| `sk-proj-`, `sk-svcacct-`, `sk-admin-`, plain `sk-` | OpenAI | Helper setup, OpenAI API key; for chats, Settings > AI, Custom server |
| `sk-or-` | OpenRouter | Custom server, or the Compatible key box |
| `VENICE-` | Venice | Settings > AI, Venice |
| anything else | not known | wherever you put it |

Venice publishes no format for its keys (its API reference shows none), so a key without a mark is
accepted for Venice, as it is for a custom server. Plain `sk-` is used by other OpenAI-style services
too: such a key is accepted in the OpenAI box and for any custom server, and turned away only from
Groq, Gemini, Venice and the Claude box.

Keys are stored in `settings.json` in your PersonalData folder and nowhere else. They are taken out of
chat logs (by value, and anything shaped like a key by its mark), chat exports, the flight recorder's
error lines and crash reports; world exports, snapshots, Phone Link sync and cloud sync never include
`settings.json`. `tests/test_privacy.gd` and `tests/test_api_keys.gd` search every file a session writes.

## What this pass changed

Each of these was found by sending real requests, and has a test:

1. Groq answering HTTP 403 "Access denied" was reported as a wrong API key. It is now reported as the
   provider refusing this network.
2. With Ollama switched off and no model chosen, the game said "Ollama has no models yet". It now says
   it can't reach Ollama.
3. A Gemini key in Google's newer format (starting `AQ.`) was filed under "Custom server", so Gemini
   looked as if it had no key. Such keys now go to Gemini, and one already misfiled is given to Gemini too.
4. OpenAI's answer for an account without credit (HTTP 429, `insufficient_quota` /
   `credit_balance_exhausted`) was reported as a rate limit to wait out. It now says the account has no
   credit left.
5. A map server that never answers was reported as a failed connection. It is now reported as busy,
   with where to choose the other server.
6. End-to-end Info-folder lookup of a public museum house (OpenStreetMap Nominatim/Overpass and
   kept room/floor/storey rules) verified live and covered by `tests/test_light_world_info.gd`
   (8 of 8 tests passing).

## To finish the table yourself

- **Venice, Groq, Anthropic**: put the key in Settings, then run the live check with `--settings`
  (and `--paid` for Anthropic). Groq also needs a network it accepts.
- **OpenAI**: add API credit to the account, then run the live check with `--settings --paid`.
- **Search-grounded lookups** (Gemini, Anthropic, OpenAI) and the **command-line helpers**: do one real
  lookup in the game (Light World > look up a home) and compare with the preview it shows.
