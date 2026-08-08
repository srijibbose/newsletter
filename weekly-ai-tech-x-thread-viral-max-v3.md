# Weekly AI/Tech X Thread — Viral-Max Layer (v3)

*Builds on `weekly-ai-tech-x-thread-automation-v2.md`. Everything in v2 — sources, dedupe, diversity
enforcement, hosting, $0 cost model — carries forward unchanged. This doc adds four new layers on top:
hook engineering, a programmatic virality QA gate, a real branded visual system (charts, cards, one
optional animated clip), and native interactivity (poll + an actually-interactive companion page). The
goal, per your brief: nothing in the thread should ever go out as plain text, every fact should be
defensible, and the thread should read like it was made by a small, sharp media team — not a bot.*

---

## 0. Reality check, re-verified for this doc (Aug 2026)

I re-checked the load-bearing facts before building on top of them:

- **X still cannot natively schedule a full thread** (confirmed across multiple independent sources as
  of mid-2026 — single tweets can be scheduled via X Pro/native scheduler, desktop only, but a full
  thread cannot). This means the core architecture — n8n builds it, delivers it to your phone, you
  paste and post — is still the correct shape. Nothing structural changes here.
- **The link-in-body penalty is still contested, but most current distribution analysis still finds a
  real penalty** — commonly cited in the 30–50% reach reduction range for posts with an external URL in
  the main body, with "post the link as the first reply instead" remaining the standard workaround.
  One notable counter-data-point: independent review of X's own open-sourced ranking code (May 2026
  release) reportedly found no *hard-coded* link penalty in the algorithm itself — the effect may
  instead be indirect (links correlate with lower predicted engagement, which the model penalizes
  anyway). Practically, this doesn't change what you should do: still avoid links in tweet bodies where
  you can.
