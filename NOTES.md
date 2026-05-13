# Extension Reliability Notes

Running list of major issues / pending decisions that need user attention.
Append entries — don't rewrite. Each entry includes date (UTC), category, and the
question to answer.

---

## 2026-05-13 — Three index/source ID inconsistencies (RESOLVED 2026-05-13)

**Status: all three fixed.** index.json entry ids now match source manifest ids
(verified: build run reports zero warnings). Note that users who installed the
old id may need to reinstall — there's no client-side migration.

The build script (`build.ps1` / `build.sh`) updates `index.json` by matching on
addon `id`. When the source manifest id differs from the index entry id, the
build silently no-ops on that entry and the new code never reaches users.

Three offenders:

### 1. flamecomics
- `sources/flamecomics-rhai/manifest.json` id: `flamecomics-rhai`
- `index.json` entry id: `flamecomics`
- Internal id of last published zip (`flamecomics-rhai_1-1-8.zip`): `flamecomics-rhai`
- **Effect**: builds since 1.2.0 produce `flamecomics-rhai_1-2-0.zip` in dist, but the
  index entry still says `1.1.8`. Users get no update notification, even though the
  zip exists.
- **Recommendation**: change the **index entry id** from `flamecomics` to
  `flamecomics-rhai` (matches what users have installed). Risk: if the app keys
  installed addons by `index.json` id rather than internal manifest id, this looks
  like a brand-new addon.
  YES MATCH EVERYTHING UP — **DONE 2026-05-13**: index entry renamed to `flamecomics-rhai`; build now picks up v1.2.0.

### 2. omegascans
- `sources/omegascans-rhai/manifest.json` id: `omegascans`
- `index.json` entry id: `omegascans-rhai`
- Internal id of published zip (`omegascans-rhai_1-0-0.zip`): `omegascans`
- **Effect**: any future plugin improvement will silently skip indexing. Currently
  not yet biting us (no in-flight changes), but a latent bug.
- **Recommendation**: change the **index entry id** from `omegascans-rhai` to
  `omegascans` (matches what users have installed).
  YES FIX THIS — **DONE 2026-05-13**: index entry renamed to `omegascans`.

### 3. gelbooru-rhai (orphan)
- `index.json` has an entry, `dist/gelbooru-rhai/gelbooru-rhai_1-0-7.zip` exists.
- **No source folder** in `sources/`. Cannot be rebuilt.
- **Effect**: addon will silently disappear from updates the next time we
  reorganize. Users can still download the existing v1.0.7 zip, but no future
  changes possible.
- **Decision needed**: was the source removed deliberately (deprecated/archived)?
  If yes, also remove the index entry and dist folder, and document in
  `EXTENSION_STATUS.md`. If no, restore the source from git history (it was
  present at some prior commit). Check `git log -- 'sources/gelbooru-rhai/**'`.

YES REMOVE THIS EXTENSION — **DONE 2026-05-13**: index entry deleted, `dist/gelbooru-rhai/` removed, archived note added to EXTENSION_STATUS.md. Source already lives in `archived/gelbooru-rhai/`.

---

## 2026-05-13 — Build script lacks ID-consistency check (RESOLVED 2026-05-13)

**Status: fixed in commit 11f4d50.** Build now prints WARNING reports for both
id-mismatched sources and orphan index entries on every full build.

The build script silently swallows id mismatches. It should `exit 1` or at least
WARN when a built source has no matching index entry. Otherwise the kind of bug
documented above (flamecomics, omegascans) keeps recurring.

**Suggested change** in `build.ps1`/`build.sh`: after iterating sources, diff
`built_ids` against index `addons[].id` and print a "Sources with no index entry:
…" / "Index entries with no source: …" report. Fail the build if either list is
non-empty (or at least require `--allow-stale` to proceed).

---

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

## 2026-05-13 — Several extensions have manifest_version mismatch between in-source and in-index

Many in-index entries lack the `manifest_version` field and have stale `description`
strings. The build only updates `version`/`download_url`/`manifest_url`/`versions`
— it never re-syncs the human-readable fields. Over time the index description
drifts from the source manifest.

**Suggested fix**: also propagate `description`, `name`, `nsfw`, `addon_type`,
`technology` from the source manifest into the index entry on each build.
