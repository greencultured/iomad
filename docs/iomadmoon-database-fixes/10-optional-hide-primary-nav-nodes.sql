-- =====================================================================
-- theme_iomadmoon database fixes: 10-optional-hide-primary-nav-nodes.sql
-- ---------------------------------------------------------------------
-- WORKAROUND (plain settings value, no script) for the browser error
--   TypeError: Cannot read properties of null (reading 'classList')
--       at moveIntoMoreDropdown (core/first.js:94:2028)
--
-- core/moremenu.js only dereferences the (null) "More" toggle when the
-- item it moves is the ACTIVE one. theme_iomadmoon/hidenodesprimarynavigation
-- removes nodes from the top-bar primary navigation before it is
-- rendered, so hiding the nodes that are active on everyday pages makes
-- the crash impossible there.
--
-- Keys accepted by this theme (settings/topbar.php, $hidenodesoptions):
--   home     Site home
--   myhome   Dashboard
--   courses  My courses
-- Any other key (e.g. siteadminnode) is ignored by the theme.
--
-- NOT covered: "Site administration" and IOMAD's "Company dashboard"
-- (ioaddashboardnode) stay in the bar, so the error can still fire on
-- /admin/* and /blocks/iomad_company_admin/* pages when the bar wraps.
-- The links remain available in the Moon sidebar and the user menu.
--
-- The admin form would call theme_reset_all_caches() on save; this
-- script bumps themerev the same way. Purge caches afterwards
-- (README, step 3). Revert by setting the value back to 'home'.
-- =====================================================================

START TRANSACTION;

UPDATE mdl_config_plugins
SET value = 'home,myhome,courses'
WHERE plugin = 'theme_iomadmoon' AND name = 'hidenodesprimarynavigation';

INSERT INTO mdl_config_plugins (plugin, name, value)
SELECT 'theme_iomadmoon', 'hidenodesprimarynavigation', 'home,myhome,courses' FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM mdl_config_plugins
    WHERE plugin = 'theme_iomadmoon' AND name = 'hidenodesprimarynavigation'
);

UPDATE mdl_config
SET value = CASE
    WHEN CAST(value AS SIGNED) >= UNIX_TIMESTAMP()
     AND CAST(value AS SIGNED) - UNIX_TIMESTAMP() < 3600
    THEN CAST(value AS SIGNED) + 1
    ELSE UNIX_TIMESTAMP()
END
WHERE name IN ('themerev', 'templaterev');

COMMIT;

SELECT name, value FROM mdl_config_plugins
WHERE plugin = 'theme_iomadmoon' AND name = 'hidenodesprimarynavigation';
