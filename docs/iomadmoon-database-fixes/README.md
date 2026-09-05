# theme_iomadmoon: database-only fixes

Runbook for the IOMAD Moon theme (`theme_iomadmoon`) problems diagnosed on
2026-09-04 on the site at `/var/www/html/moodle` (database `iomad`, table
prefix `mdl_`), under the rule **no installs, no CSS/JS/PHP changes, database
changes only**. Everything here is either a `SELECT`, an `UPDATE` of settings
rows Moodle itself writes through its admin forms, or a run of a CLI script
that ships with Moodle.

## 1. What the diagnostics established

| Symptom | Cause found | Database involvement |
|---|---|---|
| Console warning `SpaceTheme already initialized` | `theme/iomadmoon/amd/src/rui.js` calls `SpaceTheme.init()` itself on document-ready (line 1553), and all 12 layout files call `js_call_amd('theme_iomadmoon/rui', 'init')` again. The second call hits the guard and logs. | None. No injected script in `additionalhtml*`, `additionalheadscripts` or `googleanalytics` (all 0 bytes) and no config row references the loader. |
| `amd/src/rui.js` (2026-09-04) newer than `amd/build/rui.min.js` (2026-09-01), different SHA-256 | Build was not regenerated after the source edit. | `cachejs = 1` means the stale build is what browsers get. |
| Console error `TypeError: Cannot read properties of null (reading 'classList') at moveIntoMoreDropdown (core/first.js:94:2028)` | The null is `dropdownToggle`, not the nav link (every `<li>` has a `.nav-link`, the served bundle already guards `navLink`, and column 2028 is `dropdownToggle.classList`). Core `moremenu.js` finds the "More" toggle with `[data-toggle="dropdown"]`; the theme's `amd/src/bs4-compat.js` has already renamed that attribute to `data-bs-toggle`. It throws the moment an *active* item overflows into "More". | No theme or core setting causes it. Fix: script 06 stores a block in `mdl_config.additionalhtmlfooter` (Site administration > Appearance > Additional HTML) that restores `data-toggle="dropdown"` on More-menu toggles. Custom menu items are not involved. |
| Fonts | `fontbody = 'Poppins', sans-serif`, weights 400/500/700, `googlefonturl` loads exactly those weights. `fontheadings` is empty, so the SCSS default applies. No font-size setting exists in the database (`$font-size-base: 1rem` is SCSS). | Consistent. Only `fontheadings` is optionally settable. |
| Caches | `jsrev = themerev = 1788497399` (2026-09-04 04:36 UTC), i.e. purged after the source edit. | Fine. |

## 2. What the database cannot do

* It cannot remove the `SpaceTheme already initialized` warning. Removing it
  needs either the document-ready self-init in `rui.js` or the twelve
  `js_call_amd` calls to go. The warning is harmless: the guard prevents an
  actual double initialisation.
* It cannot rebuild `amd/build/rui.min.js`; only Grunt does that.
* It cannot stop `bs4-compat.js` from renaming `data-toggle` to
  `data-bs-toggle`, and it cannot make core `moremenu.js` look for the new
  name. What it can do is carry a small script in Moodle's Additional HTML
  setting that puts the attribute back (script 06, section 5). The
  equivalent file change would be one line after `Bs4Compat.init(document)`
  in `theme/iomadmoon/amd/src/loader.js`.
* It cannot change the base font size.

## 3. Files

