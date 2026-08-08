# Implementation Guide — Weekly AI/Tech X Thread Automation

Companion to `weekly-ai-tech-x-thread-automation-v2.md`. That file is the *design*; this file is the
*build checklist* — concrete accounts, exact commands, node-by-node n8n instructions, in the order to
do them. Follow it top to bottom. Only this v2 file existed in the folder (no v1), so wherever v2 said
"see v1 for endpoints," this guide fills that in directly with real, verified endpoints.

> ⚠️ **Build this on a personal machine/network/accounts, not a work one.** While researching this
> guide I tested a few of the URLs this workflow needs (an OpenAI blog feed, the Gemini API) from this
> environment, and at least one request was intercepted by what looks like your organization's
> (Electrolux) web security gateway, tagged under a "Generative AI and ML Applications" category. A
> personal social-media automation project calling third-party AI/scraping APIs on a corporate network
> or device risks both technical blocks and acceptable-use policy issues. Do the whole build — Docker,
> n8n, Oracle Cloud account, Gemini key, Telegram bot — with your **personal** Google/Microsoft/Oracle
> accounts, on your **home network**. Everything below assumes that.

## How this guide is organized

Building all 13 moving pieces from the v2 doc at once and testing nothing until the end is a recipe for
a stuck afternoon. Instead, build in **4 stages**, each one a working checkpoint:

| Stage | What you get at the end of it |
|---|---|
| **A — Minimum Viable Thread** | A real (if plain) weekly thread draft landing in your Telegram, built from 2 sources, no media, no diversity enforcement. Proves the whole pipe works. |
| **B — Full-featured version** | Matches the v2 doc exactly: all sources, diversity enforcement, media enrichment, media-aware writing, format checks. |
| **C — Go live** | Scheduled trigger, running unattended 24/7 on a free cloud VM instead of your laptop. |
| **D — Optional polish** | The "extra ideas" from v2 Section 9 — nice-to-haves, not required. |

Do not skip to Stage B before Stage A works end to end. It's much easier to debug one source and one
prompt than seven sources and a broken pipeline simultaneously.

---

# STAGE A — Minimum Viable Thread

### A0. Accounts needed for this stage only

- [ ] **Google AI Studio account** (personal Google account) → get a free Gemini API key.
      Go to https://aistudio.google.com → "Get API key" → "Create API key". Copy it somewhere safe.
      Note the current free-tier model name shown in the model picker (something like
      `gemini-flash-latest` or a specific version string) — you'll need the exact model ID string for
      the API URL later. Free tier has no cost, just rate limits (requests/minute, tokens/minute,
      requests/day) that reset daily — comfortably enough for one curation call + one writing call per
      week.
- [ ] **Telegram bot**:
  1. In Telegram, message **@BotFather** → send `/newbot` → follow prompts (name + username) → it
     replies with a **bot token** like `123456789:AAExxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`. Save it.
  2. Send your new bot **any message** (search its username, hit Start, type "hi").
  3. In a browser, open:
     `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
     Find `"chat":{"id":123456789, ...}` in the JSON reply — that number is your **chat_id**. Save it.

### A1. Install Docker Desktop and run n8n locally

1. Install **Docker Desktop for Windows** (enable the WSL2 backend when prompted):
   https://docs.docker.com/get-docker/
2. Open PowerShell and run:

```powershell
docker volume create n8n_data

docker run -d `
  --name n8n `
  --restart unless-stopped `
  -p 5678:5678 `
  -e GENERIC_TIMEZONE="Asia/Kolkata" `
  -e TZ="Asia/Kolkata" `
  -e N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true `
  -v n8n_data:/home/node/.n8n `
  docker.n8n.io/n8nio/n8n
