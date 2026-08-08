# Automated Weekly Tech & AI X Thread — Build Guide (v2)

*Supersedes the first draft. Adds: rich media (video/GIF/image) sourcing per tweet, content-diversity rules so one company can't dominate the thread, and current X algorithm strategy. Still fully free except the 2-minute manual paste.*

---

## 0. Reality check (unchanged, still true)

- X's official API dropped its free tier in Feb 2026 (pay-per-use now: ~$0.015/post, $0.20/post with a link, $0.005/read). X still can't natively schedule a full thread.
- Everything below automates **research → curation → writing → media gathering**, and delivers a finished, ready-to-post thread (with the media files already downloaded for you) straight to your phone. You paste it in and hit post — ~2 minutes, $0.
- One new wrinkle worth knowing up front: **X's own algorithm treatment of external links is genuinely contested right now.** Through most of 2025–2026, independent analysis of X's (open-sourced, Jan 2026) algorithm found posts with links in the main body got 30–94% less reach, and the standard workaround was "link in reply, not in the post." In late July 2026, Musk stated X stopped doing this over a year ago and disputed the penalty was ever real — which is itself disputed by the data. Nobody outside X can say for certain which is true this week. The strategy below hedges for both cases.

---

## 1. Updated architecture

```
Weekly Schedule Trigger
        │
        ▼
Pull from sources (7+ parallel branches — see v1 doc / Section 2 below)
        │
        ▼
Merge → Dedupe → Filter to last 7 days
        │
        ▼
LLM Pass 1 — Curate (Gemini): pick ~9 items, ENFORCING topic/company diversity
        │
        ▼
Diversity check (Code node): programmatically verify no source has >2 items;
swap in alternates from the leftover pool if it does
        │
        ▼
NEW: Media enrichment (per item): find a demo video/GIF/official post to attach
        │
        ▼
LLM Pass 2 — Write (Gemini): turn picks + media notes into the actual thread text
        │
        ▼
Format-check (char counts, link placement per algorithm strategy)
        │
        ▼
Deliver to you: thread text (Telegram/email) + the actual media files, downloaded
and attached to the message, ready to drag into X's compose box
        │
        ▼
You paste + attach + post (~2 min)
```

The only structurally new stage is **media enrichment** — everything else is the same skeleton as before, just with a diversity guardrail added.

---

## 2. Content sources (recap)

Same list as before — arXiv API, Hugging Face Trending Papers, Hacker News (Firebase/Algolia), AI lab blog RSS, tech news RSS, GitHub Trending, subreddit `.rss`, Product Hunt API. All free, all still current. See Section 2 of the original doc for endpoints if you need them again — nothing changed there.

**One addition:** tag each item as it's fetched with a rough `source_org` (OpenAI, Google, Anthropic, Meta, Apple, Microsoft, NVIDIA, "independent research," "open source," etc.) and a `category` (research / product-launch / open-source / industry-news / fun). This is cheap to do with a keyword/domain match in a Code node right after each fetch, and it's what makes Sections 3 and 5 below possible.

---

## 3. The diversity problem — solved two ways

You're right that if Google has a huge event in a given week, an unconstrained "pick the best 9 items" pass will happily fill the whole thread with Google news. Two layers fix this:

**Layer 1 — prompt constraint (soft).** Added directly to the curation prompt (full text in Section 6):
> "No more than 2 items from the same company, even if more of their news qualifies. If one company had an unusually large event, pick only their single most important item and fill the remaining slots with other sources. Aim for this mix across the thread: 3–4 research papers, 2–3 product/company items, 1–2 open-source/tools, 1 lighter/fun item."

**Layer 2 — programmatic enforcement (hard).** LLMs don't always perfectly follow counting instructions, so back it up with a Code node that actually counts:

```javascript
// n8n Code node — enforce source diversity after LLM curation
const picked = $input.all().map(i => i.json);      // LLM's picks
const pool = $('Filtered Candidates').all().map(i => i.json); // full leftover pool

const counts = {};
const kept = [];
const overflow = [];

for (const item of picked) {
  const org = item.source_org || 'independent';
  counts[org] = (counts[org] || 0) + 1;
  if (counts[org] <= 2) kept.push(item);
  else overflow.push(item);
}

// backfill each dropped slot with the next-best item from a different, less-used org
for (const dropped of overflow) {
  const replacement = pool.find(p =>
    !kept.includes(p) &&
    (counts[p.source_org] || 0) < 2
  );
  if (replacement) {
    kept.push(replacement);
    counts[replacement.source_org] = (counts[replacement.source_org] || 0) + 1;
  }
}

return kept.map(i => ({ json: i }));
```

This guarantees the rule holds even on weeks the model gets lazy about it — cheap insurance, and it's a Code node you set up once and never think about again.

---

## 4. Making it visual — the media playbook

This is the core of what you asked for. Different item types need different media strategies, both for what's *available* and for what's *safe to use*.

### 4a. Research papers with a demo video/GIF

