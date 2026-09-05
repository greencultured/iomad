-- =====================================================================
-- theme_iomadmoon database fixes: 09-rollback-theme-switch.sql
-- ---------------------------------------------------------------------
-- Reverses 08-lastresort-switch-theme-to-iomadboost.sql.
--
-- Exact only if, before the switch, no row was already 'iomadboost'
-- (check the 01-verify.sql snapshot taken before step 06: user_theme,
-- company_theme). If some were, replay the mysqldump backups from
-- README step 0 instead of running this.
-- Afterwards: purge caches AND kill sessions (README).
-- =====================================================================

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

UPDATE mdl_config SET value = 'iomadmoon' WHERE name = 'theme' AND value = 'iomadboost';

SET @sql := CONCAT('UPDATE ', @companytable,
                   ' SET theme = ''iomadmoon'' WHERE theme = ''iomadboost''');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

UPDATE mdl_user              SET theme = 'iomadmoon' WHERE theme = 'iomadboost';
UPDATE mdl_course            SET theme = 'iomadmoon' WHERE theme = 'iomadboost';
UPDATE mdl_course_categories SET theme = 'iomadmoon' WHERE theme = 'iomadboost';
UPDATE mdl_cohort            SET theme = 'iomadmoon' WHERE theme = 'iomadboost';

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

SELECT name, value FROM mdl_config WHERE name = 'theme';