```

   (Adjust the timezone string if `Asia/Kolkata` isn't right for you — this controls when your
   Schedule Trigger actually fires later.) This runs n8n in the background and auto-restarts it if
   Docker Desktop restarts. Useful commands later: `docker logs -f n8n`, `docker stop n8n`,
   `docker start n8n`.
3. Open **http://localhost:5678** in a browser → create your local owner account (email/password,
   stored only in your local container — not shared with anyone).

### A2. Create the workflow shell

1. New workflow → name it `Weekly AI Tech X Thread`.
2. Add a **Manual Trigger** node (you'll add the real Schedule Trigger in Stage C — building against a
   Manual Trigger lets you click "Execute workflow" repeatedly while you iterate).
3. Save the workflow now, and re-save (Ctrl+S) after every few nodes.

### A3. Normalize schema — decide this now, use it everywhere

Every source branch, no matter how different its raw API response looks, should output items shaped
exactly like this. Getting this consistent is what makes the Merge/Dedupe/Filter/Curate steps work
cleanly:

```js
{
  title: "string",
  url: "string",
  summary: "string",          // abstract / excerpt / description
  published_at: "ISO date string",
  source_org: "OpenAI | Google | Anthropic | Meta | Microsoft | NVIDIA | independent | open-source | ...",
  category: "research | product-launch | open-source | industry-news | fun",
  origin: "arxiv | hn | rss | reddit | github-trending | producthunt | hf-papers"
}
```

### A4. Build two source branches (easiest two first)

**Branch 1 — Hacker News (Algolia API, no auth, verified working):**

1. **HTTP Request** node — GET:
   `https://hn.algolia.com/api/v1/search_by_date?tags=story&query=AI&hitsPerPage=30`
   (swap `query=AI` for other runs, or drop it and rely on tags only). Response shape (confirmed):
   `{ hits: [ { title, url, created_at, objectID, points, author, ... } ] }`.
2. **Code** node "Tag HN" right after it:

```javascript
const hits = $input.first().json.hits;
return hits
  .filter(h => h.url) // skip Ask HN / self posts with no external link
  .map(h => ({
    json: {
      title: h.title,
      url: h.url,
      summary: '',
      published_at: h.created_at,
      source_org: 'independent',
      category: 'industry-news',
      origin: 'hn'
    }
  }));
```

**Branch 2 — arXiv (via n8n's built-in RSS Feed Read node — arXiv's API is valid Atom XML, the RSS
node parses it fine):**

1. **RSS Feed Read** node — Feed URL:
   `http://export.arxiv.org/api/query?search_query=cat:cs.AI+OR+cat:cs.CL+OR+cat:cs.LG&sortBy=submittedDate&sortOrder=descending&max_results=30`
2. Execute it once and look at the output fields (should include `title`, `link`, `pubDate`/`isoDate`,
   `content`/`contentSnippet`, `guid`) — exact field names can vary slightly by n8n version, so confirm
   before wiring the next node.
3. **Code** node "Tag arXiv":

```javascript
const items = $input.all().map(i => i.json);
return items.map(e => ({
  json: {
    title: (e.title || '').replace(/\s+/g, ' ').trim(),
    url: e.link || e.guid,
    summary: (e.contentSnippet || e.content || '').replace(/\s+/g, ' ').trim(),
    published_at: e.isoDate || e.pubDate,
    source_org: 'independent',
    category: 'research',
    origin: 'arxiv'
  }
}));
```

### A5. Merge → Dedupe → Filter to last 7 days

1. **Merge** node: connect both "Tag" nodes into it. Set "Number of Inputs" to 2, mode **Append**.
2. **Code** node "Dedupe" right after:

```javascript
const items = $input.all().map(i => i.json);
const seen = new Set();
const out = [];
for (const item of items) {
  const key = (item.url || '').split('?')[0].replace(/\/$/, '').toLowerCase();
  if (!key || seen.has(key)) continue;
  seen.add(key);
  out.push(item);
}
return out.map(i => ({ json: i }));
```

3. **Filter** node "Filtered Candidates" (name it exactly this — later nodes reference it by name):
   condition `{{ new Date($json.published_at) >= $now.minus({ days: 7 }).toJSDate() }}` is `true`.

### A6. Curate — Gemini Pass 1

1. **Code** node "Build Curation Prompt" — turns the filtered pool into the `{{items}}` block and
   assembles the full prompt text as a single string (use the Section 6 curation prompt from the v2
   doc verbatim — include the diversity instructions from day one, it costs nothing to include even
   before you add the hard-enforcement Code node in Stage B):

```javascript
const items = $input.all().map(i => i.json);
const prompt = `You are curating content for a weekly tech & AI thread on X, aimed at an
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
- Do not invent details not present in the data below.

Return ONLY a JSON array: [{ "title", "url", "source_org", "category", "why_it_matters" }]

CANDIDATE ITEMS:
${JSON.stringify(items)}`;
return [{ json: { prompt } }];
```

