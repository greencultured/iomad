-- =====================================================================
-- theme_iomadmoon database fixes: 06-optional-clear-custom-menu-items.sql
-- ---------------------------------------------------------------------
-- OPTIONAL. For the browser error
--   TypeError: Cannot read properties of null (reading 'classList')
--       at moveIntoMoreDropdown (core/first.js)
--
-- core/moremenu.js collapses the primary navigation into the "More"
-- dropdown when its items wrap onto a second line. For every <li> it
-- moves it runs navNode.querySelector('.nav-link').classList, so the
-- error means (a) the menu overflowed and (b) one of its <li> children
-- has no .nav-link inside it.
--
-- The only primary-navigation content that lives in the database is the
-- custom menu: mdl_config.custommenuitems (site) and the companies
-- table column custommenuitems (per company; overrides the site value).
-- Clearing them removes those items from the menu, which both shortens
-- it and removes any malformed entry. BACK UP FIRST (README, step 0);
-- the text cannot be recovered otherwise.
--
-- If 01-verify.sql shows both empty, this script changes nothing and the
-- offending <li> comes from the theme's templates, which is not a
-- database matter. Purge caches afterwards (README, step 3).
-- =====================================================================

-- Companies table (and column) differ between IOMAD releases.
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

-- Show what is about to be cleared.
SELECT 'mdl_config' AS source, 'site' AS scope, value AS custommenuitems
FROM mdl_config WHERE name = 'custommenuitems';

SET @sql := IF(@hascustommenu > 0, CONCAT(
    'SELECT ''', @companytable, ''' AS source, shortname AS scope, custommenuitems ',
    'FROM ', @companytable, ' WHERE COALESCE(custommenuitems, '''') <> '''''
), 'SELECT ''companies table has no custommenuitems column'' AS note');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

START TRANSACTION;

UPDATE mdl_config SET value = '' WHERE name = 'custommenuitems';

SET @sql := IF(@hascustommenu > 0, CONCAT(
    'UPDATE ', @companytable, ' SET custommenuitems = '''' ',
    'WHERE COALESCE(custommenuitems, '''') <> '''''
), 'SELECT ''nothing to clear at company level'' AS note');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Templates and theme caches must be regenerated.
UPDATE mdl_config
SET value = CASE
    WHEN CAST(value AS SIGNED) >= UNIX_TIMESTAMP()
     AND CAST(value AS SIGNED) - UNIX_TIMESTAMP() < 3600
    THEN CAST(value AS SIGNED) + 1
    ELSE UNIX_TIMESTAMP()
END
WHERE name IN ('themerev', 'templaterev');

COMMIT;

SELECT name, OCTET_LENGTH(COALESCE(value, '')) AS bytes_left
FROM mdl_config WHERE name = 'custommenuitems';