Papers in robotics, graphics, computer vision, and increasingly LLM/agent work very often ship a project website or a GitHub repo with a demo GIF or short video — usually released by the authors specifically so people will share it.

**How to find it, per item, automatically:**
1. Regex the arXiv abstract text for any URL that isn't `arxiv.org` itself — authors frequently write "Project page: https://..." or "Code: https://github.com/..." directly in the abstract.
   ```javascript
   const urlRegex = /https?:\/\/[^\s)]+/g;
   const links = (abstractText.match(urlRegex) || []).filter(l => !l.includes('arxiv.org'));
   ```
2. If a GitHub link is found, fetch the raw `README.md` (`raw.githubusercontent.com/.../README.md`, free, no auth) and look for the first `.gif`/`.mp4`/embedded video badge:
   ```javascript
   const mediaRegex = /!\[[^\]]*\]\(([^)]+\.(gif|png|jpe?g))\)|(https?:\/\/\S+\.mp4)/gi;
   ```
3. If a standalone project page is found instead, a quick HTTP fetch + look for `<video>` or `<source>` tags, or an Open Graph `og:video`/`og:image` meta tag, usually finds the hero demo asset in one shot.
4. If nothing turns up, fall back to **the paper's own Figure 1** — most papers have one compelling result figure. You can extract embedded images from the arXiv PDF with a PDF library (e.g. PyMuPDF in a Code/Execute node) and grab the largest image on page 1. This alone makes a huge visual difference for a plain-text research tweet.

**On sourcing/crediting:** authors publish these assets expecting them to circulate — that's the whole point of a project-page GIF. Standard practice (and the respectful one) is to always credit the paper/authors and link back to the source in the tweet text, same as any research-sharing account does.

### 4b. Company announcements (OpenAI, Google, Apple, etc.)

This is the case to be more careful with — these are produced marketing/keynote videos, not assets released for redistribution. Two genuinely good options, in priority order, that sidestep the copyright question entirely because you're not downloading or re-hosting anything:

1. **Quote-tweet their own X post.** Almost every major AI/tech company posts its own launch announcement on X, often with native video already attached. If your workflow can find the URL of that post, the strongest move is to have your thread **quote-tweet it** — X natively renders their video inline, it's zero copyright risk (you're linking within X's own platform, not copying content), and it's *more* engaging than a plain link because readers see the real announcement video without leaving the app.
   - How to find the URL for free: a plain web search for `site:x.com [company handle] [product name]` usually surfaces it within a day of a major announcement (search engines index X posts reasonably fast for big accounts). n8n can run this via a Google Custom Search free-tier call or even just a Code node hitting a search engine's results page.
   - Fallback if you can't find it via search: check the company's official YouTube channel directly (see below) and use that instead.
2. **Link the official YouTube upload.** Companies almost always mirror keynote/launch videos to YouTube same-day. The **YouTube Data API v3 is free** — 10,000 quota units/day, no card required. Rather than burning your quota on `search.list` (100 units/call, ~100 searches/day max), pre-register the channel IDs of the labs you care about (OpenAI, Google, Google DeepMind, Anthropic, Meta AI, Microsoft, NVIDIA…) and pull each channel's `uploads` playlist with `playlistItems.list` (1 unit/call) — that gets you their last 5–10 videos for almost nothing, and you just keyword-match against the week's topic locally.
   - Note: a pasted YouTube link is still an *external* link, so it's subject to whatever the current link situation turns out to be (Section 0). It's a solid fallback, just not as strong as option 1.

**What I'd avoid:** don't build the workflow to download a clip from a company's marketing video and re-upload it as your own attached media. That crosses from "sharing/linking," which is normal and low-risk, into "re-hosting someone else's produced video content," which is a meaningfully different — and unnecessary — risk, especially running automatically every week. Quote-tweeting gets you the exact same visual payoff natively, for free, with none of that risk.

### 4c. Delivering the media to you

Since you're posting manually, the workflow should hand you the finished assets, not just links. A Telegram bot node is the cleanest way to do this: n8n downloads whatever GIF/image/video it found (Section 4a) to a temp file, and sends it to you as an actual Telegram message alongside that tweet's text — you save it to your phone with one tap and drag it straight into the X compose box. For quote-tweets (Section 4b, option 1), there's no file to send — the workflow just includes the X post URL in the delivered thread text, and you paste that URL into a fresh compose box, which makes X auto-convert it into a native quote-tweet.

One practical limit: Telegram's bot API caps file sends around 50MB, which is far more than any GIF or short demo clip needs — fine for this use case.

---

## 5. Content mix & style, updated

Suggested weekly template (adjust to taste, but having *a* template is what makes the thread feel curated rather than reactive):

| Slot | Content | Media |
|---|---|---|
| 1 | Hook — no link, no media, just the tease | — |
| 2–4 | Research papers | Demo GIF/video or Figure 1 (Section 4a) |
| 5–7 | Product/company launches | Quote-tweet or YouTube link (Section 4b) |
| 8 | Open-source/tool release | GitHub README GIF if available |
| 9 | One lighter/fun item | Whatever visual is natural |
| 10 | Wrap-up + question | — |

