-- =====================================================================
-- theme_iomadmoon database fixes: 05-rollback.sql
-- ---------------------------------------------------------------------
-- Restores the values recorded in the 2026-09-04 diagnostics:
--   cachejs = 1, theme_iomadmoon/fontheadings = '' (empty)
-- and bumps the cache revisions so browsers pick the change up.
-- If your 01-verify.sql snapshot showed different values, restore
-- those instead (or replay the mysqldump backup from README, step 0).
-- Custom menu items are restored from the mysqldump backup, not here.
-- Purge caches afterwards (README, step 3).
-- =====================================================================

START TRANSACTION;

UPDATE mdl_config SET value = '1' WHERE name = 'cachejs';

UPDATE mdl_config_plugins
SET value = ''
WHERE plugin = 'theme_iomadmoon' AND name = 'fontheadings';

UPDATE mdl_config
SET value = CASE
    WHEN CAST(value AS SIGNED) >= UNIX_TIMESTAMP()
     AND CAST(value AS SIGNED) - UNIX_TIMESTAMP() < 3600
    THEN CAST(value AS SIGNED) + 1
    ELSE UNIX_TIMESTAMP()
END
WHERE name IN ('jsrev', 'themerev', 'templaterev');

UPDATE mdl_config SET value = UNIX_TIMESTAMP() WHERE name = 'localcachedirpurged';

COMMIT;

SELECT name, value FROM mdl_config
WHERE name IN ('cachejs', 'jsrev', 'themerev', 'templaterev', 'localcachedirpurged')
ORDER BY name;
