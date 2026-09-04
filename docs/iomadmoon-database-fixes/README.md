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
| Console error `TypeError: Cannot read properties of null (reading 'classList') at moveIntoMoreDropdown (core/first.js)` | `core/moremenu.js` collapses the primary navigation when it wraps to a second line; for each moved `<li>` it does `navNode.querySelector('.nav-link').classList`. One `<li>` in the menu has no `.nav-link` descendant. | The only menu items stored in the database are custom menu items: `mdl_config.custommenuitems` (site) and the companies table column `custommenuitems` (per company, overrides the site value). |
| Fonts | `fontbody = 'Poppins', sans-serif`, weights 400/500/700, `googlefonturl` loads exactly those weights. `fontheadings` is empty, so the SCSS default applies. No font-size setting exists in the database (`$font-size-base: 1rem` is SCSS). | Consistent. Only `fontheadings` is optionally settable. |
| Caches | `jsrev = themerev = 1788497399` (2026-09-04 04:36 UTC), i.e. purged after the source edit. | Fine. |

## 2. What the database cannot do

* It cannot remove the `SpaceTheme already initialized` warning. Removing it
  needs either the document-ready self-init in `rui.js` or the twelve
  `js_call_amd` calls to go. The warning is harmless: the guard prevents an
  actual double initialisation.
* It cannot rebuild `amd/build/rui.min.js`; only Grunt does that.
* It cannot add a missing `.nav-link` to a `<li>` that the theme's templates
  render. If script 06 finds nothing to clear, the offending item is template
  markup.
* It cannot change the base font size.

## 3. Files

| File | Writes? | Purpose |
|---|---|---|
| `01-verify.sql` | no | Snapshot of every relevant row. Run before and after. |
| `02-apply-cache-purge.sql` | yes | Bumps `jsrev`, `themerev`, `templaterev`, `localcachedirpurged` exactly like Moodle's own reset functions. Always safe. |
| `03-optional-serve-source-js.sql` | yes | `cachejs = 0`: serve `amd/src/rui.js` instead of the stale build. Costs performance. |
| `04-optional-fontheadings.sql` | yes | Sets `theme_iomadmoon/fontheadings` to Poppins. Only if headings render in the wrong family. |
| `05-rollback.sql` | yes | Restores `cachejs = 1` and empty `fontheadings`, bumps revisions. |
| `06-optional-clear-custom-menu-items.sql` | yes | Clears site and company custom menu items (the `moveIntoMoreDropdown` error). Back up first. |

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
$DB --table < $FIX/06-optional-clear-custom-menu-items.sql   # if step 1 shows custom menu items
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
* The `moveIntoMoreDropdown` error disappears only if the item without
  `.nav-link` came from the custom menu. To see which `<li>` it is, read it
  from the rendered page without changing anything (browser console):

  ```js
  document.querySelectorAll('.moremenu > li').forEach(li => {
    if (!li.querySelector('.nav-link')) console.log(li.outerHTML);
  });
  ```

### Rollback

```bash
$DB --table < $FIX/05-rollback.sql
$DB < /root/backup-companies-<stamp>.sql      # only if 06 was run
$DB < /root/backup-mdl_config-<stamp>.sql     # only if custommenuitems must come back
sudo -u www-data php admin/cli/purge_caches.php
```

## 5. Conditional: developer debugging and the warning

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

## 6. Same changes through Moodle's own CLI instead of SQL

`admin/cli/cfg.php` writes the same rows through `set_config()` and
invalidates the cache itself, so step 3 is not needed for these:

```bash
sudo -u www-data php admin/cli/cfg.php --name=cachejs --set=0
sudo -u www-data php admin/cli/cfg.php --name=custommenuitems --set=
sudo -u www-data php admin/cli/cfg.php --component=theme_iomadmoon --name=fontheadings --set="'Poppins', sans-serif"
```

Per-company custom menu items have no CLI; use script 06 or the company
edit form (Company details > Custom menu items).

## 7. Reference: where the behaviour comes from (Moodle core, unchanged)

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
* `lib/amd/src/moremenu.js`: `autoCollapse()` and `moveIntoMoreDropdown()`.
* `lib/classes/navigation/output/primary.php`, `get_custom_menu()`:
  `$CFG->custommenuitems`, overridden by the company row's `custommenuitems`.
* `local/iomad/classes/company.php`, `update_theme()`: copies the company
  theme into `mdl_user.theme` (`allowuserthemes = 1`).
