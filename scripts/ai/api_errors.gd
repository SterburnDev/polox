extends RefCounted
## What kind of "no" a provider gave. Chats (ai_client.gd) and the home helpers (helper_http.gd,
## research.gd) all ask here, so the same answer is never a bad key in one place and a rate limit in
## another. Four kinds matter, because each wants something different from the player:
##
##   KEY         the key was refused (wrong, expired, switched off, no permission): fix it, no retry
##   CREDIT      the account has nothing left to spend: add credit, no retry (waiting never helps)
##   NETWORK     the provider refuses this network or place, whatever the key: not the key's fault
##   RATE_LIMIT  too fast: wait what the provider asked (retry_after), then one more go
##
## Anything else ("") is the caller's to explain (a missing model, a server error, a bad request).
## Tags: [AI_HELPER]

const KEY := "key"
const CREDIT := "credit"
const NETWORK := "network"
const RATE_LIMIT := "rate_limit"

## A provider may ask for any wait; Polox never waits less than this or more than that.
const RETRY_MIN_S := 1.0
const RETRY_MAX_S := 60.0

const MONTHS: PackedStringArray = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]


static func kind(code: int, body_text: String) -> String:
	match code:
		401:
			return KEY
		402:
			return CREDIT
		403:
			if out_of_credit(body_text):
				return CREDIT
			return NETWORK if refused_this_network(body_text) else KEY
		429:
			return CREDIT if out_of_credit(body_text) else RATE_LIMIT
		400:
			# Google answers 400 for a bad or expired key and for a place it doesn't serve; Anthropic
			# answers 400 for an empty balance.
			if refused_this_place(body_text):
				return NETWORK
			if out_of_credit(body_text):
				return CREDIT
			if key_rejected(body_text):
				return KEY
	return ""


## A 403 that is about where the request came from, not about the key: a block page instead of JSON,
## or the provider's own words for it. (A key without permission still reads as a key problem.)
static func refused_this_network(body_text: String) -> bool:
	var text := body_text.strip_edges().to_lower()
	if text.begins_with("<"):
		return true
	for words in ["access denied", "network settings", "request not allowed", "country", "region", "territory", "your location"]:
		if text.contains(words):
			return true
	return refused_this_place(body_text)


## The same, said with a 400 (narrow words: an ordinary bad request may mention a region).
static func refused_this_place(body_text: String) -> bool:
	var text := body_text.to_lower()
	for words in ["location is not supported", "unsupported_country", "not available in your country", "not available in your region"]:
		if text.contains(words):
			return true
	return false


## "This account has nothing left to spend", not "slow down". OpenAI's real answer (type
## insufficient_quota, code credit_balance_exhausted) is the model; the words are kept narrow because
## Gemini says "quota" and "billing" for an ordinary per-minute limit too.
static func out_of_credit(body_text: String) -> bool:
	var text := body_text.to_lower()
	for words in ["insufficient_quota", "credit_balance", "credit balance", "no credits", "insufficient balance", "insufficient_balance",
			"billing_hard_limit", "billing_not_active"]:
		if text.contains(words):
			return true
	return false


## A 400 whose words are about the key itself.
static func key_rejected(body_text: String) -> bool:
	var text := body_text.to_lower()
	for words in ["api key", "api_key", "api-key", "apikey"]:
		if text.contains(words):
			return true
	return false


## How long the provider asked us to wait, in seconds, kept between RETRY_MIN_S and RETRY_MAX_S;
## -1 when it didn't say. Read from "retry-after-ms", "Retry-After" (seconds, or a date) and, for
## Google, the "retryDelay" in the answer itself.
static func retry_after(headers: PackedStringArray, body_text: String = "", now_unix: float = -1.0) -> float:
	var asked := -1.0
	for h in headers:
		var colon := str(h).find(":")
		if colon < 0:
			continue
		var name := str(h).left(colon).strip_edges().to_lower()
		var value := str(h).substr(colon + 1).strip_edges()
		if name == "retry-after-ms" and value.is_valid_float():
			asked = value.to_float() / 1000.0
			break   # the exact one wins over the rounded one beside it
		if name == "retry-after":
			if value.is_valid_float():
				asked = value.to_float()
			else:
				var at := http_date(value)
				if at > 0.0:
					asked = maxf(0.0, at - (now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()))
	if asked < 0.0:
		var said := RegEx.create_from_string("\"retryDelay\"\\s*:\\s*\"([0-9.]+)s\"").search(body_text)
		if said and said.get_string(1).is_valid_float():
			asked = said.get_string(1).to_float()
	if asked < 0.0 or is_nan(asked):
		return -1.0
	return clampf(asked, RETRY_MIN_S, RETRY_MAX_S)


## "Wed, 21 Oct 2026 07:28:00 GMT" -> Unix time (0 when it isn't such a date).
static func http_date(value: String) -> float:
	var parts := value.replace(",", " ").split(" ", false)
	if parts.size() < 5:
		return 0.0
	var month := MONTHS.find(parts[2].to_lower().left(3)) + 1
	var clock := parts[4].split(":")
	if month < 1 or clock.size() != 3 or not parts[1].is_valid_int() or not parts[3].is_valid_int():
		return 0.0
	return float(Time.get_unix_time_from_datetime_dict({"year": parts[3].to_int(), "month": month, "day": parts[1].to_int(),
		"hour": clock[0].to_int(), "minute": clock[1].to_int(), "second": clock[2].to_int()}))