| File | Writes? | Purpose |
|---|---|---|
| `01-verify.sql` | no | Snapshot of every relevant row. Run before and after. |
| `02-apply-cache-purge.sql` | yes | Bumps `jsrev`, `themerev`, `templaterev`, `localcachedirpurged` exactly like Moodle's own reset functions. Always safe. |
| `03-optional-serve-source-js.sql` | yes | `cachejs = 0`: serve `amd/src/rui.js` instead of the stale build. Costs performance. |
| `04-optional-fontheadings.sql` | yes | Sets `theme_iomadmoon/fontheadings` to Poppins. Only if headings render in the wrong family. |
| `05-rollback.sql` | yes | Restores `cachejs = 1` and empty `fontheadings`, bumps revisions. |
| `06-fix-moremenu-toggle-additionalhtml.sql` | yes | Fix for the `moveIntoMoreDropdown` error: stores a block in `mdl_config.additionalhtmlfooter` that restores `data-toggle="dropdown"` on More-menu toggles. Idempotent (marker check). |
| `07-remove-moremenu-toggle-additionalhtml.sql` | yes | Removes exactly the block that 06 added. |
| `08-lastresort-switch-theme-to-iomadboost.sql` | yes | Last resort only: switches site, companies, users, courses, categories and cohorts from `iomadmoon` to `iomadboost`. Refuses to run if `iomadboost` is not installed. Back up first. |
| `09-rollback-theme-switch.sql` | yes | Reverses script 08. |
| `10-optional-hide-primary-nav-nodes.sql` | yes | Plain-value workaround: hides `home`, `myhome`, `courses` from the top-bar navigation so no active item is left to move on everyday pages. Does not cover Site administration or IOMAD Company dashboard pages. |
| `11-align-plugin-version-after-file-restore.sql` | yes | After the theme files are put back to the vendor build: aligns `theme_iomadmoon/version` with the restored `version.php`, bumps cache revisions so the old JavaScript bundle stops being served, clears leftover whitespace in `additionalhtmlfooter`. See section 9. |

## 4. Procedure

Copy this directory to the server (the examples assume
`/root/iomadmoon-database-fixes`) and run from the code root used in the
diagnostics:

```bash
cd /var/www/html/moodle
FIX=/root/iomadmoon-database-fixes
DB="mysql --defaults-file=/etc/mysql/debian.cnf --database=iomad"
```

### Step 0: back up the rows that will change

```bash
mysqldump --defaults-file=/etc/mysql/debian.cnf --no-create-info --replace --skip-extended-insert \
  --where="name IN ('cachejs','jsrev','themerev','templaterev','localcachedirpurged','custommenuitems','debug','debugdisplay')" \
  iomad mdl_config > /root/backup-mdl_config-$(date +%F-%H%M).sql

mysqldump --defaults-file=/etc/mysql/debian.cnf --no-create-info --replace --skip-extended-insert \
  --where="plugin='theme_iomadmoon'" \
  iomad mdl_config_plugins > /root/backup-mdl_config_plugins-$(date +%F-%H%M).sql

# Companies table: mdl_local_iomad_companies on IOMAD 5.x, mdl_company on older releases.
mysqldump --defaults-file=/etc/mysql/debian.cnf --no-create-info --replace --skip-extended-insert \
  iomad mdl_local_iomad_companies > /root/backup-companies-$(date +%F-%H%M).sql \
  || mysqldump --defaults-file=/etc/mysql/debian.cnf --no-create-info --replace --skip-extended-insert \
  iomad mdl_company > /root/backup-companies-$(date +%F-%H%M).sql
```

Restoring is `$DB < /root/backup-....sql` (the dumps use `REPLACE INTO`).

### Step 1: verify

```bash
$DB --table < $FIX/01-verify.sql
```

### Step 2: apply

```bash
$DB --table < $FIX/02-apply-cache-purge.sql          # always
$DB --table < $FIX/06-fix-moremenu-toggle-additionalhtml.sql   # the moveIntoMoreDropdown fix (section 5)
$DB --table < $FIX/03-optional-serve-source-js.sql   # only if the 2026-09-04 rui.js edit must go live
$DB --table < $FIX/04-optional-fontheadings.sql      # only if headings show the wrong font
```

### Step 3: purge Moodle's caches (mandatory after any direct SQL)

Moodle reads `mdl_config` and `mdl_config_plugins` through its MUC
`core/config` cache and only invalidates that cache when a value is saved via
`set_config()`. A row changed with SQL is therefore invisible until the cache
is purged. Use Moodle's shipped script, as the web server user so no
root-owned files end up in moodledata:

```bash
sudo -u www-data php admin/cli/purge_caches.php
```