- **New signals worth designing around**, all independently reported by more than one source analyzing
  the open-sourced ranking model:
  - **Replies are weighted far above likes** — sources differ on the exact multiplier (numbers ranging
    from ~2–3x to over 20x show up depending on the analysis), but the direction is consistent enough
    to build around: a thread that generates real replies will outperform one that only generates
    likes, by a wide margin.
  - **Bookmarks appear to carry an outsized weight** relative to likes in several independent analyses.
    This is actionable: content designed to be *saved* (reference-style recaps, cheat sheets, "come
    back to this later" material) has a real distribution incentive that most threads don't build for.
  - **Native video gets the strongest distribution boost of any format**, ahead of images, ahead of
    GIFs, and well ahead of a plain link — even short (15–30 second) clips.
  - **Engagement velocity in the first ~30 minutes after posting** is repeatedly described as heavily
    weighted for initial reach. This sharpens the existing "reply in the first hour" advice from v2 —
    the real window that matters most is closer to the first 30 minutes.
  - **Active Community Notes now carry a measurable distribution penalty** while the note is live. This
    directly raises the cost of the workflow ever inventing or garbling a fact — see Section 6.

None of these numbers are official confirmed weights from X — they're independent analysts' reading of
open-sourced code and observed distribution data, and estimates vary source to source. Treat the exact
multipliers with skepticism; treat the *direction* (replies > likes, bookmarks matter more than they
look like they should, native video wins, accuracy has real teeth now) as solid enough to build a
strategy around.

---

## 1. What's new in v3, in one line each

| # | Addition | Solves |
|---|---|---|
| 1 | **Hook Engineering pass** — generates and scores 4 hook variants for tweet 1, picks the best | "Interesting" starts with the first line; one shot at a hook isn't enough |
| 2 | **Virality QA gate** — programmatic checklist run on the finished thread, auto-revises once if it fails | Quality shouldn't depend on the LLM getting it right on the first try |
| 3 | **Branded visual system** — every single tweet gets native media; nothing ships as plain text | You asked for "very interactive, very impressive" — text-only tweets can't deliver that |
| 4 | **Native interactivity** — an X-native poll + an actually-interactive companion micro-page | X threads aren't interactive by default; this adds real interactivity where the platform allows it |

---

## 2. Updated architecture

```
Weekly Schedule Trigger
        │
        ▼
Pull from sources (v2 Section 2, unchanged)
        │
        ▼
Merge → Dedupe → Filter to last 7 days (v2, unchanged)
        │
        ▼
LLM Pass 1 — Curate (Gemini): pick ~9 items + diversity/mix constraints
        │                      + NEW: is_debate_worthy flag for poll candidate
        ▼
Diversity check (Code node, v2 Section 3, unchanged)
        │
        ├──────────────► NEW: Hook Engineering (Pass 1.5)
        │                 4 hook variants, self-scored, best one picked
        │                 by a Code node (LLM soft layer + code hard layer,
        │                 same pattern as the diversity check)
        ▼
Media enrichment per item (v2 Section 4a/4b, unchanged) —
GitHub README GIF → project-page OG video/image → YouTube upload →
quote-tweet search
        │
        ▼
NEW: Numeric-claim extraction → auto-generated data chart (QuickChart)
for any item with no media yet but an extractable number
        │
        ▼
NEW: Universal quote-card fallback (branded HTML→image) for anything
STILL without media — this retires "media_type: none" entirely
        │
        ▼
LLM Pass 2 — Write (Gemini): chosen hook + curated items + media types →
full thread, now including a recap/cheat-sheet tweet and an optional poll
        │
        ▼
NEW: Virality QA gate (Code node) — checks char limits, banned phrases,
media coverage, question density, numeric density, recap presence
        │
        ├── fail ──► NEW: Revise pass (Gemini, fed the exact failed checks)
        │             → re-run QA gate once, then proceed regardless (capped
        │             retry — never loops more than once)
        ▼
NEW: Cover card generated for tweet 1 (branded HTML→image)
        │
        ▼
NEW (optional): one asset per week turned into a short animated MP4
via ffmpeg zoompan, for maximum native-video boost
        │
        ▼
Deliver to you: thread text + every image/video file, downloaded and
attached + poll instructions + companion-page reply link, all via Telegram
        │
        ▼
You paste + attach + post + poll + reply-link (~3-4 min now, still $0)
```

---

## 3. What actually makes a thread "stop the scroll"

This is the part no amount of automation replaces good judgment on, but it can be systematized enough
that the *floor* is high even on a lazy week. Five hook formulas, concrete and reusable — the Hook
Engineering prompt in Section 7 asks the model for one of each every week:

1. **Number-led.** Open with a specific, real number from this week's items. "A research team just cut
   inference cost by 71% without touching the model weights." Numbers are concrete, screenshot-able,
   and hard to skim past.
2. **Status-quo-violation.** Name what the reader currently believes or does, then contradict it.
   "Everyone assumed synthetic data would plateau by now. This week's paper says the opposite."
3. **Stakes.** Frame why this week's news changes what happens *next*, for the reader specifically —
   not "the industry" in the abstract. "If you ship anything with an LLM in it, this week's release
   quietly changes your cost math."
4. **Mini-story.** Compress one item's before/after into two clauses. "A 3-person team built in a
   weekend what took a well-funded startup 18 months. Here's what changed."
5. **The-behind-hook.** Names a gap between what's common knowledge and what just happened. Use
   sparingly — it's the easiest formula to overuse into cliché.

**Thread architecture, updated:**
- Open with the strongest hook + a native cover-card image (Section 5) — no link, ever, on tweet 1.
- Don't save the best item for last. Front-load value in tweets 2–4; readers who bail after three
  tweets should still have gotten something worth their time.
- Vary tweet *rhythm*, not just content — mix one-line punches with one or two tweets that go slightly
  longer and denser. Uniform-length tweets read as templated, which undercuts the "made by a real
  person" feel you're going for.
- Add a **recap/cheat-sheet tweet** near the end (numbered, one line per item) — this is the single
  most bookmarkable asset in the thread, and bookmarks are one of the underused high-weight signals
  from Section 0. Pair it with a recap *card* image (Section 5) and this becomes the thing people save
  and come back to.
- End with a specific, real question — not "thoughts?" — tied to something actually debatable in this
  week's items.
- **Emphasis without bold text:** X doesn't support real bold/italic formatting, but Unicode has a
  "Mathematical Alphanumeric Symbols" block that visually renders as bold in any font. Used sparingly
  (2–4 words, once per thread, on the single most important claim) it acts as a genuine pattern
  interrupt in a feed of visually identical tweets. Overused, it reads as spammy — cap it at one
  instance per thread. JS implementation:

```javascript
function toUnicodeBold(str) {
  const boldMap = {};
  const upperStart = 0x1D400, lowerStart = 0x1D41A, digitStart = 0x1D7CE;
  for (let i = 0; i < 26; i++) {
    boldMap[String.fromCharCode(65 + i)] = String.fromCodePoint(upperStart + i);
    boldMap[String.fromCharCode(97 + i)] = String.fromCodePoint(lowerStart + i);
  }
  for (let i = 0; i < 10; i++) {
    boldMap[String.fromCharCode(48 + i)] = String.fromCodePoint(digitStart + i);
  }
  return str.split('').map(ch => boldMap[ch] || ch).join('');
}
```

**Replies, revisited given Section 0's finding that replies vastly outweigh likes:**
- Be online in the **first 30 minutes**, not "sometime in the first hour" — tighten v2's guidance to
  match what the velocity signal actually rewards.
- Reply to your own thread with one extra item that didn't make the cut, or a follow-up fact. This is
  normal, expected behavior (not manipulation) and it does two legitimate things at once: gives readers
  more value, and gives the link-in-reply workaround (Section 0) a natural home if any item needed a
  plain link.

---

## 4. Guardrails — what this deliberately does NOT do

Worth stating explicitly, since "maximize virality" is exactly the kind of brief that can drift into bad
territory if you're not careful:

- **No manufactured urgency, no fake scarcity, no engagement-bait phrasing** ("comment YES if...",
  "RT if you agree") — these are against X's own platform rules in spirit and read as try-hard even when
  they technically work short-term.
- **No invented statistics or claims not traceable to the source data.** This isn't just an ethics
  position — Section 0's Community Notes finding means a fabricated claim now has a real, measurable
  distribution cost, on top of being wrong.
- **No purchased engagement, no bot replies, no coordinated inauthentic activity** — outside what this
  workflow does or should ever touch.
- **The human 60-second review stays a hard gate, every week, regardless of what the QA gate reports.**
  Automation raises the floor; it doesn't replace judgment before something goes out under your name.

---

## 5. The branded visual system

### 5a. Design tokens (pick once, reuse forever — this is what makes threads instantly recognizable)

```
Background:     #0B0D14  (near-black navy)
Accent:         #7C3AED  (violet) → #06B6D4 (cyan) gradient for charts/highlights
Text primary:   #F5F5F7
Text secondary: #9CA3AF
Font:           Space Grotesk (headlines) — distinctive, geometric, reads well at large sizes
Category tags:  🔬 research · 🚀 product-launch · 🛠️ open-source · 📰 industry-news · ✨ fun
                (unchanged from v2, now literally baked into every card too)
```

### 5b. The four visual types, in priority order per item

Media enrichment now tries these **in order** and stops at the first hit — this retires
`media_type: none` from v2 entirely. Every tweet ships with something native attached.

1. **`attached_gif` / `attached_video`** — demo GIF/video from a repo README or project page (v2
   Section 4a, unchanged).
2. **`quote_tweet_url` / `youtube_url`** — official announcement or keynote (v2 Section 4b, unchanged).
3. **`data_chart`** *(new)* — if the item's title/summary contains an extractable number (a dollar
   amount, a percentage, a parameter count, a benchmark score), auto-generate a small bar chart via
   QuickChart (free, no auth, no signup — see Section 8 in the implementation guide).