### Link placement, given the algorithm uncertainty (Section 0)

Since it's genuinely unclear this week whether links-in-body still cost reach, hedge instead of guessing:
- For items using **quote-tweets** or **native attached media** — no external link needed in the text at all, so this doesn't apply. This is another reason quote-tweets/native media are the stronger choice where available.
- For items that do need a plain link (no media found) — put the link as the **last line of that tweet**, after the substance, so the content itself lands regardless of any link penalty, and consider watching your own analytics after a few weeks to see whether isolating links into same-item reply-unders measurably helps for your account specifically.

---

## 6. Updated prompts

**Curation prompt (Pass 1) — now with diversity + mix constraints:**
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
  announcement post (flagged in the has_media field) when quality is
  otherwise comparable — these make stronger tweets.
- Do not invent details not present in the data below.

Return as JSON: [{ "title", "url", "source_org", "category",
"why_it_matters", "media_hint" }]

CANDIDATE ITEMS:
{{items}}
```

**Thread-writing prompt (Pass 2) — now media-aware:**
```
Using ONLY the items below, write a 10-post X thread. Each item includes
a media_type field: "attached_gif", "attached_video", "quote_tweet_url",
"youtube_url", or "none" — write each tweet accordingly:

- attached_gif / attached_video: write the tweet with NO link in the text
  (the media will be attached natively when posted) — just the hook and
  why it matters.
- quote_tweet_url: write a short reaction/context line (this will be
  posted as a quote-tweet of that URL, so don't re-describe the whole
  announcement — add value instead, e.g. "the demo at 0:40 is the part
  to watch").
- youtube_url or none: put the link as the LAST line of the tweet, after
  the substantive point.

- Tweet 1: hook only, no link, no media reference. Under 270 characters.
- Tweets 2-9: one item each, per the media rules above. Under 275
  characters (before any link).
- Tweet 10: short wrap-up + a question inviting replies.

Number each tweet "1/10" etc. For each tweet, also output which media
file (if any) should be attached, and if it's a quote_tweet_url, the
exact URL to paste. Output as a structured list, one tweet block per item.

ITEMS:
{{curated_items_with_media}}
```

---

## 7. Everything else from v1 (unchanged)

These sections carry over as-is from the first draft — nothing about them changed:
- n8n hosting (self-hosted Community Edition, free forever; Oracle Cloud Always Free VM as the $0 hosting option)
- Gemini API free tier for the LLM calls
- Best day/time to post (Tue–Thu 9am–12pm/2–5pm generally strongest; Sunday evening/Monday morning as a content-fit compromise for a "past week" format)
- Path A ($0, manual paste) vs Path B (~$5–10/month, fully automatic via X API) — Path A is still what this is built around
- Quality-control basics: cast a wide net, auto-widen the date window on slow weeks, keep a 60-second human glance before posting, log picks weekly to catch systematic gaps

---

## 8. Setup checklist (updated)

1. Everything from the v1 checklist (Gemini key, n8n hosting, source branches, dedupe/filter, Telegram bot).
2. Add the `source_org` / `category` tagging step right after each source fetch (simple keyword/domain match, a few minutes of Code-node work).
3. Add the diversity-check Code node (Section 3) after the curation LLM call.
4. Add the media-enrichment branch (Section 4a/4b) — start simple (just the GitHub README GIF regex) and add the project-page and Figure-1-extraction fallbacks later once the basic version is working.
5. Pre-register the channel IDs of 6–8 labs you care about for the YouTube `playlistItems.list` lookup (Section 4b) — a one-time setup that saves quota forever after.
6. Update both Gemini prompts to the v2 versions above.
7. Point the Telegram delivery node at both the thread text *and* any downloaded media files.
8. Run it manually a few times, check that attachments actually arrive usable, tune from there.

---

## 9. Extra ideas worth considering (you asked me to think beyond the brief)

- **Visual consistency**: use the same small emoji-per-category convention every week (🔬 research, 🚀 launch, 🛠️ open-source, ✨ fun) — readers start recognizing your format, which itself becomes a small brand.
- **Alt text**: have the writing prompt also generate a one-line alt-text description for each attached image/GIF — takes seconds, is genuinely more accessible, and costs nothing.
- **Reply engagement window**: whatever the current link-penalty truth turns out to be, every source agrees replies are the single strongest positive signal right now. Spend 10–15 minutes replying to comments in the first hour after you post — bigger lever than almost anything upstream of it.
- **Feedback loop**: after a month or two, skim your own X analytics (free, native, no API needed) for which categories/items in past threads got the most replies/bookmarks, and feed that back into the curation prompt's priorities (e.g. "research items with a demo video consistently outperform text-only industry news — weight accordingly").
- **Quarterly best-of**: every ~12 weeks, have a variant workflow compile the single highest-engagement item from each week into a "best of the quarter" thread — cheap to build (you already log picks weekly per Section 7) and it's a natural extra piece of content from data you're already collecting.
