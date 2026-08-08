# Implementation Guide v3 — Viral-Max Stages (E–H)

Companion to `weekly-ai-tech-x-thread-viral-max-v3.md` (the design doc) and the original
`implementation-guide.md` (Stages A–D). **This document assumes Stages A–D are already built and
working** — the Minimum Viable Thread runs, Telegram delivery works, and the full v2 feature set
(sources, diversity enforcement, media enrichment) is in place. Everything below is additive: four new
stages layered on top, same "build one piece, test it, move on" discipline as the original guide.

| Stage | What you get at the end of it | New accounts needed |
|---|---|---|
| **E** | Hook engineering + auto-QA with one capped revise retry | None |
| **F** | Every tweet has a native visual — charts, branded cards, zero plain text | htmlcsstoimage.com (free) |
| **G** | Native poll instructions + an actually-interactive companion page | GitHub (free, if doing 9b) |
| **H** *(optional)* | One asset/week becomes a short native video via ffmpeg | None (Docker rebuild only) |

---

# STAGE E — Hook Engineering + Virality QA Gate

No new accounts. Pure workflow nodes, inserted into your existing pipeline.

### E1. Insert the Hook Engineering pass

Locate where your **diversity-check Code node** (v2/original guide Section B2) outputs the final
curated list. Insert these three nodes right after it, in parallel with (not replacing) the branch that
continues to media enrichment:

1. **Code** node "Build Hook Prompt" — same pattern as "Build Curation Prompt" from Stage A6, but using
   the design doc's Section 7 Hook Engineering prompt text. Feed it the diversity-checked item list.
2. **HTTP Request** node "Gemini Hook" — identical setup to your existing "Gemini Curate"/"Gemini Write"
   nodes (same URL pattern, same `responseMimeType: "application/json"` body).
3. **Code** node "Pick Best Hook":

```javascript
const variants = JSON.parse($input.first().json.candidates[0].content.parts[0].text);
const best = variants.reduce((a, b) =>
  (a.specificity + a.curiosity_gap + a.credibility) >=
  (b.specificity + b.curiosity_gap + b.credibility) ? a : b);
return [{ json: best }];
```

Execute once, check the output has `{ formula, text, specificity, curiosity_gap, credibility }` — the
`text` field is what you'll feed into Pass 2 as `chosen_hook_text` next.

### E2. Update the Pass 2 (Writing) prompt

Open your existing "Build Writing Prompt" Code node. Replace the prompt string with the design doc's
Section 7 v3 writing prompt (the one that says "Tweet 1's text is ALREADY WRITTEN"). Two placeholders to
wire up:
- `{{curated_items_with_media}}` — same as before, from your media-enrichment branch.
- `{{chosen_hook_text}}` — pull this from the "Pick Best Hook" node's output, e.g. in n8n expression
  syntax: `{{ $('Pick Best Hook').item.json.text }}`.

Re-run once and confirm tweet 1 in the output matches the chosen hook verbatim (the model shouldn't be
rewriting it — if it is, tighten the "use as-is" instruction).

### E3. Add the Virality QA gate

Right after your "Parse Thread" Code node (which turns Gemini's Pass-2 output into the array of tweet
objects), add:

**Code** node "Virality QA Gate" — paste the exact code from the design doc's Section 6. It returns
`{ pass, issue_count, issues, tweets }`.

### E4. Add the revise loop

1. **IF** node "QA Passed?" — condition: `{{ $json.pass }}` is `true`.
   - **True branch** → continue straight to visual generation (Stage F) / delivery.
   - **False branch** → continue below.
2. On the false branch, **Code** node "Build Revise Prompt":

```javascript
const data = $input.first().json;
const prompt = `The X thread below failed automated quality checks. Fix ONLY the specific
issues listed — do not rewrite tweets that aren't flagged, and do not
change any facts, numbers, or media_type assignments.

ISSUES FOUND:
${data.issues.join('\n')}

CURRENT THREAD:
${JSON.stringify(data.tweets)}

