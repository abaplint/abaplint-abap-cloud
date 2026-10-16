# Anomalies

Unexpected things found while working on [PLAN.md](PLAN.md). Add an entry when something behaves differently from what you expected, differs from the classic repository or the released SAP API, or needs a workaround. Update the status when it's resolved.

Status: `open`, `workaround` (with a pointer to the workaround), `fixed` (with a link to the fix), or `accepted` (with the reason).

## Generator and tooling

### Syntax check uses the Normal language version, not Cloud
- **Where:** [abaplint.jsonc](abaplint.jsonc), `syntax.version`
- **What:** `"release": "open-abap", "language": "Normal"`, with dependencies on open-abap-core and open-abap-gui. Code that isn't released for ABAP Cloud passes lint.
- **Impact:** Lint can't show that `src/generated` is cloud compatible.
- **Status:** workaround for the new code: [abaplint-cloud.jsonc](abaplint-cloud.jsonc) (`npm run lint:cloud`) checks `src/*` and `src/checks` with the Cloud version, using `src/generated` only as a dependency. Open for `src/generated`, see the next entry.

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
