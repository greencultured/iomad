-- =====================================================================
-- theme_iomadmoon database fixes: 02-apply-cache-purge.sql
-- ---------------------------------------------------------------------
-- Bumps every cache revision Moodle keeps in the database, exactly the
-- way theme_reset_all_caches(), js_reset_all_caches(),
-- template_reset_all_caches() and purge_all_caches() do it:
--   * new value = now, or previous + 1 if the previous value is already
--     "now" (or up to 1 hour in the future), so it always increases;
--   * localcachedirpurged = now makes every web node wipe its
--     localcache directory (compiled theme CSS, requirejs bundles) on
--     the next request.
--
-- Moodle only reads mdl_config through its MUC "core/config" cache, so
-- after this script you MUST purge caches once with Moodle's own tool
-- (see README, step 3). Safe to run at any time; no side effects other
-- than browsers re-downloading CSS/JS once.
-- =====================================================================

START TRANSACTION;

UPDATE mdl_config
SET value = CASE
    WHEN CAST(value AS SIGNED) >= UNIX_TIMESTAMP()
     AND CAST(value AS SIGNED) - UNIX_TIMESTAMP() < 3600
    THEN CAST(value AS SIGNED) + 1
    ELSE UNIX_TIMESTAMP()
END
WHERE name IN ('jsrev', 'themerev', 'templaterev');

INSERT INTO mdl_config (name, value)
SELECT 'jsrev', UNIX_TIMESTAMP() FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM mdl_config WHERE name = 'jsrev');

INSERT INTO mdl_config (name, value)
SELECT 'themerev', UNIX_TIMESTAMP() FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM mdl_config WHERE name = 'themerev');

INSERT INTO mdl_config (name, value)
SELECT 'templaterev', UNIX_TIMESTAMP() FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM mdl_config WHERE name = 'templaterev');

UPDATE mdl_config
SET value = UNIX_TIMESTAMP()
WHERE name = 'localcachedirpurged';

INSERT INTO mdl_config (name, value)
SELECT 'localcachedirpurged', UNIX_TIMESTAMP() FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM mdl_config WHERE name = 'localcachedirpurged');

COMMIT;

SELECT name, value, FROM_UNIXTIME(CAST(value AS SIGNED)) AS as_datetime_utc
FROM mdl_config
WHERE name IN ('jsrev', 'themerev', 'templaterev', 'localcachedirpurged')
ORDER BY name;