Run it from the directory that contains `config.php` (on a Moodle 5.x
layout that is the parent of `public/`). The admin UI equivalent is
Site administration > Development > Purge caches.

### Step 4: check in the browser

* Page source: with `cachejs = 1` the loader URL is
  `/lib/requirejs.php/<jsrev>/core/first.js`; with `cachejs = 0` it is
  `/lib/requirejs.php/-1/core/first.js` and `rui.js` comes from `amd/src`.
* The `SpaceTheme already initialized` warning is expected to remain (section 2).
* After script 06, the page source has the block between
  `<!-- iomadmoon-moremenu-fix:start -->` and `:end` just before `</body>`.
  In the console, after a hard reload and a window resize:

  ```js
  console.log('old attr:', document.querySelectorAll('.moremenu [data-toggle="dropdown"]').length,
              'renamed:', document.querySelectorAll('.moremenu [data-bs-toggle="dropdown"]').length);
  ```

  Before the fix this printed `old attr: 0 renamed: 1` (the failure
  condition); after it both counts are equal and the error no longer fires.

### Rollback

```bash
$DB --table < $FIX/05-rollback.sql
$DB --table < $FIX/07-remove-moremenu-toggle-additionalhtml.sql   # only if 06 was run
$DB --table < $FIX/09-rollback-theme-switch.sql                   # only if 08 was run
sudo -u www-data php admin/cli/purge_caches.php
sudo -u www-data php admin/cli/kill_all_sessions.php   # only if 08 or 09 was run
```

## 5. The `moveIntoMoreDropdown` error: what the database can and cannot do

Mechanism, from the files on the server and the served bundle:

1. `lib/templates/moremenu.mustache` and the theme's
   `templates/core/course-moremenu.mustache` render the "More" toggle with
   `data-toggle="dropdown"` (this core is Bootstrap 4).
2. `theme/iomadmoon/amd/src/loader.js` runs `Bs4Compat.init(document)`;
   `bs4-compat.js` sets `data-bs-toggle` and removes `data-toggle` on every
   `[data-toggle="dropdown"]`.
3. `lib/amd/src/moremenu.js` keeps `dropdowntoggle: '[data-toggle="dropdown"]'`,
   so `dropdownToggle` is `null` after step 2.
4. `moveIntoMoreDropdown()` only touches `dropdownToggle` when the item being
   moved is active. So the error appears when a menu wraps (window resize,
   medium widths, course pages with many secondary tabs) and the active item
   is pushed into "More".

Confirmed on the live site (Moodle 4.5.13, theme v1.8.0 for 4.5):
`bs4-compat.js` reads no configuration, `loader.js` passes it none, and the
rendered primary navigation has `data-toggle` count 0 and `data-bs-toggle`
count 1.

Consequences for a database-only rule:

* **No theme or core setting causes it.** Custom menu items were a wrong
  lead (the site value was empty; company 529's value is intact).
* **The fix (script 06):** the one Moodle setting that injects markup into
  every page is Additional HTML (`mdl_config.additionalhtmlfooter`, printed
  by `standard_end_of_body_html()`). The block it stores restores
  `data-toggle="dropdown"` on every More-menu toggle that has
  `data-bs-toggle="dropdown"`, immediately and whenever the DOM changes
  (MutationObserver), so it does not matter whether the compat shim runs
  before or after core. Both attributes coexist safely: the theme's
  Bootstrap 5 opens the dropdown from `data-bs-toggle`, core `moremenu.js`
  finds it from `data-toggle`, and no Bootstrap 4 JavaScript is loaded on
  this theme. Purge caches afterwards (the row is read through the config
  cache). It is JavaScript, but it lives in a database row and no file
  changes. Remove with script 07.
* **Plain-value workaround (script 10):** `theme_iomadmoon/hidenodesprimarynavigation`
  (a multi-checkbox stored comma-separated; the theme accepts only `home`,
  `myhome`, `courses`) removes those nodes from the top bar. Because core
  only dereferences the null toggle for the *active* item, hiding the nodes
  that are active on everyday pages makes the crash impossible there.
  "Site administration" and IOMAD's "Company dashboard" (`ioaddashboardnode`)
  cannot be hidden this way, so the error can still fire on `/admin/*` and
  `/blocks/iomad_company_admin/*` pages when the bar wraps. Applied on the
  live site on 2026-09-04 with the value `home,myhome,courses,siteadminnode`
  (the last key is ignored). Revert to `home`.
* **Last resort (script 08):** switching every theme pin to `iomadboost`,
  which does not load `bs4-compat.js`, then purge caches and
  `admin/cli/kill_all_sessions.php` (`$USER->theme` lives in the session).
  Reverse with script 09 plus the same two commands.

## 6. Conditional: developer debugging and the warning

If the `Logger` object in `rui.js` only prints when Moodle's developer
debugging is on, production debug levels hide the warning. Check without
changing anything:

```bash
grep -n "developerdebug\|M.cfg.debug\|const Logger" theme/iomadmoon/amd/src/rui.js
```

If it does consult `M.cfg.developerdebug`, and `01-verify.sql` shows
`debug = 32767`, the production values are a database change:

```sql
UPDATE mdl_config SET value = '0' WHERE name IN ('debug', 'debugdisplay');
```

followed by step 3.

## 7. Same changes through Moodle's own CLI instead of SQL

`admin/cli/cfg.php` writes the same rows through `set_config()` and
invalidates the cache itself, so step 3 is not needed for these:

```bash
sudo -u www-data php admin/cli/cfg.php --name=cachejs --set=0
sudo -u www-data php admin/cli/cfg.php --name=additionalhtmlfooter --set="$(cat snippet.html)"   # same block as script 06, saved to snippet.html
sudo -u www-data php admin/cli/cfg.php --component=theme_iomadmoon --name=fontheadings --set="'Poppins', sans-serif"
```

Per-company and per-user theme rows have no CLI; use script 08 or the
company edit form (Company details > Theme).

## 8. Reference: where the behaviour comes from (Moodle core, unchanged)

* `lib/classes/output/requirements/page_requirements_manager.php`,
  `get_jsrev()`: `cachejs` empty gives revision `-1`.
* `lib/requirejs.php`: revision `-1` serves one module per request and
  falls back to `amd/src/*.js` when `amd/build/*.min.js.map` is absent;
  `js_send_uncached()` sets `Expires` two seconds ahead.
* `lib/outputlib.php`: `theme_reset_all_caches()`, `js_reset_all_caches()`,
  `template_reset_all_caches()` (revision = now, or previous + 1).
* `lib/moodlelib.php`, `purge_other_caches()`: sets `localcachedirpurged`;
  `lib/setuplib.php`, `make_localcache_directory()`: wipes localcache when
  `.lastpurged` is older than that value.
* `lib/amd/src/moremenu.js`: `autoCollapse()`, `moveIntoMoreDropdown()`,
  `Selectors.attributes.dropdowntoggle = '[data-toggle="dropdown"]'`.
* `lib/pagelib.php`, `resolve_theme()`: order course, category, session,
  user, cohort, site; `$USER->theme` is the session copy, hence
  `admin/cli/kill_all_sessions.php` after a database theme switch.
* `lib/classes/navigation/output/primary.php`, `get_custom_menu()`:
  `$CFG->custommenuitems`, overridden by the company row's `custommenuitems`.
* `local/iomad/classes/company.php`, `update_theme()`: copies the company
  theme into `mdl_user.theme` (`allowuserthemes = 1`).

## 9. After the theme files were put back to the vendor build

Observed on 2026-09-04 around 06:00 UTC: the theme directory on the server
changed between two diagnostic runs.

| File | Before | After |
|---|---|---|
| `amd/src/loader.js` | 5706 bytes, 2026-08-27 | 3822 bytes, 2025-02-15 |
| `amd/build/loader.min.js` | 2092 bytes, 2026-08-27 | 3106 bytes, 2025-02-15 |
| `amd/src/bs4-compat.js` | 6577 bytes, 2025-12-02 | absent |
| `amd/src/index.js` | 943 bytes, 2025-05-09 | 939 bytes, 2025-02-13 |

The vendor's loader, read from `loader.min.js.map` (`sourcesContent`),
contains no `bs4-compat`, `Bs4Compat` or `data-bs-toggle` and four
`data-toggle`. That build never renames the attribute core `moremenu.js`
looks up, so the `moveIntoMoreDropdown` cause is gone from the code. The
later build (Bootstrap 5 files plus the compat shim, dated 2025-12-02, and
the loader rewrite of 2026-08-27) was a server-side change, not the vendor's
release. Whoever restored the files did the right thing; the database now
has to follow, which is script 11.

Result of running this on 2026-09-04 (06:09 UTC):

| Check | Output | Meaning |
|---|---|---|
| `version.php` on disk | `2026041805.01`, release `v1.8.0 for 4.5` | The restored build carries the same version number the database already held, so script 11 changed nothing there and there is no downgrade. |
| `admin/cli/upgrade.php --non-interactive` | `No upgrade needed for the installed version 4.5.13` | `allversionshash` matches the files on disk. |
| `jsrev`, `themerev`, `templaterev`, `localcachedirpurged` | all `1788502163`, moved again by `purge_caches.php` | Browsers get new bundle URLs; every web node wipes its local cache on its next request (see section 10). |
| `find -newermt 2025-03-01` | lists `settings/*.php` from 2026 | Expected: the v1.8.0 release itself is from 2026. File dates do not tell the vendor build from the later one; the presence of `amd/src/bs4-compat.js` and `data-bs-toggle` in `amd/` or `templates/` does. |

The `find | head` line stopped the block from finishing: `head` exits after
its lines, `find` keeps walking until it next writes, and a large tree (a
`node_modules` left behind by a development build, for instance) makes that
a long wait. The bounded commands below replace it.

Why the rows matter:

1. `theme_iomadmoon/version` must equal `$plugin->version` in `version.php`.
   With a lower number on disk Moodle flags a plugin downgrade and blocks
   the upgrade screen; setting the row to the code's value is Moodle's
   documented rollback. Equal numbers, as observed, mean nothing to do.
2. Moodle stores a hash of every plugin's `version.php` in
   `allversionshash`; a changed `version.php` makes `moodle_needs_upgrade()`
   true until `admin/cli/upgrade.php` recomputes it.
3. The cached JavaScript bundle is keyed by `jsrev`; until it moves,
   browsers keep receiving the bundle built from the old loader.

```bash
cd /var/www/html/moodle
grep -n 'version\|release' theme/iomadmoon/version.php
# Later-build leftovers where they matter (served JS and templates); exit=1 means none found.
timeout 60 grep -rIl --exclude-dir=node_modules -e 'bs4-compat' -e 'Bs4Compat' -e 'data-bs-toggle' \
  theme/iomadmoon/amd theme/iomadmoon/templates 2>/dev/null; echo "shim refs on host exit=$?"
ls -la theme/iomadmoon/amd/src/loader.js theme/iomadmoon/amd/src/bs4-compat.js 2>&1

CODEVER=$(grep -oP '^\$plugin->version\s*=\s*\K[0-9.]+' theme/iomadmoon/version.php)
mysql --defaults-file=/etc/mysql/debian.cnf --database=iomad --table \
  --init-command="SET @codeversion='$CODEVER'" < $FIX/11-align-plugin-version-after-file-restore.sql
sudo -u www-data php admin/cli/upgrade.php --non-interactive
sudo -u www-data php admin/cli/purge_caches.php
```

Verification in the browser after a hard reload at a narrow width:

```js
console.log('old:', document.querySelectorAll('.moremenu [data-toggle="dropdown"]').length,
            'renamed:', document.querySelectorAll('.moremenu [data-bs-toggle="dropdown"]').length);
```

Expected `old: 1 renamed: 0` and no error when the bar collapses. If
`rui.js` was restored as well, the `SpaceTheme already initialized` line is
gone too; if it remains, `ls -la theme/iomadmoon/amd/src/rui.js` shows
whether the later build's `rui.js` (2026 date, `SpaceTheme.init()` on
document-ready) is still in place.

