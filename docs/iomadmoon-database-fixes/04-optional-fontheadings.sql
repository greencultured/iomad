-- =====================================================================
-- theme_iomadmoon database fixes: 04-optional-fontheadings.sql
-- ---------------------------------------------------------------------
-- OPTIONAL. Only if headings render in the wrong font family.
--
-- theme_iomadmoon/fontheadings is empty in the database, so lib.php's
-- SCSS mapping ('fontheadings' => ['fontheadings']) emits no
-- $fontheadings variable and the theme's SCSS default applies. Setting
-- it to the same family as fontbody makes headings explicitly Poppins,
-- which the stored googlefonturl already loads (weights 400/500/700).
--
-- The admin form would call theme_reset_all_caches() on save; this
-- script bumps themerev the same way. Purge caches afterwards
-- (README, step 3). Reverse with 05-rollback.sql.
-- =====================================================================

START TRANSACTION;

UPDATE mdl_config_plugins
SET value = '''Poppins'', sans-serif'
WHERE plugin = 'theme_iomadmoon' AND name = 'fontheadings';

INSERT INTO mdl_config_plugins (plugin, name, value)
SELECT 'theme_iomadmoon', 'fontheadings', '''Poppins'', sans-serif' FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM mdl_config_plugins WHERE plugin = 'theme_iomadmoon' AND name = 'fontheadings'
);

UPDATE mdl_config
SET value = CASE
    WHEN CAST(value AS SIGNED) >= UNIX_TIMESTAMP()
     AND CAST(value AS SIGNED) - UNIX_TIMESTAMP() < 3600
    THEN CAST(value AS SIGNED) + 1
    ELSE UNIX_TIMESTAMP()
END
WHERE name = 'themerev';

COMMIT;

SELECT plugin, name, QUOTE(value) AS value
FROM mdl_config_plugins
WHERE plugin = 'theme_iomadmoon' AND name IN ('fontbody', 'fontheadings', 'googlefonturl')
ORDER BY name;
