-- =====================================================================
-- theme_iomadmoon database fixes: 01-verify.sql  (READ-ONLY)
-- ---------------------------------------------------------------------
-- Snapshot of every database row that influences how the Moon theme
-- (theme_iomadmoon) is served. Run it BEFORE and AFTER any change.
-- It writes nothing. Table prefix assumed: mdl_
--
--   mysql --defaults-file=/etc/mysql/debian.cnf --database=iomad --table \
--       < 01-verify.sql
-- =====================================================================

-- 1. Core settings that decide which theme/JS is served and how caches work.
SELECT
    name,
    value,
    CASE
        WHEN name IN ('jsrev', 'themerev', 'templaterev', 'localcachedirpurged')
        THEN FROM_UNIXTIME(CAST(value AS UNSIGNED))
    END AS as_datetime_utc
FROM mdl_config
WHERE name IN (
    'theme',                 -- site theme (expected: iomadmoon)
    'cachejs',               -- 1 = serve amd/build/*.min.js, 0 = serve amd/src/*.js
    'jsrev',                 -- JavaScript cache revision
    'themerev',              -- theme (CSS) cache revision
    'templaterev',           -- Mustache template cache revision
    'localcachedirpurged',   -- forces every web node to wipe localcache
    'cachetemplates',
    'themedesignermode',     -- must be 0 on production
    'debug',                 -- 32767 = developer debugging
    'debugdisplay',
    'allowuserthemes'        -- IOMAD sets this to 1 (per-company themes)
)
ORDER BY name;

-- 2. Nothing injected into pages from the database (all lengths should be 0).
SELECT 'mdl_config' AS source, name, OCTET_LENGTH(COALESCE(value, '')) AS bytes
FROM mdl_config
WHERE name IN ('additionalhtmlhead', 'additionalhtmltopofbody', 'additionalhtmlfooter')
UNION ALL
SELECT CONCAT('mdl_config_plugins:', plugin), name, OCTET_LENGTH(COALESCE(value, ''))
FROM mdl_config_plugins
WHERE plugin = 'theme_iomadmoon'
  AND name IN ('additionalheadscripts', 'googleanalytics')
ORDER BY source, name;

-- 3. Moon theme settings that are compiled into SCSS (fonts) and its own revision.
SELECT name, QUOTE(value) AS value, OCTET_LENGTH(COALESCE(value, '')) AS bytes
FROM mdl_config_plugins
WHERE plugin = 'theme_iomadmoon'
  AND (name REGEXP 'font' OR name = 'googlefonturl' OR name = 'themerev' OR name = 'version')
ORDER BY name;

-- 4. Themes actually installed (a theme row in mdl_config_plugins with a version).
SELECT SUBSTRING(plugin, 7) AS installed_theme, value AS version
FROM mdl_config_plugins
WHERE plugin LIKE 'theme\_%' AND name = 'version'
ORDER BY 1;

-- 5. IOMAD company themes. The table is mdl_local_iomad_companies on
--    IOMAD 5.x and mdl_company on older releases; pick whichever exists.
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
SET @hascustommenu := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = @companytable
      AND column_name = 'custommenuitems'
);
SET @sql := CONCAT(
    'SELECT id, shortname, theme AS company_theme, ',
    IF(@hascustommenu > 0, 'OCTET_LENGTH(COALESCE(custommenuitems, ''''))', '0'),
    ' AS custommenu_bytes FROM ', @companytable, ' ORDER BY id'
);
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 6. Which theme users are pinned to (IOMAD copies the company theme into
--    mdl_user.theme). Empty string = site theme.
SELECT theme AS user_theme, COUNT(*) AS users
FROM mdl_user
WHERE deleted = 0
GROUP BY theme
ORDER BY users DESC;

-- 7. Users pinned to a theme that is NOT installed. Moodle silently falls
--    back to the site theme for them and emits a debugging notice.
SELECT u.theme AS missing_theme, COUNT(*) AS users
FROM mdl_user u
WHERE u.deleted = 0
  AND u.theme <> ''
  AND NOT EXISTS (
      SELECT 1 FROM mdl_config_plugins cp
      WHERE cp.name = 'version' AND cp.plugin = CONCAT('theme_', u.theme)
  )
GROUP BY u.theme;

-- 8. Everything in the database that adds items to the primary navigation
--    (the menu core/moremenu.js collapses into "More").
SELECT name, OCTET_LENGTH(COALESCE(value, '')) AS bytes, value
FROM mdl_config
WHERE name IN ('custommenuitems', 'langmenu', 'navfilter', 'stringfilters', 'commerce_admin_enableall')
ORDER BY name;
