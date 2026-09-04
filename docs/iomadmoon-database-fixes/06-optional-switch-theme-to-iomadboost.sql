-- =====================================================================
-- theme_iomadmoon database fixes: 06-optional-switch-theme-to-iomadboost.sql
-- ---------------------------------------------------------------------
-- OPTIONAL BYPASS for the browser error
--   TypeError: Cannot read properties of null (reading 'classList')
--       at moveIntoMoreDropdown (core/first.js:94:2028)
--
-- Root cause (code, not data): theme/iomadmoon/amd/src/bs4-compat.js
-- rewrites every data-toggle="dropdown" on the page to
-- data-bs-toggle="dropdown", but this Moodle core's lib/amd/src/moremenu.js
-- still looks the "More" toggle up with [data-toggle="dropdown"]. So
-- dropdownToggle is null, and the first time an ACTIVE navigation item
-- overflows into "More" (menu wraps on resize/init) core does
-- dropdownToggle.classList.add(...) and throws.
--
-- No settings row changes that JavaScript. The only database-level way
-- to stop the error site-wide without touching code is to stop serving
-- theme_iomadmoon: switch the site, every IOMAD company, and every row
-- that pins the theme to the parent theme iomadboost until the theme's
-- JavaScript is fixed. This changes the site's look. BACK UP FIRST
-- (README, step 0). Reverse with 07-rollback-theme-switch.sql.
--
-- Afterwards (README):  purge caches AND kill sessions, because
-- $USER->theme is held in each logged-in session.
-- =====================================================================

-- Refuse to do anything unless iomadboost is actually installed.
SET @ok := (
    SELECT COUNT(*) FROM mdl_config_plugins
    WHERE plugin = 'theme_iomadboost' AND name = 'version'
);
SELECT IF(@ok > 0, 'iomadboost installed: proceeding',
                    'iomadboost NOT installed: nothing will be changed') AS precheck;

SET @companytable := (
    SELECT CASE
        WHEN EXISTS (
            SELECT 1 FROM information_schema.tables
            WHERE table_schema = DATABASE() AND table_name = 'mdl_local_iomad_companies'
        )
        THEN 'mdl_local_iomad_companies'
        ELSE 'mdl_company'
    END
);

START TRANSACTION;

UPDATE mdl_config SET value = 'iomadboost'
WHERE @ok > 0 AND name = 'theme' AND value = 'iomadmoon';

SET @sql := CONCAT('UPDATE ', @companytable,
                   ' SET theme = ''iomadboost'' WHERE ', @ok, ' > 0 AND theme = ''iomadmoon''');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

UPDATE mdl_user              SET theme = 'iomadboost' WHERE @ok > 0 AND theme = 'iomadmoon';
UPDATE mdl_course            SET theme = 'iomadboost' WHERE @ok > 0 AND theme = 'iomadmoon';
UPDATE mdl_course_categories SET theme = 'iomadboost' WHERE @ok > 0 AND theme = 'iomadmoon';
UPDATE mdl_cohort            SET theme = 'iomadboost' WHERE @ok > 0 AND theme = 'iomadmoon';

UPDATE mdl_config
SET value = CASE
    WHEN CAST(value AS SIGNED) >= UNIX_TIMESTAMP()
     AND CAST(value AS SIGNED) - UNIX_TIMESTAMP() < 3600
    THEN CAST(value AS SIGNED) + 1
    ELSE UNIX_TIMESTAMP()
END
WHERE @ok > 0 AND name IN ('jsrev', 'themerev', 'templaterev');

UPDATE mdl_config SET value = UNIX_TIMESTAMP()
WHERE @ok > 0 AND name = 'localcachedirpurged';

COMMIT;

SELECT name, value FROM mdl_config WHERE name = 'theme';
SELECT theme AS user_theme, COUNT(*) AS users FROM mdl_user WHERE deleted = 0 GROUP BY theme;
