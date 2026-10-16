# Anomalies

Unexpected things found while working on [PLAN.md](PLAN.md). Add an entry when something behaves differently from what you expected, differs from the classic repository or the released SAP API, or needs a workaround. Update the status when it's resolved.

Status: `open`, `workaround` (with a pointer to the workaround), `fixed` (with a link to the fix), or `accepted` (with the reason).

## Generator and tooling

### Syntax check uses the Normal language version, not Cloud
- **Where:** [abaplint.jsonc](abaplint.jsonc), `syntax.version`
- **What:** `"release": "open-abap", "language": "Normal"`, with dependencies on open-abap-core and open-abap-gui. Code that isn't released for ABAP Cloud passes lint.
- **Impact:** Lint can't show that `src/generated` is cloud compatible.
- **Status:** workaround for the new code: [abaplint-cloud.jsonc](abaplint-cloud.jsonc) (`npm run lint:cloud`) checks `src/*` and `src/checks` with the Cloud version, using `src/generated` only as a dependency. Open for `src/generated`, see the next entry.

### The transpiled rules may not compile as ABAP Cloud
- **Where:** `src/generated`
- **What:** The checks call the transpiled rules, so they must compile as ABAP Cloud too. Linting `src/generated` with the Cloud version (`parser_error` and `check_syntax`) finds one statement: `GET RUN TIME FIELD` in `zlnt_runtime_tele_970d5104e5f4=>now`, which isn't allowed in ABAP Cloud. abaplint doesn't know which SAP APIs are released, so the lint can't show whether the generated code only calls released ones. `cl_abap_message_digest` (one use, in `zlnt_runtime_stri_248d3505915c`) needs its release state checked.
- **Impact:** The checks can't be activated on an ABAP Cloud system until `GET RUN TIME` is replaced.
- **Status:** open, best fixed in ABAPiti. The unreleased `cl_abap_conv_out_ce` and `cl_abap_conv_in_ce` (about 600 uses) are worked around by [scripts/replace-conv.mjs](scripts/replace-conv.mjs), which runs after ABAPiti and rewrites them to `cl_abap_conv_codepage`.

### The transpiler runtime removes trailing whitespace for WIDTH
- **Where:** `@abaplint/runtime`, `template_formatting.js`
- **What:** `|{ ch WIDTH = 1 }|` uses JavaScript `trimEnd()`, which removes trailing newlines and tabs as well as blanks, for strings too. ABAP only removes trailing blanks, and only of c fields. A newline became a blank, the lexer saw one long line, and a unit test failed. Tested in the transpiler: a newline or tab in `c LENGTH 1` comes back as `' '`. `` `a` && newline `` as a string comes back as `'a'`, and `` `a ` `` as a string also comes back as `'a'`. Without `WIDTH`, all of these are correct.
- **Status:** workaround: `replace-conv.mjs` uses `COND string( WHEN ch IS INITIAL THEN ` ` ELSE ch )`. Should be fixed in the transpiler.

### Code point conversions are untested on a real system
- **Where:** [scripts/replace-conv.mjs](scripts/replace-conv.mjs)
- **What:** The rewrite uses `cl_abap_conv_codepage` with `UTF-16LE` for the converters (as before, encoding 4103) and `UTF-16BE` to turn a code point into a character. open-abap-core supports `UTF-16BE` only in `create_in`, which is why `create_out` uses `UTF-16LE` and adds up the two bytes. Not verified on SAP: whether `UTF-16BE` decoding keeps U+FEFF (`uccpi( 65279 )`, 37 uses) or drops it as a byte order mark.
- **Status:** open

### A generated rule class uses the hand-written class prefix
- **Where:** `src/generated/zcl_lnt_atc_check_category.clas.abap`
- **What:** The transpiled abaplint rule `atc_check_category` uses the `zcl_lnt_atc_*` prefix of the hand-written classes (`zcl_lnt_atc_check`, `zcl_lnt_atc_meta_data`, `zcl_lnt_atc_source_reader`).
- **Status:** workaround: `checks.mjs` fails if a hand-written name also exists in `src/generated`.

### abaplint's Cloud version rejects programs, so the checks use v758
- **Where:** `zcl_lnt_utils=>get_config`
- **What:** PLAN.md suggested `"version": "Cloud"` for the configuration the rules run with. With it, `REPORT` and `WRITE` are parser errors, so every PROG and FUGR object, and every class using classic statements in a Standard ABAP system, would be reported.
- **Status:** accepted. It stays `v758`, as in classic. Revisit if the checks should only run on ABAP Cloud objects.

### The transpiler rejects the ATC object types
- **Where:** [abap_transpile.json](abap_transpile.json)
- **What:** `npm run unit` failed with `allowed_object_types, Object type CHKO not allowed` (also CHKC and CHKV). abaplint itself accepts the JSON files.
- **Status:** workaround: `exclude_filter` for `.chko.json`, `.chkc.json` and `.chkv.json` in `abap_transpile.json`.