2. **HTTP Request** node "Gemini Curate":
   - Method: `POST`
   - URL: `https://generativelanguage.googleapis.com/v1beta/models/<MODEL_ID>:generateContent?key=<YOUR_GEMINI_KEY>`
     (put the key in an n8n **credential**/expression, not hardcoded, once you're comfortable — for
     now getting it working matters more than perfect secret hygiene on your own local instance)
   - Body (JSON):
     ```json
     {
       "contents": [ { "parts": [ { "text": "={{ $json.prompt }}" } ] } ],
       "generationConfig": { "responseMimeType": "application/json" }
     }
     ```
   - `responseMimeType: "application/json"` forces Gemini to return valid JSON text — much more
     reliable than hoping the model doesn't wrap it in markdown fences.
3. **Code** node "Parse Curated":

```javascript
const text = $input.first().json.candidates[0].content.parts[0].text;
const picked = JSON.parse(text);
return picked.map(i => ({ json: i }));
```

### A7. Write — Gemini Pass 2 (simplified, no media yet)

1. **Code** node "Build Writing Prompt":

```javascript
const items = $input.all().map(i => i.json);
const prompt = `Using ONLY the items below, write a 10-post X thread for a technically
literate audience.

- Tweet 1: hook only, no link. Under 270 characters.
- Tweets 2-9: one item each. Put the link as the LAST line of the tweet,
  after the substantive point. Under 275 characters before the link.
- Tweet 10: short wrap-up + a question inviting replies.

Return ONLY a JSON array: [{ "tweet_number": 1, "text": "..." }, ...]

ITEMS:
${JSON.stringify(items)}`;
return [{ json: { prompt } }];
```

2. **HTTP Request** node "Gemini Write" — same setup as A6's Gemini node, pointed at this prompt.
3. **Code** node "Parse Thread" — same pattern as "Parse Curated" above, output an array of
   `{ tweet_number, text }`.

### A8. Basic format check

**Code** node "Format Check" — flag (don't silently fix) anything over the limit so you notice it in
testing:

```javascript
const tweets = $input.all().map(i => i.json);
return tweets.map(t => {
  const limit = t.tweet_number === 1 ? 270 : 275;
  return { json: { ...t, over_limit: t.text.length > limit, char_count: t.text.length } };
});
```

### A9. Telegram delivery (text only)

1. In n8n: **Credentials → New → Telegram API** → paste your bot token.
2. **Code** node "Build Full Thread Text" (combine into one message so you have a single copy-paste
   reference, ahead of Stage B's per-tweet media sends):

```javascript
const tweets = $input.all().map(i => i.json).sort((a,b) => a.tweet_number - b.tweet_number);
const full = tweets.map(t => `${t.tweet_number}/10:\n${t.text}`).join('\n\n---\n\n');
return [{ json: { full } }];
```

3. **Telegram** node — Operation: **Send Message** → Chat ID: your saved chat_id → Text:
   `={{ $json.full }}`.

### A10. Test it

Click **Execute workflow** on the Manual Trigger. Fix errors node by node (n8n shows the exact error
and the exact input each node received — read both before guessing). Iterate on prompt wording until
the thread reads naturally. **Milestone: a real weekly-thread draft lands in your Telegram.** Everything
in Stage B is additive from here.

---

# STAGE B — Full-featured version (matches the v2 doc)

### B1. Add the remaining source branches

Add these the same way as A4 (HTTP/RSS node → Code node "Tag X" → same normalized schema → feed into
the Merge node, which you'll need to grow to "Number of Inputs" = total branch count):

- **Hugging Face Daily Papers** (JSON, no auth, verified working) — **HTTP Request** GET
  `https://huggingface.co/api/daily_papers`. Each element is `{ paper: { id, title, summary,
  publishedAt, mediaUrls: [...] } }`. Note `mediaUrls` — HF often already has images attached; useful
  later in B3.
  ```javascript
  const items = $input.first().json;
  return items.map(x => ({
    json: {
      title: x.paper.title,
      url: `https://huggingface.co/papers/${x.paper.id}`,
      summary: x.paper.summary,
      published_at: x.paper.publishedAt,
      source_org: 'independent',
      category: 'research',
      origin: 'hf-papers',
      media_urls: x.paper.mediaUrls || []
    }
  }));
  ```
- **AI lab blogs + tech news RSS** — one **RSS Feed Read** node per feed (simplest to debug). Try:
  `https://techcrunch.com/feed/` (verified working), plus your pick of lab/news blogs — RSS paths on
  company blogs change occasionally, so open each URL in a browser first and confirm it renders XML
  before wiring it into n8n. A `source_org` guess based on domain works fine in the tagging Code node
  (e.g. `techcrunch.com` → `independent`, a lab's own blog → that lab's name).