## 10. When the site runs in containers (podman, one compose file)

The site was moved to podman containers (six containers, one compose file,
one env file per container). That changes which copy of the files the
browser gets and which cache directories a purge reaches, so three
read-only checks come first. None of them changes a file or a row.

What the database rows do across containers: `make_localcache_directory()`
(`lib/setuplib.php`) compares the mtime of `localcache/.lastpurged` with
`localcachedirpurged` on every request and wipes that node's local cache
directory when the row is newer. So the row set by script 02/11 or by
`purge_caches.php` reaches every web container on its own, including the
`localcache/requirejs/` bundles. The `core/config` MUC cache, however, lives
in `$CFG->cachedir` (`moodledata/cache` by default): a purge run on the host
only empties it for a container that shares that moodledata directory.

```bash
# 1. Which container serves the site, and what it mounts.
podman ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
for c in $(podman ps --format '{{.Names}}'); do
  echo "== $c mounts:"
  podman inspect "$c" --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
done

# 2. The theme files each container actually has.
for c in $(podman ps --format '{{.Names}}'); do
  podman exec "$c" sh -c '
    for d in /var/www/html/moodle /var/www/html /var/www/moodle /app /bitnami/moodle /opt/moodle; do
      [ -f "$d/theme/iomadmoon/version.php" ] || continue
      echo "== '"$c"': moodle code at $d"
      grep -o "version = [0-9.]*" "$d/theme/iomadmoon/version.php"
      ls -la "$d/theme/iomadmoon/amd/src/loader.js" "$d/theme/iomadmoon/amd/src/bs4-compat.js" 2>&1
      echo "data-bs-toggle in built loader: $(grep -c data-bs-toggle "$d/theme/iomadmoon/amd/build/loader.min.js")"
    done' 2>/dev/null
done

# 3. What the site serves, independent of where the files are.
SITE=https://learn.greencultured.co
JSREV=$(mysql --defaults-file=/etc/mysql/debian.cnf iomad -N -e "SELECT value FROM mdl_config WHERE name='jsrev'")
CACHEJS=$(mysql --defaults-file=/etc/mysql/debian.cnf iomad -N -e "SELECT value FROM mdl_config WHERE name='cachejs'")
echo "db jsrev=$JSREV cachejs=$CACHEJS"
echo "jsrev in served pages: $(curl -s $SITE/login/index.php | grep -o 'requirejs.php/[-0-9]*' | sort -u | tr '\n' ' ')"
if [ "$CACHEJS" = "0" ]; then URL="$SITE/lib/requirejs.php/-1/theme_iomadmoon/loader.js"; else URL="$SITE/lib/requirejs.php/$JSREV/core/first.js"; fi
curl -s "$URL" -o /root/served.js; ls -la /root/served.js
echo "shim markers in served JS:"; grep -o 'theme_iomadmoon/bs4-compat\|data-bs-toggle' /root/served.js | sort | uniq -c
```

Reading the output:

- **Served pages carry the database `jsrev`** and the served JS has no
  `bs4-compat` / `data-bs-toggle`: the site delivers the vendor build. The
  rename that nulled the "More" toggle cannot happen; the console check in
  section 9 should show `old: 1 renamed: 0`. An error that still appears is
  a browser holding the old bundle: hard reload, and confirm in the Network
  tab that `requirejs.php` is fetched with the new number.
- **Served pages carry an older `jsrev`** than the database: the web
  container reads `core/config` from a cache the host purge did not reach
  (its moodledata is a different volume). Run the purge where that cache is:
  `podman exec <web container> php <path>/admin/cli/purge_caches.php`.
  That is a cache operation, not a code change.
- **Served JS still contains the shim** while the host directory is clean:
  the container serves its own copy of the code (step 1 shows no bind mount
  of `/var/www/html/moodle`, or a mount from another path). No database row
  selects which files a container serves; the vendor build has to be present
  at the path the container mounts, the same restore that was done on the
  host, followed by the section 9 alignment. Until then, the only database
  measures are the ones in section 5.