4. **`quote_card`** *(new, universal fallback)* — every curated item already has a `why_it_matters`
   field from the curation prompt. Render it as a styled pull-quote card using the design tokens above.
   Since every item has this field, this fallback always exists — nothing can fall through to plain
   text.

### 5c. Cover card (tweet 1)

Tweet 1's rule updates from v2's "hook only, no media" to **hook text + a native cover-card image, no
link.** There's no algorithmic downside here — it's not an external link, and native visual content is
consistently favored (Section 0) — so there's real upside to attaching one and no real cost.

Contents: the chosen hook headline, a small "This Week in AI/Tech" kicker, the date, and a row of the
category emoji previewing what's inside — same design tokens as every other card, so followers start
recognizing the format at a glance (this is the literal implementation of v2 Section 9's "visual
consistency" idea).

### 5d. Recap card

Paired with the recap/cheat-sheet tweet from Section 3 — same template, but listing all curated items
as a compact numbered list with one emoji + 4–6 words each. This is designed to be the single most
saved asset in the thread.

### 5e. Alt text

Every generated or fetched image gets a one-line alt-text description from the same LLM pass that
writes the thread (v2 Section 9 idea, now extended to the new card types too) — delivered alongside the
image in Telegram so you can paste it into X's alt-text field in the same ~3 seconds it takes to attach
the image.

### 5f. Optional: turning one asset into real native video

Section 0 confirmed native video gets the strongest boost of any format, by a wide margin over static
images. A static branded card can be turned into a short (4–5 second) animated clip with a Ken-Burns
style zoom using `ffmpeg`'s `zoompan` filter — genuinely simple once ffmpeg is available in the
container, and it turns your best static asset of the week into your best-performing format. This is
infra-heavier (needs a Docker image rebuild) so it's specced as an optional final stage in the
implementation guide — do it once Stages A–G are solid, and only for one asset per week (the cover card
or the strongest data chart) to keep render time and complexity in check.

---

## 6. The virality QA gate (Pass 3)

A programmatic checklist that runs on the finished, written thread — same "LLM writes it, code verifies
it" pattern as v2's diversity check, applied to overall thread quality this time:

```javascript
// Code node "Virality QA Gate"
const tweets = $input.all().map(i => i.json); // parsed thread array
const bannedPhrases = ["you won't believe", "gone viral", "shocking",
  "this changes everything", "mind-blowing"];
const issues = [];

tweets.forEach(t => {
  const limit = t.tweet_number === 1 ? 270 : 275;
  if (t.text.length > limit) issues.push(`Tweet ${t.tweet_number} over char limit`);
  if (bannedPhrases.some(p => t.text.toLowerCase().includes(p)))
    issues.push(`Tweet ${t.tweet_number} has a banned clickbait phrase`);
});

if (/https?:\/\//.test(tweets[0].text)) issues.push('Tweet 1 contains a link');

const noMedia = tweets.filter(t => !t.media_type || t.media_type === 'none');
if (noMedia.length > 0) issues.push(`${noMedia.length} tweet(s) have no visual assigned`);

const questionTweets = tweets.filter(t => t.text.includes('?'));
if (questionTweets.length < 2) issues.push('Fewer than 2 tweets ask a question');

const body = tweets.filter(t => t.tweet_number !== 1 && t.tweet_number !== tweets.length);
const withNumbers = body.filter(t => /\d/.test(t.text));
if (withNumbers.length / body.length < 0.6)
  issues.push('Fewer than 60% of body tweets contain a concrete number');

const hasRecap = tweets.some(t => (t.text.match(/\n?\d\.\s/g) || []).length >= 3 || t.is_recap === true);
if (!hasRecap) issues.push('No recap/cheat-sheet tweet found');

return [{ json: { pass: issues.length === 0, issue_count: issues.length, issues, tweets } }];
```

Wire an **IF** node after this: `pass === true` → straight to visual generation and delivery. `pass ===
false` → one revise pass (prompt in Section 7) fed the exact list of failed checks → run the QA gate
again → deliver either way, but if issues remain after the one retry, prepend a flag to the Telegram
message ("⚠️ auto-QA found N unresolved issues — check before posting") so your human review is targeted
at the actual weak spot instead of a generic re-read. Capped at one retry on purpose — this is a quality
floor, not a loop that burns API calls chasing a perfect score.

---

## 7. Updated prompts (full text)

**Curation prompt (Pass 1)** — same as v2 Section 6, with one addition (the `is_debate_worthy` flag
feeds the poll in Section 8):

```
You are curating content for a weekly tech & AI thread on X, aimed at an
engaged, technically literate audience. Below is a list of candidate items
from the last 7 days, each tagged with a rough source_org and category
(research / product-launch / open-source / industry-news / fun).

Select 9 items for the thread. Requirements:
- No more than 2 items from the same source_org, even if more of their
  news would otherwise qualify. If one company had an unusually large
  event this week, pick only their single most important item.
- Aim for this mix: 3-4 research, 2-3 product/company, 1-2 open-source,
  1 lighter/fun item. Adjust only if the week's actual news genuinely
  doesn't support it.
- Prioritize items with an available demo video, GIF, or official
  announcement post when quality is otherwise comparable.
- Flag exactly ONE item as "is_debate_worthy": true if it has two
  genuinely defensible sides (a real design tradeoff, a real open
  question) — this will become a poll. If nothing qualifies, flag none.
- Every "why_it_matters" field must be a claim you can point to a specific
  title/summary below for. Do not invent details not present in the data.

Return as JSON: [{ "title", "url", "source_org", "category",
"why_it_matters", "media_hint", "is_debate_worthy" }]

CANDIDATE ITEMS:
{{items}}
```

**Hook Engineering prompt (Pass 1.5, new):**

```
You are a viral X (Twitter) copywriter for a technically literate AI/tech
audience. Below are this week's curated items. Write ONLY the opening hook
tweet (tweet 1) — not the rest of the thread.

Generate 4 different hook variants, each using a different formula:
1. NUMBER-LED: opens with a specific, real number from the items below
2. STATUS-QUO-VIOLATION: names a common assumption, then contradicts it
   with what happened this week
3. STAKES: frames why this changes what happens next for the reader
   specifically, not the industry in the abstract
4. MINI-STORY: compresses one item's before/after into two clauses

Hard rules:
- Every specific fact must be traceable to a title/summary/why_it_matters
  field below. Never invent a number, name, or event.
- No link, no "🧵" spam. Under 270 characters.
- Never use: "you won't believe", "gone viral", "SHOCKING", "this changes
  everything", "wait until you see", "mind-blowing".
- Make the reader want the SPECIFIC next fact, not just feel vague hype.

Self-score each variant 1-10 on: specificity (concrete detail, not just
hype), curiosity_gap (withholds one specific thing), credibility (reads
like a real claim, not an ad).

Return ONLY JSON:
[{ "formula": "...", "text": "...", "specificity": N, "curiosity_gap": N,
"credibility": N }]

ITEMS:
{{curated_items}}
```

Pick the winner with a small Code node (sum the three scores, take the max — same hard-layer-backs-up
soft-layer pattern as the diversity check):

```javascript
const variants = $input.first().json; // parsed array from Gemini
const best = variants.reduce((a, b) =>
  (a.specificity + a.curiosity_gap + a.credibility) >=
  (b.specificity + b.curiosity_gap + b.credibility) ? a : b);
return [{ json: best }];
```

**Writing prompt (Pass 2)** — extended from v2 Section 6 with the recap tweet, poll output, and the two
new media types:

```
Using ONLY the items below, write an 11-post X thread for a technically
literate audience. Tweet 1's text is ALREADY WRITTEN (given below as
chosen_hook) — do not rewrite it, just use it as-is.

Each item includes a media_type: "attached_gif", "attached_video",
"quote_tweet_url", "youtube_url", "data_chart", or "quote_card". Write
each tweet accordingly:
- attached_gif / attached_video / data_chart / quote_card: NO link in the
  text (media is attached natively) — just the hook and why it matters.
- quote_tweet_url: a short reaction/context line, since this posts as a
  quote-tweet of that URL — add value, don't re-describe the announcement.
- youtube_url: put the link as the LAST line, after the substantive point.

- Tweet 1: use chosen_hook verbatim. No link, no additional media note
  needed (cover card is generated separately).
- Tweets 2-9: one item each, per the media rules above. Under 275
  characters (before any link). Vary sentence rhythm — don't make every
  tweet the same length and shape.
- Tweet 10: a RECAP tweet — a numbered list (1. through however many
  items), one line each, 4-8 words per line, no links. Mark this tweet
  with "is_recap": true.
- Tweet 11: short wrap-up + one specific, genuinely debatable question
  (not "thoughts?").

If any item has "is_debate_worthy": true, also output a "poll" object:
{ "tweet_number": <the tweet for that item>, "question": "...",
"options": [2 to 4 short options] }. If no item qualifies, omit "poll".

Wrap exactly one short, high-impact phrase (2-4 words) across the whole
thread in Unicode bold characters, on the single most important claim,
using this mapping: [A-Z]→𝐀-𝐙, [a-z]→𝐚-𝐳, [0-9]→𝟎-𝟗. Use it once only.

Output alt text (one line) for every tweet with a data_chart or
quote_card media_type.

Return as a structured JSON list, one tweet block per item, with fields:
tweet_number, text, media_type, alt_text (if applicable), is_recap
(tweet 10 only).

ITEMS:
{{curated_items_with_media}}

chosen_hook: {{chosen_hook_text}}
```

**Revise prompt (Pass 3, used only if the QA gate fails):**

```
The X thread below failed automated quality checks. Fix ONLY the specific
issues listed — do not rewrite tweets that aren't flagged, and do not
change any facts, numbers, or media_type assignments.

ISSUES FOUND:
{{issues_list}}

CURRENT THREAD:
{{current_thread_json}}

Return the corrected thread in the exact same JSON shape.
```

---

## 8. Content mix, updated (11 slots)

| Slot | Content | Visual |
|---|---|---|
| 1 | Hook (chosen from 4 scored variants) | **Cover card** (new) |
| 2–4 | Research papers | Demo GIF/video → data chart → quote card |
| 5–7 | Product/company launches | Quote-tweet, YouTube, or data chart |
| 8 | Open-source/tool release | GitHub README GIF or quote card |
| 9 | One lighter/fun item + optional **poll** if flagged debate-worthy | Whatever's natural |
| 10 | **Recap tweet** (new) — numbered cheat-sheet of the week | **Recap card** (new) |
| 11 | Wrap-up + specific question | — |

---

## 9. Native interactivity

### 9a. The poll

X's API can't create polls, and this is still a manual-paste workflow anyway (v2's whole design), so the
poll is delivered as a clearly marked instruction alongside the thread text: *"Tweet 9 has a poll —
tap the poll icon in the X composer and enter these options: [...]."* Costs you one extra tap; native
polls are explicitly called out across current algorithm analysis as a format the ranking system scores
well, on top of being genuinely interactive in a way plain text can't be.

### 9b. The companion micro-page (optional, the "real" interactivity)

For the single strongest story each week, generate a small, genuinely interactive static HTML page (a
hoverable chart, or a simple before/after comparison) and publish it for free via GitHub Pages. Link it
in the **first reply** under tweet 1 — not the main thread body — which sidesteps the link-penalty
question entirely (Section 0's own recommended workaround) while giving genuinely curious readers
somewhere to go deeper than 275 characters allows. This is the most infrastructure-heavy addition in
this doc (needs a GitHub repo + personal access token), so it's specced as its own stage in the
implementation guide — build it once everything else is solid.

---

## 10. The feedback loop, upgraded

v2 Section 9 already suggested logging picks and skimming analytics after a month. Extend it:

- Log, per week: which hook formula was chosen, each tweet's `media_type`, and (a month later) that
  week's bookmark + reply counts from your own X analytics.
- Every ~4–6 weeks, skim which hook formulas and media types correlate with your best bookmark/reply
  weeks, and fold that back into the Hook Engineering and curation prompts as a soft preference (e.g.
  "number-led hooks have outperformed status-quo-violation hooks on this account — prefer them when
  both are viable").
- Keep the quarterly best-of idea from v2 unchanged — it's still cheap and still a good idea.
- **X Premium** is worth a one-line mention since Section 0 found Premium accounts get a reach
  multiplier in current ranking — this is a paid, optional lever outside the $0 ethos of the rest of
  this build, and a subscription decision only you can make; noted here as a factual option, not a
  recommendation.

---

## 11. Setup checklist (v3 additions only — v2's checklist still applies first)

1. Add the Hook Engineering pass (Section 7) between the diversity check and media enrichment.
2. Add the numeric-claim extraction + QuickChart data-chart generation for items without existing media.
3. Add the universal quote-card fallback so `media_type: none` can never occur.
4. Add the cover-card and recap-card generation.
5. Update the Pass 2 writing prompt to the v3 version (recap tweet, poll output, new media types).
6. Add the Virality QA gate + capped one-retry revise loop.
7. Update Telegram delivery to include poll instructions and (if built) the companion-page reply link.
8. Optional: build the ffmpeg animation stage last, once everything above is stable.
9. Run it a few times, confirm every tweet has a visual, confirm the QA gate actually catches issues
   when you deliberately break something (good test: temporarily add a banned phrase to a prompt and
   confirm the gate flags it).