- **Reddit** — same RSS Feed Read node, e.g. `https://www.reddit.com/r/MachineLearning/.rss`,
  `https://www.reddit.com/r/singularity/.rss`. No auth needed.
- **GitHub Trending** — no official API, so: **HTTP Request** GET `https://github.com/trending?since=weekly`
  → **HTML Extract** node with CSS selector `article.Box-row` for each repo card, then sub-selectors for
  the repo name link and description inside it. GitHub's markup can shift — if the selector returns
  nothing, open the page, "View Source", and find the current repeating container class.
- **Product Hunt** (optional, add last — most setup friction for the least AI-specific content): create
  a free dev token at https://www.producthunt.com/v2/oauth/applications, then **HTTP Request** POST to
  `https://api.producthunt.com/v2/api/graphql` with header `Authorization: Bearer <token>` and a
  GraphQL query for `posts(postedAfter: ...)`.

Update the tagging Code node for each branch to set a real `source_org` via keyword/domain match (per
v2 Section 2's suggestion), e.g.:

```javascript
function guessOrg(text) {
  const t = text.toLowerCase();
  if (t.includes('openai')) return 'OpenAI';
  if (t.includes('google') || t.includes('deepmind')) return 'Google';
  if (t.includes('anthropic') || t.includes('claude')) return 'Anthropic';
  if (t.includes('meta') || t.includes('llama')) return 'Meta';
  if (t.includes('microsoft')) return 'Microsoft';
  if (t.includes('nvidia')) return 'NVIDIA';
  return 'independent';
}
```

### B2. Add the diversity-enforcement Code node

Insert this **after** "Parse Curated" (A6), reading from the "Filtered Candidates" node (A5) by name —
this is the exact code from v2 doc Section 3:

```javascript
const picked = $input.all().map(i => i.json);
const pool = $('Filtered Candidates').all().map(i => i.json);

const counts = {};
const kept = [];
const overflow = [];

for (const item of picked) {
  const org = item.source_org || 'independent';
  counts[org] = (counts[org] || 0) + 1;
  if (counts[org] <= 2) kept.push(item);
  else overflow.push(item);
}

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

(If you renamed the filter node from A5 to something other than "Filtered Candidates", update the
`$('...')` reference to match.)

### B3. Media enrichment — build incrementally, in this order

Add a parallel branch after diversity-check that runs per curated item (n8n auto-loops Code/HTTP nodes
over each input item).

**B3a. GitHub README GIF (start here — simplest, highest hit rate for research items):**

```javascript
// Step 1: find a non-arxiv link in the abstract (Code node)
const items = $input.all().map(i => i.json);
return items.map(item => {
  const urlRegex = /https?:\/\/[^\s)]+/g;
  const links = ((item.summary || '').match(urlRegex) || []).filter(l => !l.includes('arxiv.org'));
  return { json: { ...item, extra_links: links } };
});
```
Then, for items with a `github.com` link in `extra_links`: **HTTP Request** GET the raw README
(`https://raw.githubusercontent.com/<owner>/<repo>/main/README.md` — try `main` then `master` if 404),
then a **Code** node:
```javascript
const mediaRegex = /!\[[^\]]*\]\(([^)]+\.(gif|png|jpe?g))\)|(https?:\/\/\S+\.mp4)/gi;
// match against the README text, take the first hit as media_hint
```

**B3b. Project-page Open Graph fallback:** for items whose `extra_links` has a non-GitHub URL, **HTTP
Request** GET the page, then **HTML Extract** node with CSS selectors
`meta[property="og:video"]` / `meta[property="og:image"]` (extract the `content` attribute).

**B3c. YouTube uploads lookup** (for company/product items):
1. Get a free **YouTube Data API v3 key**: Google Cloud Console → APIs & Services → enable "YouTube
   Data API v3" → Credentials → API key.
