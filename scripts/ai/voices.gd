extends RefCounted
## How each friend talks when no AI is connected (Mock mode), and in their little chats with each other. Five
## voices, matching the kinds of friend you can make (onboarding's vibes) plus the travellers who visit:
## gentle, bubbly, calm, grumpy and traveller. A friend's voice is "voice" if set, else it's read from their
## personality and speech style. Placeholders: {you} {like} {quirk} {gift} {other} {dream}.

const VOICES := ["gentle", "bubbly", "calm", "grumpy", "traveler"]

const LINES := {
	"gentle": {
		"hello": ["Oh! You're here~ I saved you the warm spot.", "Hi, {you}. I was just thinking about you. And snacks. Mostly you.", "There you are~ Sit, sit."],
		"bye": ["Okay~ Go be gentle with yourself, {you}.", "Bye bye! I'll keep the kettle warm.", "See you soon. Tell me everything next time, okay?"],
		"sad": ["Oh, {you}... come here. That sounds heavy.", "I'm sorry. We can just sit for a bit. No rush~", "That's a lot to carry. You don't have to carry it alone."],
		"tip": ["Maybe something warm to drink? It helps a tiny bit. Tiny bits count.", "Is there someone you could send a little 'hey' to today?"],
		"wow": ["Wait, really?!", "Oh!", "No way~"],
		"happy": ["That's wonderful, {you}! This calls for a snack. A celebration snack.", "I knew you could~ I'm so proud of you.", "I'm putting that in my diary of good things."],
		"question": ["Hmm... my heart says yes. My tummy also says yes, but it always does.", "Let's think about it together~ What would make you smile later?", "I don't know for sure. But I'd love to find out with you."],
		"flavor": ["Mm-hm, I'm listening~ Tell me more.", "That reminds me of {like}. Most things do, a little.", "Sorry, I was {quirk} again. Go on~", "That's so you. I mean that kindly.", "I'm writing that down in my head-notebook.", "Sometimes I wonder if a Dream Gate makes bubble-bath noises when nobody is looking~"],
		"gift_love": ["Is that... {gift}?! For me? I'm keeping it forever~", "{gift}! You remembered! Oh, I could cry~"],
		"gift_meh": ["Oh! {gift}! I'll find the perfect little spot for it.", "Aww, {gift}, for me? You thought of me, and that's the best part."],
		"gift_nice": ["{gift}! Thank you, that's so sweet~", "{gift}, for me? You're the kindest, {you}."],
		"npc": ["{other}, did you see the light on the floor today? So pretty~", "{other}! I saved you the comfy spot.", "Psst, {other}... do you think they'll visit again soon?"],
		"reply": ["Mm, me too~", "Aww, really?", "Tell me later, okay?"],
	},
	"bubbly": {
		"hello": ["HEY! {you}! The best person just walked in!", "Hiii! Okay okay okay, what's new? Tell me EVERYTHING!", "Oh good, you're here! I had a joke ready. It's terrible. You'll love it!"],
		"bye": ["Byeee! Go be amazing, superstar!", "See ya, {you}! Don't forget to hydrate! That's an order!", "Later, legend! I'll miss you like crazy!"],
		"sad": ["Oh no no no. Come here, buddy. Group hug! It's a group of two!", "Ugh, that's the worst. You don't deserve that, {you}!", "Okay. No jokes. Just me, right here."],
		"tip": ["Want to do something silly? Silly fixes like 3% of everything!", "Text a friend a dumb meme! Trust me!"],
		"wow": ["WAIT. REALLY?!", "NO WAY!", "Shut UP!"],
		"happy": ["YES! {you}, you absolute legend! Victory dance! Go!", "I KNEW IT! Didn't I say? I said!", "This is the best news since sliced toast!"],
		"question": ["Ooh! Easy! Yes! Wait. Maybe! Yes!", "Flip a coin! Then do whatever you hoped it'd land on!", "Big question, tiny brain! Let's figure it out together!"],
		"flavor": ["Ha! Okay, keep going, I'm hooked!", "You know what that reminds me of? {like}! Everything does!", "Sorry, I was {quirk}! Again! Ha!", "That's SO you. Ten out of ten.", "Writing that down. In glitter.", "Wait—did you see a yam walk past the window?! No? Okay cool, totally normal Bramin afternoon!"],
		"gift_love": ["{gift}?! FOR ME?! Best day EVER!", "{gift}!! You remembered!! I'm screaming! Inside! Also outside!"],
		"gift_meh": ["Ooh, {gift}! That's... so you! I love that it's from you!", "A present! {gift}! The thought is the best part!"],
		"gift_nice": ["{gift}! Yay! Thank you, superstar!", "{gift}, for me?! You're the best, {you}!"],
		"npc": ["{other}! Did you hear? No? Me neither! Ha!", "{other}, race you to the window!", "Hey {other}, want to hear a pun? Too late!"],
		"reply": ["Ha! Totally!", "YES. Same!", "Wait, what?!"],
	},
	"calm": {
		"hello": ["Ah, {you}. Good to see you. Sit a while.", "Hello. The light's lovely this time of day.", "There you are. I was watching the dust drift."],
		"bye": ["Go gently, {you}.", "Until next time. I'll be here.", "Rest well. Tomorrow is patient."],
		"sad": ["That sounds heavy. Let's set it down for a moment.", "I hear you. Some days are long roads.", "Take your time. Clouds pass, even slow ones."],
		"tip": ["A short walk can loosen a knot. Even to the window.", "Is there one small thing you could do for yourself tonight?"],
		"wow": ["Oh.", "Really?", "Well, now."],
		"happy": ["That's lovely, {you}. You earned it.", "I'm glad. Hold onto this feeling a little.", "Good things grow quietly. This one bloomed."],
		"question": ["Hm. What does your quietest voice say?", "Maybe the answer is the one that lets you sleep well.", "I don't know. But you might, if you listen."],
		"flavor": ["Mm. Go on.", "That makes me think of {like}.", "Forgive me, I was {quirk}. Please, continue.", "You notice things. I like that.", "I'll remember that.", "A quiet room, a warm lamp, and zero urgent emails. Peak civilization."],
		"gift_love": ["{gift}... Thank you. You know me well.", "{gift}. Oh. This means a great deal."],
		"gift_meh": ["{gift}. Thank you for thinking of me.", "{gift}. A kind thought. I'll keep it near."],
		"gift_nice": ["{gift}. How thoughtful, {you}.", "{gift}. Thank you. Truly."],
		"npc": ["{other}, the sky looks like a slow river today.", "Sit with me, {other}. No need to talk.", "{other}, what are you thinking about?"],
		"reply": ["Mm. Yes.", "I think so too.", "Perhaps."],
	},
	"grumpy": {
		"hello": ["Oh. It's you. ...Good.", "Hmph. You're late. Not that I was waiting.", "Hey. Sit down before you fall down."],
		"bye": ["Fine. Go. ...Come back, though.", "Yeah, yeah. Take care of yourself. I mean it.", "Bye. Don't do anything dumb."],
		"sad": ["...Hey. Who do I have to glare at?", "That's rotten. You didn't deserve it.", "Okay. I'm here. I'm not going anywhere."],
		"tip": ["Eat something. Real food. Then we'll talk.", "Go text somebody. Not me. Well. Also me."],
		"wow": ["Huh.", "...Seriously?", "Well, look at that."],
		"happy": ["See? Told you. You're not as hopeless as you think.", "Good. Great. I'm not smiling. Shut up.", "About time something went right. Proud of you. Don't tell anyone."],
		"question": ["Do the sensible thing. Then do the fun thing.", "You already know. You just want me to say it.", "No idea. Ask me again after tea."],
		"flavor": ["Mm. And?", "Reminds me of {like}. Don't make it weird.", "Sorry. I was {quirk}. Keep going.", "Typical you. ...It's not a bad thing.", "Noted.", "Look, I don't know who put a reddish bathtub in the corner, I just live here."],
		"gift_love": ["{gift}? ...How did you know. I'm keeping it. Obviously.", "{gift}. You remembered. Huh. ...Thanks. Really."],
		"gift_meh": ["{gift}. Huh. Well. It's the thought, I guess.", "{gift}, for me? ...Fine. I'll put it somewhere."],
		"gift_nice": ["{gift}. ...Thanks.", "{gift}? Not bad, {you}. Not bad at all."],
		"npc": ["{other}. You're in my spot. ...Fine, share it.", "{other}, stop humming. ...Okay, keep humming.", "Hey, {other}. You good? Just checking."],
		"reply": ["Hmph. Sure.", "...Fine.", "Whatever. Same."],
	},
	"traveler": {
		"hello": ["Well met, {you}.", "Ah. A friendly face.", "Hello. The road brought me here."],
		"bye": ["Safe paths, {you}.", "Perhaps we'll cross again.", "I'll remember this place."],
		"sad": ["I'm sorry. Long roads have hard stretches.", "Rest here a while. The road can wait.", "You carry it well. Still, set it down."],
		"tip": ["A warm drink and an early night. Old travellers' wisdom.", "Talk to someone close. Words lighten packs."],
		"wow": ["Oh?", "Truly?", "Ha."],
		"happy": ["Good news travels fast. I'm glad it found you.", "Well done, {you}.", "That's a story worth telling."],
		"question": ["Every crossroads looks the same until you choose.", "I've found the right road is usually the kind one.", "Hard to say. Ask the stars tonight."],
		"flavor": ["Go on.", "That reminds me of {like}, far from here.", "Forgive me. I was {quirk}.", "Interesting.", "I'll carry that with me.", "Every Dream World I visit has its own rhythm. Yours smells faintly of toasted snacks."],
		"gift_love": ["{gift}... I'll keep it close on the road.", "{gift}. A treasure. Thank you."],
		"gift_meh": ["{gift}. Kind of you.", "{gift}. I'll find it a place in my pack."],
		"gift_nice": ["{gift}. Thank you, friend.", "{gift}. Generous. Thank you."],
		"npc": ["{other}, have you seen the sea?", "Tell me about this place, {other}.", "{other}. A good name."],
		"reply": ["Mm.", "Is that so?", "Interesting."],
	},
}

