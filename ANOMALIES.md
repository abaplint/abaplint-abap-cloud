# Anomalies

Unexpected things found while working on [PLAN.md](PLAN.md). Add an entry when something behaves differently from what you expected, differs from the classic repository or the released SAP API, or needs a workaround. Update the status when it's resolved.

Status: `open`, `workaround` (with a pointer to the workaround), `fixed` (with a link to the fix), or `accepted` (with the reason).

## Generator and tooling

### ABAPiti output declares strings differently than in the classic repository
- **Where:** `src/generated/*.clas.abap`, `get_metadata` methods
- **What:** Strings are written as `DATA(t3) = CONV string( |abapdoc| ).`. The classic repo's `scripts/checks.mjs` expects `DATA(t3) = |abapdoc|.`, so its regexes find no rules here.
- **Impact:** The ported script must accept both forms (PLAN.md, Phase 1, step 1).
- **Status:** open. It's unclear whether this comes from a different ABAPiti release or different options.

### abapGit XML written without a byte order mark
- **Where:** [scripts/abapgit-xml.mjs](scripts/abapgit-xml.mjs)
- **What:** The XML template has no BOM, but `xml_bom` is enabled in [abaplint.jsonc](abaplint.jsonc). The classic `checks.mjs` writes a BOM to satisfy that rule.
- **Impact:** Possibly fixed later by `abaplint --fix` in `regenerate`; not verified.
- **Status:** open

### package.json still names the classic package
- **Where:** [package.json](package.json)
- **What:** `name` is `@abaplint/abaplint-abap-classic`, and `description` says "ABAPiti transpilation experiments".
- **Status:** open

### Syntax check uses the Normal language version, not Cloud
- **Where:** [abaplint.jsonc](abaplint.jsonc), `syntax.version`
- **What:** `"release": "open-abap", "language": "Normal"`, with dependencies on open-abap-core and open-abap-gui. Code that isn't released for ABAP Cloud passes lint.
- **Impact:** Lint can't show that `src/generated` or the new checks are cloud compatible (PLAN.md, "Out of scope, but needed before Phase 4").
- **Status:** open

### A generated rule class uses the planned hand-written class prefix
- **Where:** `src/generated/zcl_lnt_atc_check_category.clas.abap`
- **What:** The transpiled abaplint rule `atc_check_category` uses the `zcl_lnt_atc_*` prefix planned for the hand-written classes (`zcl_lnt_atc_check`, `zcl_lnt_atc_meta_data`, `zcl_lnt_atc_source_reader`).
- **Impact:** Some future rule could get the same name as a hand-written class. The script will fail on collisions (PLAN.md, Phase 1, step 8).
- **Status:** workaround planned

## open-abap-ci stubs

### `cl_ci_atc_data_provider` is not FINAL CREATE PRIVATE
- **Where:** [open-abap-ci `src/cloud/cl_ci_atc_data_provider.clas.abap`](https://github.com/open-abap/open-abap-ci/blob/main/src/cloud/cl_ci_atc_data_provider.clas.abap)
- **What:** The released class is `FINAL CREATE PRIVATE`; the stub is neither.
- **Impact:** Test code that subclasses or creates it would lint and run here but not compile on a real system.
- **Status:** open. Fix in open-abap-ci, and inject `zif_lnt_source_reader` in tests instead.

### `cl_ci_atc_data_provider` methods are not implemented
- **Where:** same file
- **What:** `get_code_provider( )` and `main_program_from_comp_unit( )` return initial values (`" todo`). `get_checked_destination( )` is commented out because `if_rfc_dest` is missing.
- **Status:** open

### `cl_ci_atc_assistant_factory` methods are not implemented
- **Where:** [open-abap-ci `src/cloud/cl_ci_atc_assistant_factory.clas.abap`](https://github.com/open-abap/open-abap-ci/blob/main/src/cloud/cl_ci_atc_assistant_factory.clas.abap)
- **What:** All methods return initial values.
- **Impact:** None while quick fixes and finding details are out of scope.
- **Status:** accepted