2. Resolve each lab's channel ID once (don't hardcode guessed IDs — resolve them yourself so they're
   correct): `GET https://www.googleapis.com/youtube/v3/channels?part=id&forHandle=<Handle>&key=<KEY>`
   using the channel's `@handle` from its YouTube URL. Store the resulting IDs in a **Set** node as your
   config (6–8 labs you care about, one-time setup).
3. Pull recent uploads cheaply: `GET https://www.googleapis.com/youtube/v3/channels?part=contentDetails&id=<CHANNEL_ID>&key=<KEY>`
   → read `items[0].contentDetails.relatedPlaylists.uploads` → then
   `GET https://www.googleapis.com/youtube/v3/playlistItems?part=snippet&playlistId=<UPLOADS_PLAYLIST_ID>&maxResults=10&key=<KEY>`
   (1 unit/call — cheap, 10,000 free units/day). Keyword-match titles against the week's item locally.

**B3d. PDF Figure-1 extraction (optional/advanced — do last):** n8n's Code node is JS-only, so this
needs either (a) a custom Docker image with Python + PyMuPDF and n8n's **Execute Command** node calling
a small script, or (b) skip this one — B3a/B3b/B3c already cover most cases, and this is the lowest
value-per-effort item in the whole doc. If you do want it, extend the Dockerfile:
```dockerfile
FROM docker.n8n.io/n8nio/n8n
USER root
RUN apk add --no-cache python3 py3-pip && pip install --break-system-packages pymupdf
USER node
```