### 25 of 140 single-file rules are not generated
- **Where:** `skip` in [scripts/checks.mjs](scripts/checks.mjs)
- **What:** Classic generates 140 checks; this repo generates 115. The source is rebuilt from tokens, so rules that need comments, pragmas or the original identifier case would report false positives. Rules for CDS, tables and number ranges never get their objects. Rules that look for tabs, trailing spaces, CRLF or spaces before `.` and `:` can never report on rebuilt source. The script prints the skipped rules with reasons.
- **Status:** accepted until Phase 0 shows what the code provider really returns.

## Assumptions about the released API, not yet checked (PLAN.md, Phase 0)

The source reader was written and tested against hand-built statements. Each assumption below is a constant or a single place in [zcl_lnt_atc_source_reader](src/zcl_lnt_atc_source_reader.clas.abap). Check them on a real system and update this list.

- **Token columns start at 0**, as in `SCAN ABAP-SOURCE` (`c_first_column`). ATC finding columns are assumed to use the same base. The thfiedler sample reports column 1 for the start of a line, which may mean they are 1-based.
- **Lexemes are upper case** except literals, as in `SCAN`. That's why `keyword_case` is skipped. If lexemes keep their case, it and naming rules give better results.
- **Chained statements** come as one statement per part, with the shared tokens before the colon repeated at the same positions. There are no tokens for `:` or `,`.
- **The class pool statements** (`ENDCLASS` of the definition, `CLASS ... IMPLEMENTATION`, the final `ENDCLASS`) are not usable, so they are added and left unmapped. Statements of the `CP` include are ignored.
- **`get_procedures`** returns every statement of the compilation unit, across `DECL`, `METH` and the other procedure kinds. Statements returned twice are dropped.
- **Pseudo comments** come as `CI_SUBRC`, `#EC CI_SUBRC` or `"#EC CI_SUBRC`. All three are accepted. Pragmas are not in the tokens.
- **The finding location** is the include as a `PROG` object, as in the thfiedler sample.
- **ATC accepts a pseudo comment** in `get_finding_code_infos` without the `CI_` prefix rule that code-pal follows. Only `check_subrc` (`CI_SUBRC`) has one today.

## Behaviour kept from classic, to revisit for ATC

### Unsupported ABAPiti paths still raise
- **Where:** `zcl_lnt_utils=>run_rule`
- **What:** `zlnt_exception_un_5f2d02892fe8` (a `cx_no_check`) is passed on, as in classic, and leaves `if_ci_atc_check~run`. How ATC reports an exception from a check is untested.
- **Status:** open

## open-abap-ci stubs

### `cl_ci_atc_data_provider` is not FINAL CREATE PRIVATE
- **Where:** [open-abap-ci `src/cloud/cl_ci_atc_data_provider.clas.abap`](https://github.com/open-abap/open-abap-ci/blob/main/src/cloud/cl_ci_atc_data_provider.clas.abap)
- **What:** The released class is `FINAL CREATE PRIVATE`; the stub is neither.
- **Impact:** Test code that subclasses or creates it would lint and run here but not compile on a real system.
- **Status:** workaround: the tests inject `zif_lnt_source_reader` with `zcl_lnt_utils=>set_source_reader( )` and pass an initial data provider. Should still be fixed in open-abap-ci.

### `cl_ci_atc_data_provider` methods are not implemented
- **Where:** same file
- **What:** `get_code_provider( )` and `main_program_from_comp_unit( )` return initial values (`" todo`). `get_checked_destination( )` is commented out because `if_rfc_dest` is missing.
- **Status:** open. Not needed by the tests.

### `cl_ci_atc_assistant_factory` methods are not implemented
- **Where:** [open-abap-ci `src/cloud/cl_ci_atc_assistant_factory.clas.abap`](https://github.com/open-abap/open-abap-ci/blob/main/src/cloud/cl_ci_atc_assistant_factory.clas.abap)
- **What:** All methods return initial values.
- **Impact:** None while quick fixes and finding details are out of scope.
- **Status:** accepted

### Stub methods raise `cx_static_check` instead of the released exceptions
- **Where:** open-abap-ci `if_ci_atc_check~set_attributes`, `if_ci_atc_source_code_provider~get_procedures` and `~get_called_procedure`
- **What:** The released interfaces (checked against [abapedia steampunk-2305-api](https://github.com/abapedia/steampunk-2305-api)) raise `cx_ci_atc_check_invalid_attr`, `cx_ci_atc_invalid_comp_unit` and `cx_ci_atc_token_no_call`. open-abap-ci doesn't have these classes. Released, they inherit from `cx_dynamic_check`, not `cx_static_check`, so code that catches only `cx_static_check` passes here but misses the real exception. Otherwise the three interfaces match.
- **Status:** workaround: `zcl_lnt_atc_source_reader` catches `cx_root`. Should be fixed in open-abap-ci by adding the exception classes.
