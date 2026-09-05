-- =====================================================================
-- theme_iomadmoon database fixes: 03-optional-serve-source-js.sql
-- ---------------------------------------------------------------------
-- OPTIONAL. Makes Moodle serve theme/iomadmoon/amd/src/rui.js (the file
-- edited on 2026-09-04) instead of the stale amd/build/rui.min.js
-- (built 2026-09-01) without rebuilding anything.
--
-- How it works: with cachejs = 0 Moodle's page_requirements_manager
-- uses JS revision -1 ("developer mode"); lib/requirejs.php then serves
-- each AMD module one by one and, because amd/build/rui.min.js.map does
-- not exist, falls back to amd/src/rui.js. Modules that DO have a .map
-- file (loader, drawers, aria, ...) keep being served from amd/build.
--
-- Cost: every AMD module is requested separately on every page view and
-- sent with an Expires header 2 seconds in the future, i.e. effectively
-- uncached and unminified. Acceptable as a stop-gap, not as a permanent
-- production setting. Reverse with 05-rollback.sql.
--
-- This does NOT remove the "SpaceTheme already initialized" warning:
-- both the source and the build contain the self-initialisation.
-- Purge caches afterwards (README, step 3).
-- =====================================================================

START TRANSACTION;

UPDATE mdl_config SET value = '0' WHERE name = 'cachejs';

INSERT INTO mdl_config (name, value)
SELECT 'cachejs', '0' FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM mdl_config WHERE name = 'cachejs');

COMMIT;

SELECT name, value FROM mdl_config WHERE name = 'cachejs';