Return the corrected thread in the exact same JSON shape.`;
return [{ json: { prompt } }];
```

3. **HTTP Request** node "Gemini Revise" — same setup pattern as your other Gemini calls.
4. **Code** node "Parse Revised Thread" — same parse pattern as "Parse Thread."
5. Route this back through the **same** "Virality QA Gate" node (reuse it, don't duplicate it — connect
   the "Parse Revised Thread" output into it).
6. Add a second **IF** node after this second QA pass: regardless of `pass` true/false this time,
   proceed to delivery — but if still `false`, prepend a flag. Simplest way to do this without a real
   loop-with-counter: since the revise branch only ever runs once (it's downstream of the *first* IF's
   false branch, and there's no path back to "Build Revise Prompt" from the second QA check), this
   structurally caps the retry at exactly one — no counter variable needed.
7. **Code** node "Add QA Flag" (only on this second path, both true and false sub-branches merge into
   it): 

```javascript
const data = $input.first().json;
const flag = data.pass ? '' : `⚠️ Auto-QA found ${data.issue_count} unresolved issue(s) after one revision — check before posting: ${data.issues.join('; ')}\n\n`;
return [{ json: { ...data, delivery_flag: flag } }];
```

Merge both the original "QA Passed? → True" path and this "Add QA Flag" path into whatever node comes
next (Stage F's visual generation), so both cases converge onto the same downstream pipeline.

### E5. Test

Run the whole thing manually. Then deliberately break it once to confirm the gate actually catches
things: temporarily hardcode a banned phrase into a test item's `why_it_matters`, run it through, and
confirm (a) the QA gate flags it, (b) the revise pass fixes it, (c) if it somehow still fails, the
Telegram message actually shows the ⚠️ flag. Revert the test hack afterward.

---

# STAGE F — Branded Visual System

Needs one new free account: **htmlcsstoimage.com**.

### F1. Create the htmlcsstoimage.com account

1. Go to https://htmlcsstoimage.com → sign up (free, no card required).
2. Dashboard → grab your **User ID** and **API Key**. Free tier is 50 images/month, no card, images
   auto-expire after 1 year on the free plan — this workflow needs roughly 8–12 images/week (well under
   quota even accounting for testing iterations). Save both values somewhere safe; you'll use them as
   Basic Auth (User ID as username, API Key as password) in the HTTP Request nodes below.
3. Note: the exact request field names below match their API as of this writing — if a call 400s,
   open https://docs.htmlcsstoimage.com and diff against what's below before assuming your workflow is
   broken; third-party API shapes drift occasionally, same caveat as the RSS-feed note in the original
   guide.

### F2. Build the cover card (tweet 1)

1. **Code** node "Build Cover Card HTML":

```javascript
const hook = $('Pick Best Hook').item.json;
const items = $input.all().map(i => i.json);
const emojiRow = [...new Set(items.map(i =>
  ({research:'🔬','product-launch':'🚀','open-source':'🛠️','industry-news':'📰',fun:'✨'}[i.category] || '💡')
))].join(' ');
const date = new Date().toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' });

const html = `<div style="width:1080px;height:1080px;display:flex;flex-direction:column;
justify-content:center;padding:90px;background:linear-gradient(135deg,#0B0D14,#1A1035);
font-family:'Space Grotesk',sans-serif;color:#F5F5F7;">
  <div style="font-size:32px;color:#9CA3AF;margin-bottom:20px;">THIS WEEK IN AI &amp; TECH · ${date}</div>
  <div style="font-size:58px;font-weight:700;line-height:1.3;">${hook.text}</div>
  <div style="font-size:44px;margin-top:50px;">${emojiRow}</div>
</div>`;
return [{ json: { html } }];
```

2. **HTTP Request** node "Render Cover Card":
   - Method `POST`, URL `https://hcti.io/v1/image`
   - Auth: Basic Auth credential (User ID / API Key from F1)
   - Body (JSON): `{ "html": "={{ $json.html }}", "google_fonts": "Space Grotesk" }`
   - Response contains a `url` field pointing to the rendered PNG.
3. **HTTP Request** node "Download Cover Card" — GET the `url` from the previous node's response, set
   **Response Format: File** so you get binary image data.
4. Wire this binary output into a **Telegram** node — **Send Photo** — as the attachment for tweet 1,
   caption = tweet 1's text.

### F3. Numeric-claim extraction

Insert this in the media-enrichment branch, after your existing GitHub/OG-tag/YouTube lookups (v2
Section 4a/4b), for items that still don't have a `media_type` assigned:

```javascript
const items = $input.all().map(i => i.json);
const numRegex = /(\$[\d,.]+\s?(?:B|M|K|billion|million)?|\d+(?:\.\d+)?\s?%|\d+(?:\.\d+)?\s?(?:B|M)\s?parameters?)/gi;

return items.map(item => {
  if (item.media_type) return { json: item }; // already has media, skip
  const text = `${item.title} ${item.summary}`;
  const matches = [...new Set((text.match(numRegex) || []))].slice(0, 2);
  return { json: { ...item, chart_candidates: matches, has_chartable_number: matches.length > 0 } };
});
```

### F4. Build the data chart (QuickChart — no account, no auth needed)

**Code** node "Build QuickChart URL", only for items where `has_chartable_number` is true:

```javascript
function buildChartUrl(item) {
  const nums = item.chart_candidates.map(s => parseFloat(s.replace(/[^0-9.]/g, '')));
  let config;
  if (nums.length >= 2) {
    config = { type: 'bar', data: { labels: ['Before', 'Now'],
      datasets: [{ label: item.title, data: nums, backgroundColor: ['#4B5563', '#7C3AED'] }] },
      options: { plugins: { legend: { display: false },
        title: { display: true, text: item.title, color: '#E5E7EB' } },
        scales: { y: { ticks: { color: '#E5E7EB' } }, x: { ticks: { color: '#E5E7EB' } } } } };
  } else {
    config = { type: 'bar', data: { labels: [item.chart_candidates[0]],
      datasets: [{ data: [nums[0]], backgroundColor: ['#7C3AED'] }] },
      options: { indexAxis: 'y', plugins: { legend: { display: false },
        title: { display: true, text: item.title, color: '#E5E7EB' } } } };
  }
  const encoded = encodeURIComponent(JSON.stringify(config));
  return `https://quickchart.io/chart?width=600&height=400&backgroundColor=%230B0D14&c=${encoded}`;
}

return $input.all().map(i => ({
  json: { ...i.json, media_url: buildChartUrl(i.json), media_type: 'data_chart' }
}));
```

Then, same pattern as F2 steps 3–4: **HTTP Request** GET the `media_url` (Response Format: File) →
**Telegram Send Photo**.

### F5. Universal quote-card fallback

For anything that reaches this point in the branch still without a `media_type` (no GIF, no OG image, no
YouTube match, no chartable number):

1. **Code** node "Build Quote Card HTML":

```javascript
function quoteCardHtml(item) {
  const emoji = {research:'🔬','product-launch':'🚀','open-source':'🛠️','industry-news':'📰',fun:'✨'}[item.category] || '💡';
  return `<div style="width:1080px;height:1080px;display:flex;flex-direction:column;
justify-content:center;padding:80px;background:linear-gradient(135deg,#0B0D14,#1A1035);
font-family:'Space Grotesk',sans-serif;color:#F5F5F7;">
  <div style="font-size:48px;margin-bottom:24px;">${emoji} ${item.source_org}</div>
  <div style="font-size:56px;font-weight:700;line-height:1.25;">${item.why_it_matters}</div>
</div>`;
}
return $input.all().map(i => ({
  json: { ...i.json, card_html: quoteCardHtml(i.json), media_type: 'quote_card' }
}));
```

2. Same **HTTP Request → Render → Download → Telegram Send Photo** chain as F2, but posting
   `{ "html": "={{ $json.card_html }}", "google_fonts": "Space Grotesk" }` to `hcti.io/v1/image`.

### F6. Consolidate

Update your B3f "Consolidate" Code node (original implementation guide) so the priority order is now:
`attached_gif` → `attached_video` → `quote_tweet_url` → `youtube_url` → `data_chart` (F4) → `quote_card`
(F5, guaranteed to exist). Confirm no item can exit this branch with `media_type` unset.

### F7. Build the recap card

Same template pattern as F5's quote card, but content is the numbered recap list instead of a single
quote — reuse the same HTML-card → hcti.io → Telegram chain, attached to tweet 10 (the recap tweet from
the v3 writing prompt).

### F8. Test

Run the full pipeline. Confirm in Telegram: every single tweet arrives with an attached image (or
GIF/video), nothing arrives as plain text. Check your htmlcsstoimage.com dashboard usage stays
comfortably under 50/month — if you're testing heavily during development, you'll burn through faster
than in steady weekly use; that's expected and fine, just don't run it dozens of times in one sitting.

---

# STAGE G — Native Interactivity

### G1. Poll instructions (no new account)

Already produced by the v3 curation prompt (`is_debate_worthy`) and writing prompt (the `poll` object).
Update your Telegram delivery Code node to check for a `poll` field on the parsed thread and, if
present, prepend a clearly marked line to that tweet's message:

```javascript
const pollNote = tweet.poll
  ? `📊 ADD A POLL to this tweet: "${tweet.poll.question}" — options: ${tweet.poll.options.join(' / ')}\n\n`
  : '';
```

### G2. Companion micro-page — GitHub setup (one-time)

1. Create a free GitHub account if you don't have one, and a new **public** repo (e.g.
   `weekly-ai-companion`).
2. Repo → **Settings → Pages** → Source: deploy from a branch → pick `main`, folder `/ (root)` → Save.
   Your pages will be live at `https://<your-username>.github.io/weekly-ai-companion/<filename>.html`.
3. Create a **fine-grained personal access token**: GitHub → Settings → Developer settings → Personal
   access tokens → Fine-grained tokens → scope it to **this one repo only**, permission: **Contents:
   Read and write**. Save the token somewhere safe (n8n credential, not hardcoded in a node).

### G3. Build the companion page

For the single top-scoring item each week (use whichever curated item has the highest combination of
`is_debate_worthy` or the largest `chart_candidates` numbers as your pick — simplest: just use the item
in tweet 2, since Pass 1's curation already orders by importance):

1. **Code** node "Build Companion Page HTML" — a small self-contained page, real interactivity via
   Chart.js loaded from CDN (not just a static QuickChart image this time, since the point here is
   genuine interactivity — hover tooltips, etc.):

```javascript
const item = $input.first().json;
const nums = item.chart_candidates || [];
const html = `<!DOCTYPE html><html><head><meta charset="utf-8">
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.0/chart.umd.min.js"></script>
<style>body{background:#0B0D14;color:#F5F5F7;font-family:sans-serif;max-width:700px;
margin:60px auto;padding:0 20px;} canvas{margin-top:30px;}</style></head>
<body>
<h1>${item.title}</h1>
<p>${item.why_it_matters}</p>
<canvas id="c" height="300"></canvas>
<p><a href="${item.url}" style="color:#7C3AED;">Original source →</a></p>
<script>
new Chart(document.getElementById('c'), {
  type: 'bar',
  data: { labels: ${JSON.stringify(nums.length ? nums : ['This week'])},
    datasets: [{ data: ${JSON.stringify(nums.length ? nums.map(n=>parseFloat(n.replace(/[^0-9.]/g,''))||0) : [1])},
    backgroundColor: '#7C3AED' }] },
  options: { plugins: { legend: { display: false } } }
});
</script>
</body></html>`;
const base64 = Buffer.from(html).toString('base64');
const filename = `week-${new Date().toISOString().slice(0,10)}.html`;
return [{ json: { base64, filename } }];
```

2. **HTTP Request** node "Publish Companion Page":
   - Method `PUT`
   - URL `=https://api.github.com/repos/<your-username>/weekly-ai-companion/contents/{{ $json.filename }}`
   - Headers: `Authorization: Bearer <your PAT>` (use an n8n credential), `Accept:
     application/vnd.github+json`
   - Body (JSON): `{ "message": "weekly companion page", "content": "={{ $json.base64 }}", "branch":
     "main" }`
3. The response includes the file's GitHub URL; the live page is at
   `https://<your-username>.github.io/weekly-ai-companion/{{ filename }}`. Build that URL in a Code
   node and pass it to Telegram delivery as: *"Reply to your own tweet 1 with: [that URL] — this is the
   deep-dive link, keeps it out of the main thread body."*

### G4. Test

Run once, open the resulting github.io URL in a browser, confirm the chart renders and is genuinely
interactive (hover shows a tooltip). Confirm the link works from a phone browser too, since you'll be
pasting it from Telegram on mobile.

---

# STAGE H — Optional: Animated Native Video (advanced, do last)

Turns one static branded asset per week into a short native MP4 using ffmpeg's `zoompan` filter — a
Ken-Burns-style slow zoom that makes a static PNG read as a short animated clip. Native video gets the
strongest distribution boost of any format (design doc Section 0), so this is worth it for your single
strongest asset — but it's the most infrastructure-heavy addition here, so keep it to one asset per
week and only build it once Stages E–G are solid.

### H1. Rebuild the Docker image with ffmpeg

Extend your Dockerfile (merge with the optional PyMuPDF one from the original guide's B3d if you built
that too):

```dockerfile
FROM docker.n8n.io/n8nio/n8n
USER root
RUN apk add --no-cache ffmpeg
USER node
```

Build and redeploy this image in place of the stock `docker.n8n.io/n8nio/n8n` image, same `docker run`
command as before otherwise (Stage A1/C3 in the original guide) — just point `docker run` at your new
local image tag instead of pulling the public one.

### H2. Write the PNG to disk

Add a **Read/Write File from Disk** node (Write mode) right after whichever card you're animating (the
cover card is the natural pick — it's the highest-visibility asset). Point it at, e.g.,
`/tmp/cover_card.png`, fed from the binary data downloaded in F2.

### H3. Run ffmpeg via Execute Command

Add an **Execute Command** node:

```bash
ffmpeg -y -loop 1 -i /tmp/cover_card.png -vf "zoompan=z='min(zoom+0.0015,1.15)':d=125:s=1080x1080:fps=25,format=yuv420p" -t 5 -movflags +faststart /tmp/cover_reveal.mp4
```

This produces a 5-second, slowly-zooming MP4 from the static card.

### H4. Read the MP4 back in and deliver as native video

Add a second **Read/Write File from Disk** node (Read mode) pointed at `/tmp/cover_reveal.mp4`, then
wire its binary output into a **Telegram** node — **Send Video** — instead of Send Photo for this one
asset. Caption = tweet 1's text, same as before.

### H5. Test

Run it, mind render time (a few seconds is normal on the Oracle free-tier VM's Ampere cores) and confirm
the resulting video plays correctly and looks intentional, not glitchy, before relying on it weekly.
Keep this to one asset per week — applying it to every card would meaningfully slow the whole run and
isn't necessary for the payoff.

---

## Quick reference: what changed vs. the original guide

- **Stage A–D**: unchanged, build these first if you haven't.
- **Stage E**: inserted between the diversity check and media enrichment (hook) and after "Parse
  Thread" (QA gate) — no new nodes needed elsewhere.
- **Stage F**: extends the existing media-enrichment branch (B3 in the original guide) with two new
  fallback tiers, and adds the cover/recap card generation as new parallel branches.
- **Stage G**: extends Telegram delivery (B6 in the original guide) with poll text and, optionally, a
  new companion-page publishing branch.
- **Stage H**: purely additive — one Docker rebuild, three new nodes, applied to a single asset.
