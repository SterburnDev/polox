# Google Maps Integration (Gemini & Google AI Plus)

Polox's Light World maps your real neighbourhood using OpenStreetMap by default, and also includes
**optional Google Maps integration** designed for players with **Google Gemini**, **Google AI Plus /
Google One AI**, or **Google Maps Platform** keys.

It is **off by default**. Nothing is ever sent to Google unless you explicitly turn it on and confirm
each lookup.

## Three modes

Open **Settings > Light World > Helper setup** to choose how Google Maps works for you:

| Mode | Best for | What it uses |
| --- | --- | --- |
| **Gemini Maps Grounding** | Gemini API & Google AI Plus / Google One AI users | Your Gemini key from *Settings > AI* (or a Google key in Helper setup). Calls Gemini with Google's `google_maps` + `google_search` grounding tools to find nearby public landmarks, parks, cafes, and neighbourhood atmosphere. |
| **Google Maps Places API** | Google Cloud / Maps API key users | Direct Nearby Search against Google Maps Places API (New) using a strict field mask (`displayName`, `location`, `types`, `googleMapsUri`) limited to public categories. |
| **Links & URL paste only** | Zero-key / web Gemini subscribers | Sends nothing automatically. Lets you paste any Google Maps share link directly into address/coordinate fields, and copies a ready-to-paste Google Maps prompt for Gemini web chat. |

## Pasting Google Maps URLs offline

Even with Google Maps integration turned off, Polox understands pasted Google Maps links locally
without touching the network (`scripts/home/google_maps.gd` → `parse_link`):

- `https://www.google.com/maps/@37.4220,-122.0841,17z`
- `https://www.google.com/maps/place/.../@37.4220,-122.0841,16z/data=!3d37.422!4d-122.084`
- `https://www.google.com/maps/search/?api=1&query=37.4220%2C-122.0841`
- `https://maps.google.com/?q=37.4220,-122.0841`

## Enriching your Light World streets

1. Map your streets in **My home > Map my streets** (OpenStreetMap builds the roads and building shapes).
2. Open **My home > Sources > Map and references** and click **Enrich with Google Maps**.
3. Review the confirmation prompt (which shows the exact radius sent) and confirm.
4. Discovered public landmarks are merged into your local map with clickable verified `https://` Google
   Maps links and cached in `PersonalData/my_home/google_maps.json` so your Light World stays offline
   afterwards.

## Privacy rules

- **Public places only:** Neighbours' private residences and people's names are excluded.
- **Explicit consent:** Every live lookup asks before sending coordinates.
- **Keys stay local:** Google API keys live only in `PersonalData/settings.json`, are never synced to
  phones or cloud folders, and are automatically scrubbed from all logs (`scripts/ai/key_format.gd`).
- **One-tap removal:** *My home > Forget my home* deletes `google_maps.json` along with all other home data.
