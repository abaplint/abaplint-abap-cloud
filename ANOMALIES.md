# Anomalies

Unexpected things found while working on [PLAN.md](PLAN.md). Add an entry when something behaves differently from what you expected, differs from the classic repository or the released SAP API, or needs a workaround. Update the status when it's resolved.

Status: `open`, `workaround` (with a pointer to the workaround), `fixed` (with a link to the fix), or `accepted` (with the reason).

## Generator and tooling

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
