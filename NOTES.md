# Extension Reliability Notes

Running list of major issues / pending decisions that need user attention.
Open items at the top — resolved items live in a log at the bottom for
traceability.

---

# OPEN

## 2026-05-13 — `EXTENSION_STATUS.md` is stale (last tested 2026-01-24)

Roughly 4 months old. The "Working scrapers" table needs a fresh smoke test —
several sources change selectors or move domains on the order of weeks. Don't
trust the numbers in that file when triaging issues.

**Decision needed**: do we want to regenerate this file automatically via a
script that hits each source's `/search` and `/browse` endpoints? Manual upkeep
isn't keeping pace.

---

## 2026-05-13 — Comick BASE_URL may be stale

`sources/comick-rhai/plugin.rhai` line 21: `const BASE_URL = "https://comick.art";`

External signals:
- `api.comick.io` returns `301 → comick.dev`
- `comick.dev` returns `403 Forbidden` to non-browser User-Agents

The plugin's `${BASE_URL}/api/comics/${hid}` enrichment may currently be hitting
a stale host. Worth verifying inside the scraper container (rquest Chrome131
impersonation may still work where plain HTTPS doesn't).

**Action**: confirm with a real scraper run whether the BASE_URL still works.
If not, update to whichever host serves the API today. Don't change blind — the
plugin's behavior under the actual TLS-impersonated client may differ from a
browser request.

---

## 2026-05-13 — New-source survey (round 1)

Probed for gaps in our 53-source catalog. **Don't speculatively add scaffolds**
— each new source needs site-availability verification (which I can't do from
this sandbox: WebFetch paraphrases responses and there's no scraper container
to spin up rquest+CF impersonation).

### Candidate sites checked
- **reaperscans.com**: 502 Bad Gateway. *Already covered* by `heancms-rhai`
  with user-configurable `base_url` — no new addon needed; just document this
  in `heancms-rhai` README.
- **templescan.net**: 403 (CF challenge). Live but browser/FlareSolverr only.
  *Not yet covered.* Worth adding when scraper container access is available.
- **zeroscans.com → zscans.com**: domain moved per site banner. *Not yet
  covered.* Likely HeanCMS or custom — needs investigation.

### Already-covered "popular" sources (via framework adapters)
- ReaperScans / QuantumScans / LuminousScans / OmegaScans / FlameComics:
  all routed through `heancms-rhai` (set `base_url` in settings).
- Generic Madara sites: route through `toonily-rhai`, `manhwaclan-rhai`,
  `manhuaplus-rhai`, `manhuafast-rhai` (each is preconfigured for one Madara
  domain). A *generic* "Madara" addon with configurable base_url would
  consolidate these — current pattern duplicates ~1000 lines per addon.

### Survey approach didn't work
Tried fetching `keiyoushi/extensions-source` directory listing via WebFetch.
The model summarizing the response **hallucinated several hundred fake folder
names** (e.g. cascading "manascanoriginal{1..40}" entries that don't exist).
Anything that needs raw lists rather than prose summaries should use the gh
CLI (`gh api repos/keiyoushi/extensions-source/contents/src/en --paginate`)
from a session that has gh auth — not WebFetch.

### Decision needed
Pick one of:
1. **Add a generic Madara framework addon** (configurable base_url) so common
   Madara sites can be supported without N copies. Drops ~5000 LOC.
2. **Add specific scaffolds** for: templescan-rhai, zscans-rhai (defer until
   we can verify in a scraper container).
3. **Status quo**: heancms covers the framework-aware sites; Madara stays
   per-site. Defer net-new sources entirely until user requests one.

---

## 2026-05-14 — 8 plugins still call HTTP unwrapped (defense-in-depth todo)

Grep `for f in sources/*/plugin.rhai; do … grep -c "http_get_with_headers"` finds
these plugins calling `http_get_with_headers` / `http_get_plain` directly with
zero try/catch wrapping:

- `webtoon-rhai` — 14 call sites (highest impact)
- `dynastyscans-rhai` — 7
- `mangasee-rhai` — 7
- `mangatown-rhai` — 2
- `roliascan-rhai` — 2
- `violetscans-rhai` — 2
- `weebcentral-rhai` — 2
- `rule34-rhai` — 1

Each unwrapped call lets a transient network exception (TLS retry, dropped
connection, intermediate proxy 5xx) propagate up to the caller and crash the
whole search / browse / chapter fetch instead of falling through to an empty
result. Same class of bug fixed in `hivetoons-rhai v1.0.1` (commit 8cd5c2c)
and `asurascans-rhai v1.9.1` (commit f0fc474).

**Recommendation**: add a tiny `api_get` helper at the top of each plugin and
route the calls through it (the same pattern used by toonily-rhai and the
hivetoons fix). Low-risk per-plugin but high-touch across 8 sources — defer
until you want a focused reliability sweep.

---

# RESOLVED LOG

## 2026-05-13 — Three index/source ID inconsistencies → fixed in `8c9d1f2`

- `flamecomics`: index entry id renamed to `flamecomics-rhai` to match source
  manifest + every published zip; index now reflects v1.2.0 (was pinned to
  1.1.8 because the build silently no-op'd on id mismatch).
- `omegascans-rhai`: index entry id renamed to `omegascans`.
- `gelbooru-rhai`: orphan removed (`index.json` entry deleted,
  `dist/gelbooru-rhai/` deleted, archived note added to `EXTENSION_STATUS.md`).
  Source lives in `archived/gelbooru-rhai/`.

Note: users who installed under an old id may need to reinstall — no
client-side rename migration.

## 2026-05-13 — Build script lacks ID-consistency check → fixed in `11f4d50`

Build now prints prominent WARNINGs for (a) sources built but not matched to
any index entry by id, (b) index entries with no source folder. Orphan check
is gated to full-build mode so `-Single` runs don't fire false positives.
Empty-bump and `released_at` churn fixes shipped alongside.

## 2026-05-13 — Index drift on description/name/nsfw → fixed in `997fe55`

Build now propagates `name`, `description`, `addon_type`, `technology`,
`nsfw` from source manifest into the index entry on every build. Empty
values preserve the index's prior value (won't accidentally clear a field).
Caught 6 stale entries on first run.
