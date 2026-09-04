-- =====================================================================
-- theme_iomadmoon database fixes: 07-remove-moremenu-toggle-additionalhtml.sql
-- ---------------------------------------------------------------------
-- Removes exactly the block that 06 added (between its start/end
-- markers) and leaves any other Additional HTML footer content alone.
-- Purge caches afterwards (README, step 3).
-- =====================================================================

START TRANSACTION;

UPDATE mdl_config
SET value = TRIM(CONCAT(
    SUBSTRING_INDEX(value, '<!-- iomadmoon-moremenu-fix:start -->', 1),
    SUBSTRING_INDEX(value, '<!-- iomadmoon-moremenu-fix:end -->', -1)
))
WHERE name = 'additionalhtmlfooter'
  AND value LIKE '%iomadmoon-moremenu-fix:start%'
  AND value LIKE '%iomadmoon-moremenu-fix:end%';

COMMIT;

SELECT name, OCTET_LENGTH(value) AS bytes,
       value LIKE '%iomadmoon-moremenu-fix:start%' AS fix_present
FROM mdl_config WHERE name = 'additionalhtmlfooter';