**B3e. Quote-tweet URL search fallback** (company announcements, v2 Section 4b option 1): free
Google Programmable Search Engine (https://programmablesearchengine.google.com, 100 free queries/day)
→ **HTTP Request** GET `https://www.googleapis.com/customsearch/v1?key=<KEY>&cx=<CX_ID>&q=site:x.com+<company>+<product>`.

**B3f. Consolidate:** final **Code** node that maps whatever B3a–B3e found into the exact fields the
Pass-2 prompt expects: `media_type` (`attached_gif` / `attached_video` / `quote_tweet_url` /
`youtube_url` / `none`) and `media_hint`.

### B4. Upgrade Pass 2 to the full media-aware prompt

Swap A7's simplified prompt for the v2 doc's Section 6 "Thread-writing prompt (Pass 2)" verbatim
(it's the one with the `media_type` branching logic) — no code changes needed beyond feeding it the
now-richer item objects from B3f.

### B5. Upgrade the format-check node

Add the link-placement check from v2 Section 5: flag any tweet whose `media_type` is
`attached_gif`/`attached_video` but still contains a URL in the text (the writing prompt shouldn't do
this, but verify it programmatically rather than trusting the model every week).

### B6. Upgrade Telegram delivery to send real media

1. Replace the single "Build Full Thread Text" send with a **Split in Batches** (loop) over the parsed
   tweets.
2. Per tweet, branch on `media_type`:
   - `attached_gif`/`attached_video`: **HTTP Request** node downloading the media URL with **Response
     Format: File** (binary), then a **Telegram** node — **Send Photo**/**Send Video** — using that
     binary data, caption = tweet text.
   - `quote_tweet_url`: **Telegram Send Message** with the tweet text + the URL on its own line (you'll
     paste that URL into X's compose box to trigger the native quote-tweet).
   - `youtube_url`/`none`: **Telegram Send Message**, plain text (link already in the text from the
     writing prompt).
3. Telegram's Bot API caps file sends at ~50MB — fine for any GIF/short clip this workflow finds.

---

# STAGE C — Go live (unattended, 24/7)

Local Docker Desktop only runs while your laptop is on — fine for building, not for a weekly 6pm
Sunday trigger. Move to an always-on free VM.

### C1. Add the real Schedule Trigger

Add a **Schedule Trigger** node (leave the Manual Trigger in place too — you can still test manually
any time). Configure: **Weeks** → interval 1 → trigger day **Sunday** → time **18:00** (matches v2's
"Sunday evening/Monday morning" recommendation, and your container's `GENERIC_TIMEZONE` from A1).

### C2. Create your Oracle Cloud Always Free VM

1. Sign up at https://www.oracle.com/cloud/free/ with a **personal** email (card required for identity
   verification only — Always Free resources are never charged).
2. Create a Compute instance: shape **VM.Standard.A1.Flex (Ampere, Always Free-eligible)**, 2 OCPU /
   12GB RAM is plenty (leaves headroom under the 4 OCPU/24GB Always-Free ceiling for anything else
   later). Image: Ubuntu (latest LTS). Generate/download the SSH key pair when prompted.
3. **This workflow has no incoming webhook** — it's purely Schedule Trigger-driven, calling *out* to
   APIs. That means you do **not** need to open port 80/443, buy a domain, or set up a reverse
   proxy/HTTPS at all. Skip all of that. You only need SSH (port 22, open by default).

### C3. Install Docker on the VM and run n8n

SSH in (`ssh -i <your-key>.pem ubuntu@<vm-public-ip>`), then:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
exec sg docker newgrp

docker volume create n8n_data
docker run -d \
  --name n8n \
  --restart unless-stopped \
  -p 127.0.0.1:5678:5678 \
  -e GENERIC_TIMEZONE="Asia/Kolkata" \
  -e TZ="Asia/Kolkata" \
  -e N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true \
  -v n8n_data:/home/node/.n8n \
  docker.n8n.io/n8nio/n8n
```

Note `-p 127.0.0.1:5678:5678` — this binds n8n only to localhost on the VM, i.e. **not** exposed to the
public internet at all. You'll reach it via an SSH tunnel (next step), which is more secure than
opening the port publicly and is enough since you only need occasional access, not 24/7 UI availability.

### C4. Access the remote n8n UI securely (SSH tunnel, no public port needed)

From your Windows machine:

```powershell
ssh -i <your-key>.pem -L 5678:localhost:5678 ubuntu@<vm-public-ip>
```

Leave that running, then open **http://localhost:5678** in your browser — you're now looking at the
VM's n8n instance through the tunnel.

### C5. Move the workflow over

1. On your local instance: workflow menu → **Download** (exports JSON).
2. On the VM instance (via the tunnel): **Import from File** → pick that JSON.
3. **Re-enter credentials on the server** — the Gemini API key/URL and the Telegram credential don't
   travel with a plain JSON export for security reasons. Recreate them once on this instance.
4. Re-run via the Manual Trigger to confirm it still works from the server.

### C6. Activate

Toggle the workflow **Active** (top right). Confirm in the **Executions** tab after the next Sunday
18:00 passes that it actually ran and Telegram got the message. From here: **Sunday 6pm the workflow
fires → Monday morning you get a Telegram message → 60-second glance/edit → paste into X → spend
10–15 minutes in the first hour replying to comments** (v2 Section 9 — the single strongest lever
regardless of anything else in this pipeline).

---

# STAGE D — Optional polish (v2 Section 9, do only once A–C are solid)

- [ ] Consistent per-category emoji (🔬 research, 🚀 launch, 🛠️ open-source, ✨ fun) in the writing prompt.
- [ ] Ask the writing prompt to also generate one-line alt-text per attached image/GIF.
- [ ] Log each week's picks (append to a simple CSV/Google Sheet via an extra node) — enables both the
      feedback loop and quarterly best-of ideas below without extra future work.
- [ ] After a month, skim your own X analytics for which categories/items got the most
      replies/bookmarks, and fold that back into the curation prompt's priorities.
- [ ] Every ~12 weeks: a second, simple workflow that reads your logged picks and compiles the single
      highest-engagement item from each week into a "best of the quarter" thread.

---

## Troubleshooting quick-reference

- **n8n expression errors**: click the node, check the "Input" pane for the exact shape it received —
  don't guess field names, read them.
- **Merge node only shows 2 inputs**: increase "Number of Inputs" in its parameters panel to match
  however many source branches feed into it.
- **Gemini 429 errors**: you've hit the free-tier rate limit (requests/minute or requests/day) — this
  workflow only needs 2 calls/week, so this should only happen while you're rapidly re-testing during
  development; wait a minute and retry.
- **RSS feed 404s or empty**: blog RSS paths change; open the URL directly in a browser first.
- **GitHub Trending selector returns nothing**: GitHub changed its markup — view source on
  github.com/trending and find the current repeating container class.
- **Telegram "chat not found"**: you must message your bot at least once before `getUpdates` will show
  a chat_id for it.
- **Scheduled run never fires**: confirm the workflow is toggled **Active**, and that
  `GENERIC_TIMEZONE`/`TZ` match what you assumed when picking the trigger time.
