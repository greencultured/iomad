-- =====================================================================
-- theme_iomadmoon database fixes: 11-align-plugin-version-after-file-restore.sql
-- ---------------------------------------------------------------------
-- Run AFTER the theme directory has been put back to the vendor build
-- (observed on 2026-09-04: amd/src/loader.js 3822 bytes dated
-- 2025-02-15, no amd/src/bs4-compat.js). The database still describes
-- the replaced build, and three rows have to follow the code:
--
--   * theme_iomadmoon/version in mdl_config_plugins was written by the
--     replaced version.php (2026041805.01). If the restored version.php
--     is lower, Moodle reports a plugin downgrade and blocks the
--     upgrade screen. Setting the row to the code's value is Moodle's
--     documented way to roll a plugin back.
--   * jsrev / themerev / templaterev / localcachedirpurged predate the
--     restore, so browsers keep receiving the cached JavaScript bundle
--     built from the OLD loader (the one that renamed data-toggle).
--   * additionalhtmlfooter may hold whitespace left by script 07.
--
-- Usage: the code version is read from version.php by the shell and
-- passed in as a MySQL user variable (README, section 9):
--
--   CODEVER=$(grep -oP '^\$plugin->version\s*=\s*\K[0-9.]+' theme/iomadmoon/version.php)
--   mysql --defaults-file=/etc/mysql/debian.cnf --database=iomad --table \
--       --init-command="SET @codeversion='$CODEVER'" < 11-align-plugin-version-after-file-restore.sql
--
-- Nothing is written unless @codeversion is a plausible version number.
-- Afterwards run admin/cli/upgrade.php --non-interactive (recomputes
-- Moodle's stored allversionshash for the changed version.php) and
-- admin/cli/purge_caches.php.
-- =====================================================================

SET @codeversion := COALESCE(@codeversion, '');
SET @ok := (@codeversion REGEXP '^[0-9]{10}(\\.[0-9]+)?$');

SELECT @codeversion AS code_version,
       (SELECT value FROM mdl_config_plugins WHERE plugin = 'theme_iomadmoon' AND name = 'version') AS db_version_before,
       IF(@ok, 'aligning', 'no valid @codeversion given: nothing will be changed') AS action;

START TRANSACTION;

UPDATE mdl_config_plugins
SET value = @codeversion
WHERE @ok AND plugin = 'theme_iomadmoon' AND name = 'version' AND value <> @codeversion;

UPDATE mdl_config
SET value = ''
WHERE @ok AND name = 'additionalhtmlfooter'
  AND TRIM(BOTH '\n' FROM TRIM(BOTH '\r' FROM TRIM(value))) = '';

UPDATE mdl_config
SET value = CASE
    WHEN CAST(value AS SIGNED) >= UNIX_TIMESTAMP()
     AND CAST(value AS SIGNED) - UNIX_TIMESTAMP() < 3600
    THEN CAST(value AS SIGNED) + 1
    ELSE UNIX_TIMESTAMP()
END
WHERE @ok AND name IN ('jsrev', 'themerev', 'templaterev');

UPDATE mdl_config SET value = UNIX_TIMESTAMP()
WHERE @ok AND name = 'localcachedirpurged';

COMMIT;

SELECT name, value FROM mdl_config_plugins WHERE plugin = 'theme_iomadmoon' AND name = 'version';
SELECT name, value, FROM_UNIXTIME(CAST(value AS SIGNED)) AS as_datetime_utc
FROM mdl_config WHERE name IN ('jsrev', 'themerev', 'templaterev', 'localcachedirpurged') ORDER BY name;
