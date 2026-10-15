# Plan: generate ABAP Cloud ATC checks for abaplint rules

Port [abaplint-abap-classic/scripts/checks.mjs](https://github.com/abaplint/abaplint-abap-classic/blob/main/scripts/checks.mjs) to this repository. The design stays the same: discover the single file rules in `src/generated` and write one thin wrapper class per rule into `src/checks`. What changes is the wrapper and the runtime support around it. They must use only APIs released for ABAP Cloud: `IF_CI_ATC_CHECK` instead of `CL_CI_TEST_ROOT`.

## Classic design, for reference

```
src/generated/zcl_lnt_<rule>   transpiled abaplint rule (input)
        |
scripts/checks.mjs             finds SingleFile rules, reads key + title
        |
src/checks/zcl_lnc_<rule>      INHERITING FROM cl_ci_test_root
        |                      run( ) -> zcl_lnt_utils=>run_rule( ) -> inform( )
src/zcl_lnt_utils              registry cache, config, finding mapping
src/zcl_lnt_source_reader      reads includes, builds abapGit style files + line map
src/zcl_lnt_category           cl_ci_category_root
```

## Target design

```
scripts/checks.mjs             same discovery; new templates; also writes CHKO/CHKC/CHKV json
        |
src/checks/zcl_lnc_<rule>      FINAL, INHERITING FROM zcl_lnt_atc_check
        |                      constructor passes key/title/pseudo comment; create_rule( ) returns NEW zcl_lnt_<rule>( )
src/checks/zlnc_<rule>.chko.json   ATC check object, implementingClass = ZCL_LNC_<RULE>
src/checks/zlnc_abaplint.chkc.json ATC check category
src/checks/zlnc_abaplint.chkv.json check variant with all generated checks (optional)

src/zcl_lnt_atc_check          ABSTRACT, INTERFACES if_ci_atc_check (hand written)
src/zcl_lnt_atc_meta_data      INTERFACES if_ci_atc_check_meta_data (hand written)
src/zcl_lnt_utils              cloud port of the classic class
src/zif_lnt_source_reader      unchanged interface
src/zcl_lnt_atc_source_reader  builds abapGit style files from if_ci_atc_source_code_provider
```

Record anything unexpected found while working on this plan in [ANOMALIES.md](ANOMALIES.md): generator output, stubs, tooling, or differences from the classic repository. That keeps this plan about the work itself.

The shared logic goes in a hand written abstract base class, so each generated class stays a few lines long and the script stays simple. This differs from classic, which put everything in the generated class plus static utils. A base class is needed here because `IF_CI_ATC_CHECK` has five methods, and every check needs a separate meta data object. `/cc4a/check_meta_data` in [SAP/code-pal-for-abap-cloud](https://github.com/SAP/code-pal-for-abap-cloud/tree/main/src/core) is a good model for the meta data class.

## Phase 0: spike on reading the source (blocking)

ABAP Cloud has no released API that returns the raw source of a class or program:

- `cl_ci_atc_data_provider->get_code_provider( )` returns `if_ci_atc_source_code_provider`. That gives procedures, statements and tokens. Each token has a `lexeme` and a `position` (line, column), and each statement has an `include` and `pseudo_comments`. It gives no comments and no raw lines. It does work for remote checked systems.
- XCO (`if_xco_clas_i_method_content->get_source( )`) gives method bodies only, not definitions or local classes, and only for the local system.

Proposed approach: rebuild each include by placing every token's lexeme at its original line and column. Put the statement's pseudo comments back as `"#EC <name>` at the end of the statement line. Then assemble the abapGit style files the same way the classic `zcl_lnt_source_reader` does. That logic is ported from `ZCL_ABAPGIT_OO_SERIALIZER`, and the include structure (CU/CO/CI/CCDEF/CCIMP/CCAU/CMnnn) is the same.

Questions the spike must answer on a real BTP ABAP environment or S/4HANA Cloud system:

1. Do `get_procedures( )` and `DECL` procedures cover every statement, including `CLASS ... DEFINITION/IMPLEMENTATION`, `ENDCLASS` and section headers? Or are some statements missing?
2. Are lexemes kept as written (keyword case, string templates, literals), or normalized?
3. For a chained statement (`DATA: a, b.`), are the colon and commas present as tokens with positions?
4. Are ABAP Doc (`"!`) and other comments ever visible? We assume not.
5. Can we name each `CMnnn` include's method, or do we have to read it from the `METHOD` statement?

From the answers, decide:

- **Rule exclusion list.** Rules that depend on comments, whitespace inside statements, or keyword case can't give correct results from rebuilt source. The script needs a hard-coded `skip` list with a reason for each rule, for example `abapdoc`, `comment_*`, `keyword_case`, `whitespace_end`, `indentation` and `line_length` (to verify). Skipped rules are logged, the same way the classic script logs filtered rules.
- **Fallback.** If rebuilding turns out unusable, try XCO for local-only checks (`checkType` not remote enabled) and reduce the scope to rules that only look at method bodies.

`zif_lnt_source_reader` stays the boundary, so the base check and the tests don't depend on which approach wins.

## Phase 1: update the generator script (`scripts/checks.mjs`)

Copy the classic script, then change:

1. **Parsing the transpiled output.** This repo's ABAPiti output declares strings as `DATA(t3) = CONV string( |abapdoc| ).` followed by `t2 = t3.`, not `DATA(t3) = |abapdoc|.`. Extend the regexes in `stringValue` to accept both forms, and the `tN = tN && |...|.` continuation lines as well. Detect `SingleFile` as `|SingleFile|` anywhere in `get_metadata`. Today 143 generated classes contain it.
2. **Also read `i_pseudo_comment`**, so the ATC finding code can carry the rule's pseudo comment (`pseudo_comment` in `get_finding_code_infos`, as code-pal does). Check how ABAPiti passes it, since it may be wrapped in an optional (`zlnt_runtime_opti_*`).
3. **Keep the filters**: not abstract, implements `zif_lnt_rule` (following superclasses), constructor without parameters, `zcl_lnt_` prefix. Add the Phase 0 `skip` list.
4. **Names.** The class is `zcl_lnc_<rule>`, max 30 characters, already guaranteed by the `zcl_lnt_` input. The CHKO is `zlnc_<key>` in upper case, also max 30 characters. Truncate and fail the script on collisions. Rule keys like `align_type_expressions` fit, but check all of them.
5. **Templates.** See the generated class below, plus:
   - `zcl_lnc_<rule>.clas.xml`, the same as classic.
   - `zlnc_<key>.chko.json`:
     ```json
     {
       "formatVersion": "1",
       "header": {"description": "<key>: <title>", "originalLanguage": "en", "abapLanguageVersion": "cloudDevelopment"},
       "category": "ZLNC_ABAPLINT",
       "implementingClass": "ZCL_LNC_<RULE>",
       "checkType": "remoteEnabled"
     }
     ```
     The format is copied from code-pal's `(cc4a)prefer_is_not.chko.json`. Description max 60 characters, truncated as in classic.
   - Written once: `zlnc_abaplint.chkc.json` (category) and `zlnc_abaplint.chkv.json`, a variant with all `selectedChecks`. Both are regenerated every run and added to the `keep` handling like `package.devc.xml`.
6. **Cleanup.** Clear the output folder except `package.devc.xml`, as classic does.
7. **Byte order mark.** Write the XML with a BOM, because `xml_bom` is on in `abaplint.jsonc`. JSON is written without a BOM.
8. **Name collisions.** Fail if a hand-written class name (`zcl_lnt_atc_check`, `zcl_lnt_utils`, ...) also exists in `src/generated`. `zcl_lnt_atc_check_category` already exists there as a transpiled rule.
9. **package.json.** Add `node scripts/checks.mjs` back to `regenerate` between `abapgit-xml.mjs` and `abaplint --fix`.

Generated class:

```abap
* abaplint rule <key>, generated by scripts/checks.mjs
CLASS zcl_lnc_<rule> DEFINITION PUBLIC FINAL INHERITING FROM zcl_lnt_atc_check CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS constructor.
  PROTECTED SECTION.
    METHODS create_rule REDEFINITION.
ENDCLASS.

CLASS zcl_lnc_<rule> IMPLEMENTATION.
  METHOD constructor.
    super->constructor(
      iv_key            = `<key>`
      iv_title          = `<title>`
      iv_pseudo_comment = `<pseudo comment>` ).
  ENDMETHOD.

  METHOD create_rule.
    ri_rule = NEW zcl_lnt_<rule>( ).
  ENDMETHOD.
ENDCLASS.
```

## Phase 2: hand-written runtime classes (`src/`)

### `zcl_lnt_atc_check` (abstract, `INTERFACES if_ci_atc_check`)
- `constructor( iv_key, iv_title, iv_pseudo_comment )`; `create_rule( )` is abstract and returns `zif_lnt_rule`.
- `get_meta_data`: `NEW zcl_lnt_atc_meta_data( ... )`.
- `set_assistant_factory`: stores the factory. Quick fixes are not planned.
- `verify_prerequisites`: returns nothing.
- `set_attributes`: no attributes in the first version. Later: the abaplint syntax version, or a JSON rule configuration.
- `run( object, data_provider )`:
  1. Create the reader `NEW zcl_lnt_atc_source_reader( data_provider->get_code_provider( ) )`, unless a test double was injected.
  2. `zcl_lnt_utils=>run_rule( io_rule = create_rule( ) ... )`.
  3. Map each finding to `if_ci_atc_check=>ty_finding`: `code` from the severity (see below); `location-object` = `VALUE #( type = 'PROG' name = <include> )`; `location-position` = line and column, with column clamped to `int1`, max 255; `parameters-param_1` = message.

### `zcl_lnt_atc_meta_data` (`INTERFACES if_ci_atc_check_meta_data`)
- `get_description`: `abaplint - <title>`.
- `get_checked_object_types`: `PROG`, `CLAS`, `INTF`, `FUGR`, from `zcl_lnt_utils=>object_types( )`.
- `get_finding_code_infos`: one code per severity, because ATC sets the severity per finding code:

  | code | severity | text |
  |---|---|---|
  | `ERROR` | `finding_severities-error` | `&1` |
  | `WARNING` | `finding_severities-warning` | `&1` |
  | `INFO` | `finding_severities-note` | `&1` |
  | `DUMP` | `finding_severities-error` | `abaplint failed: &1` |

  All codes carry the rule's pseudo comment, if it has one.
- `is_remote_enabled`: `abap_true`, assuming the Phase 0 token approach. `uses_checksums`: `abap_false` at first.
- `get_attributes` and `get_quickfix_code_infos`: empty.

### `zcl_lnt_utils` (cloud port)
Keep `run_rule`, the registry cache, `get_config`, `find_object`, `to_findings` and `map_position`. Change:
- `ty_finding-kind`: an own enum or constants instead of `cl_ci_test_root=>c_*`. `code` uses `if_ci_atc_check=>ty_finding_code` instead of `sci_errc`.
- `include`: `if_ci_atc_source_code_provider=>ty_include` instead of `progname`. `object_types`: `if_ci_atc_check=>ty_object-type` instead of `tadir-object`.
- Remove `add_scimessages` and `display_documentation`. There is no SAP GUI in cloud; the rule URL `https://rules.abaplint.org/<key>/` can be put in the finding details later.
- Config: set `syntax.version` to `"Cloud"` instead of `"v758"`. Verify this doesn't break rules that read the version.

### `zcl_lnt_atc_source_reader` (`INTERFACES zif_lnt_source_reader`)
- Created with the code provider. `read( iv_object_type, iv_object_name )` turns the object into a compilation unit (`object_to_comp_unit`), calls `get_procedures`, groups statements by `include`, and rebuilds each include from the token positions.
- Assembles the abapGit files and the line map with the same logic as the classic `zcl_lnt_source_reader`, minus the classic reads (`READ REPORT` and similar). The line map maps a file row to include + line, as before.

## Phase 3: tests

- **Script.** Add `npm run checks` (or run it as part of `regenerate`) and log how many checks were written and which rules were skipped and why. Compare the list with classic: classic writes 140 checks. Any difference should be explained by the parsing change or the skip list.
- **ABAP unit tests (`npm run unit`, transpiled).** open-abap-ci already has stubs for `if_ci_atc_check`, `if_ci_atc_check_meta_data`, `if_ci_atc_source_code_provider` and `cl_ci_atc_data_provider`.
  - `zcl_lnt_atc_source_reader`: a fake `if_ci_atc_source_code_provider` with hand-built statements and tokens. Assert on the rebuilt files and line map: class sections, method includes, chained statements, pseudo comments.
  - `zcl_lnt_atc_check`: inject a fake `zif_lnt_source_reader` through `zcl_lnt_utils=>set_source_reader( )`, as classic does. Run two or three generated checks against known source and assert code, include, line and column.
  - Meta data: every generated check returns a description, object types and the four finding codes.
- **open-abap-ci may need updates first.** See the next section.
- **Lint.** `abaplint` must pass on `src/checks` and the hand-written classes. Also run them once with `"language": "Cloud"`, to catch non-released APIs that the `open-abap` syntax version would accept.

## Note: open-abap-ci may need updates

The lint and unit tests here run against the stubs in [open-abap/open-abap-ci `src/cloud`](https://github.com/open-abap/open-abap-ci/tree/main/src/cloud), not the real SAP classes. Those stubs are incomplete and differ from the released APIs in places. So some of this work may need pull requests to open-abap-ci before it lints or runs here. Known so far:

- `cl_ci_atc_data_provider` is not `FINAL CREATE PRIVATE`, unlike the released class. Code that subclasses or instantiates it passes locally but won't compile on a real system. Tests must use our own `zif_lnt_source_reader` injection, not a data provider subclass.
- `cl_ci_atc_data_provider->get_code_provider( )` and `main_program_from_comp_unit( )` return initial values (`" todo`). `get_checked_destination( )` is commented out because `if_rfc_dest` is missing.
- `cl_ci_atc_assistant_factory` methods all return initial values. That's fine while quick fixes and finding details aren't used.
- Compare `if_ci_atc_check`, `if_ci_atc_check_meta_data` and `if_ci_atc_source_code_provider` with the released versions (for example [abapedia steampunk-2305-api](https://github.com/abapedia/steampunk-2305-api)). Fix any differences in types, enums or method signatures in open-abap-ci, not with workarounds here.

Record every stub gap found in [ANOMALIES.md](ANOMALIES.md) and link the open-abap-ci pull request that fixes it.

## Phase 4: real system test

Pull the package with abapGit into a BTP ABAP environment trial or S/4HANA Cloud. Check that the CHKO, CHKC and CHKV objects import. Run the variant in ADT on a test package, and confirm the findings, navigation to the right line, and that pseudo comments suppress findings.

## Out of scope, but needed before Phase 4

The checks call the transpiled rules in `src/generated`, so that code must also compile with ABAP Cloud language version. `abaplint.jsonc` currently checks `"language": "Normal"`, and the dependencies on open-abap-core/gui are not cloud-only. Run a separate check with `"language": "Cloud"` over `src/generated` to see the size of that work. It may need changes in ABAPiti, not here.

## Open questions

1. The Phase 0 results, which decide the skip list and whether checks can be remote enabled.
2. Naming: is `zlnc_` acceptable for CHKO/CHKC/CHKV, and should everything move to a namespace later?
3. Should the CHKV variant be generated, or left for users to build?
4. abaplint registry support for `.chko.json`, `.chkc.json` and `.chkv.json` files. Verify that `abaplint` doesn't report them as unknown, and add them to `exclude` if it does.
