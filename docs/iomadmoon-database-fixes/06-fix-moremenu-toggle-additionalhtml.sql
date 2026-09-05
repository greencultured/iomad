-- =====================================================================
-- theme_iomadmoon database fixes: 06-fix-moremenu-toggle-additionalhtml.sql
-- ---------------------------------------------------------------------
-- FIX for the browser error
--   TypeError: Cannot read properties of null (reading 'classList')
--       at moveIntoMoreDropdown (core/first.js:94:2028)
--
-- Proven cause (live DOM: `.moremenu [data-toggle="dropdown"]` count 0,
-- `.moremenu [data-bs-toggle="dropdown"]` count 1):
--   theme/iomadmoon/amd/src/bs4-compat.js renames data-toggle="dropdown"
--   to data-bs-toggle="dropdown" and removes the old attribute; Moodle
--   4.5 core lib/amd/src/moremenu.js looks the "More" toggle up with
--   [data-toggle="dropdown"], gets null, and dereferences it when an
--   active item overflows into "More".
--
-- What this script does: stores a small script in mdl_config
-- additionalhtmlfooter (Site administration > Appearance > Additional
-- HTML > "When BODY is closed"). Moodle prints that row on every page.
-- The script puts data-toggle="dropdown" back on every More-menu
-- toggle that carries data-bs-toggle="dropdown" (both attributes
-- coexist: the theme's Bootstrap 5 opens the dropdown via
-- data-bs-toggle, core moremenu.js finds it via data-toggle) and keeps
-- doing so via a MutationObserver, so the order in which the compat
-- shim and core run does not matter.
--
-- No file is touched. Idempotent: the row is only changed if the
-- marker is absent. Remove with 07-remove-moremenu-toggle-additionalhtml.sql.
-- Purge caches afterwards (README, step 3): mdl_config is cached.
-- =====================================================================

SET @snippet := '
<!-- iomadmoon-moremenu-fix:start -->
<script>
(function () {
    var SELECTOR = ".moremenu [data-bs-toggle=dropdown]:not([data-toggle])";
    function restore() {
        var nodes = document.querySelectorAll(SELECTOR);
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].setAttribute("data-toggle", "dropdown");
        }
    }
    function start() {
        restore();
        if (!window.MutationObserver) {
            return;
        }
        new MutationObserver(restore).observe(document.documentElement, {
            subtree: true,
            childList: true,
            attributes: true,
            attributeFilter: ["data-bs-toggle"]
        });
    }
    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", start);
    } else {
        start();
    }
})();
</script>
<!-- iomadmoon-moremenu-fix:end -->
';

START TRANSACTION;

INSERT INTO mdl_config (name, value)
SELECT 'additionalhtmlfooter', '' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM mdl_config WHERE name = 'additionalhtmlfooter');

UPDATE mdl_config
SET value = CONCAT(COALESCE(value, ''), @snippet)
WHERE name = 'additionalhtmlfooter'
  AND COALESCE(value, '') NOT LIKE '%iomadmoon-moremenu-fix:start%';

COMMIT;

SELECT name, OCTET_LENGTH(value) AS bytes,
       value LIKE '%iomadmoon-moremenu-fix:start%' AS fix_present
FROM mdl_config WHERE name = 'additionalhtmlfooter';
