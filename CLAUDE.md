# IOMAD working notes

## Company-scoped values are keyed by ID, not by name

Everywhere IOMAD resolves a company-scoped thing dynamically, the key is the
**numeric id**, never the display name. That holds for company scoping in
config (`<setting>_<companyid>`), for department references, and for the
per-company profile-field menus that feed `mdl_company.departmentprofileid`.

Consequences to keep in mind:

- A per-company department menu stores `mdl_department.id` values in
  `user_info_field.param1`, one option per line, with the company's
  `parent = 0` node first and also set as `defaultdata`.
- Any lookup that resolves such a stored value must key on
  `department.id`, not `department.name`.

## Live server vs. this checkout — they are different versions

The production server (`ip-10-0-12-184`, `/var/www/html/moodle`, DB `iomad`,
prefix `mdl_`) runs **IOMAD 4.5.13**. This checkout is **IOMAD 5.1.6**.
Never cite a line number from this tree as though it applied to the server.

Table and column names differ between the two:

| 4.5.13 (live)            | 5.1.6 (this tree)                    |
|--------------------------|--------------------------------------|
| `company`                | `local_iomad_companies`              |
| `company_users`          | `local_iomad_company_users`          |
| `department`             | `local_iomad_company_departments`    |
| `company.profileid`      | `local_iomad_companies.profilecategoryid` |
| `department.company`     | `..._departments.companyid`          |
| `department.parent`      | `..._departments.parent`             |

Live class files are under `local/iomad/lib/`; here they are under
`local/iomad/classes/`.

## Database access on the live server

Read credentials out of `config.php` as text. Do **not** `require` it — that
bootstraps Moodle and emits output, which corrupts a generated `my.cnf`.

```bash
cd /var/www/html/moodle
DBU=$(grep -oP "dbuser\s*=\s*'\K[^']+" config.php)
DBP=$(grep -oP "dbpass\s*=\s*'\K[^']+" config.php)
DBH=$(grep -oP "dbhost\s*=\s*'\K[^']+" config.php)
DBN=$(grep -oP "dbname\s*=\s*'\K[^']+" config.php)
printf '[client]\nuser=%s\npassword="%s"\nhost=%s\ndatabase=%s\n' \
  "$DBU" "$DBP" "$DBH" "$DBN" > /root/.my.iomad.cnf
chmod 600 /root/.my.iomad.cnf
```

## Gotchas that have bitten

- `!empty('0')` is **false**. A company setting legitimately set to `0` is
  dropped by an `!empty()` guard.
- MySQL `GROUP_CONCAT(... SEPARATOR ...)` takes a **string literal** only.
  `SEPARATOR '\n'` works; `SEPARATOR CHAR(10)` is a syntax error.
- `TERMINATED` and `STORED` are MySQL reserved words; backtick them.
- A core `menu` profile field requires **at least 2 options**
  (`user/profile/field/menu/define.class.php`). A single-option menu stores
  and renders fine but cannot be re-saved from the profile-field admin form.
- `user_info_data` has `UNIQUE (userid, fieldid)` — one row per pair.