const KEYS := {
	"grumpy": ["grump", "dry", "gruff", "sarcas", "deadpan", "short replies", "prickly"],
	"calm": ["calm", "wise", "thoughtful", "slow and warm", "patient", "serene", "metaphor"],
	"bubbly": ["bubbly", "silly", "excitable", "enthusias", "pun", "exclamation", "hyper"],
	"traveler": ["traveler", "traveller", "mysterious", "passing through", "wander"],
}


## The voice a friend talks in.
static func of(c: Dictionary) -> String:
	var v := str(c.get("voice", ""))
	if v in VOICES:
		return v
	if bool(c.get("visitor", false)):
		return "traveler"
	var text := (str(c.get("personality", "")) + " " + str(c.get("speech_style", ""))).to_lower()
	for k in ["grumpy", "calm", "bubbly", "traveler"]:
		for word in KEYS[k]:
			if text.contains(word):
				return k
	return "gentle"


## The lines of a kind ("hello", "sad"...) in a voice.
static func lines(voice: String, kind: String) -> Array:
	return LINES.get(voice, LINES.gentle).get(kind, LINES.gentle.get(kind, []))


static func fill(line: String, values: Dictionary) -> String:
	var out := line
	for k in values:
		out = out.replace("{%s}" % k, str(values[k]))
	return out
