import {existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync} from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const srcFolder = path.join(packageRoot, "src");
const classesFolder = path.join(srcFolder, "generated");
const checksFolder = path.join(srcFolder, "checks");
const keep = new Set(["package.devc.xml"]);
const category = "zlnc_abaplint";
const variant = "zlnc_abaplint";

// the ATC checks rebuild the source from statements and tokens, keeping the token positions, see
// zcl_lnt_atc_source_reader. Comments and pragmas are lost and identifiers may be upper case, so rules
// looking at those would report false positives, and rules for other object types never run
const skip = new Map([
  ["abapdoc", "needs comments"],
  ["align_pseudo_comments", "pseudo comments are rebuilt"],
  ["cds_association_name", "checks CDS, only ABAP source is read"],
  ["cds_comment_style", "checks CDS, only ABAP source is read"],
  ["cds_field_order", "checks CDS, only ABAP source is read"],
  ["cds_legacy_view", "checks CDS, only ABAP source is read"],
  ["cds_naming", "checks CDS, only ABAP source is read"],
  ["cds_parser_error", "checks CDS, only ABAP source is read"],
  ["check_comments", "needs comments"],
  ["commented_code", "needs comments"],
  ["contains_tab", "cannot report on rebuilt source"],
  ["empty_line_in_statement", "needs comments"],
  ["index_completely_contained", "checks tables, only ABAP source is read"],
  ["keyword_case", "needs the original case"],
  ["line_break_style", "cannot report on rebuilt source"],
  ["newline_between_methods", "needs comments"],
  ["no_comments_between_methods", "needs comments"],
  ["nrob_consistency", "checks number ranges, only ABAP source is read"],
  ["pragma_style", "needs pragmas"],
  ["sequential_blank", "needs comments"],
  ["space_before_colon", "cannot report on rebuilt source"],
  ["space_before_dot", "cannot report on rebuilt source"],
  ["unnecessary_pragma", "needs pragmas"],
  ["whitespace_end", "cannot report on rebuilt source"],
  ["wrong_abapdoc_position", "needs comments"],
]);

// hand written classes in src, a generated class with the same name would replace them
const handWritten = ["zcl_lnt_atc_check", "zcl_lnt_atc_meta_data", "zcl_lnt_atc_source_reader", "zcl_lnt_utils", "zif_lnt_source_reader"];

function escapeXml(text) {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");
}

// written with a byte order mark, as required by the xml_bom rule
function abapGitXml(serializer, values) {
  return `﻿<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="${serializer}" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
${values}
  </asx:values>
 </asx:abap>
</abapGit>
`;
}

function header(description) {
  return {description: truncate(description), originalLanguage: "en", abapLanguageVersion: "cloudDevelopment"};
}

function writeJson(filename, data) {
  writeFileSync(path.join(checksFolder, filename), JSON.stringify(data, null, 2) + "\n");
}

function truncate(text, length = 60) {
  return text.length > length ? text.substring(0, length - 3) + "..." : text;
}

function unescapeTemplate(text) {
  return text.replace(/\\(.)/g, (_, c) => ({n: "\n", r: "\r", t: "\t"})[c] ?? c);
}

function superclassOf(source) {
  return /^CLASS \S+ DEFINITION\b[^.]*\bINHERITING FROM (\S+?)[\s.]/im.exec(source)?.[1].toLowerCase();
}

function methodBody(source, method) {
  return new RegExp(`^\\s*METHOD ${method}\\.\\n([\\s\\S]*?)^\\s*ENDMETHOD\\.`, "im").exec(source)?.[1];
}

const template = "\\|((?:[^|\\\\]|\\\\.)*)\\|";

// resolves the temporary variables ABAPiti writes for a value, returns undefined if not a string:
//   DATA(t3) = |abc|.  or  DATA(t3) = CONV string( |abc| ).  plus  t3 = t3 && |def|.
//   t2 = t3.  copies, tried in order, as IF/ELSE branches assign the same variable
//   t5->value = t4.  for optional values
function stringValue(body, variable, seen = new Set()) {
  if (seen.has(variable)) {
    return undefined;
  }
  seen.add(variable);
  const start = new RegExp(`^\\s*DATA\\(${variable}\\) = (?:CONV string\\( ${template} \\)|${template})\\.$`, "m").exec(body);
  if (start) {
    let value = unescapeTemplate(start[1] ?? start[2]);
    const append = new RegExp(`^\\s*${variable} = ${variable} && ${template}\\.$`, "gm");
    for (const match of body.matchAll(append)) {
      value += unescapeTemplate(match[1]);
    }
    return value;
  }
  const optional = new RegExp(`^\\s*${variable}->value = (t\\d+)\\.$`, "m").exec(body);
  if (optional) {
    return stringValue(body, optional[1], seen);
  }
  for (const copy of body.matchAll(new RegExp(`^\\s*${variable} = (t\\d+)\\.$`, "gm"))) {
    const value = stringValue(body, copy[1], seen);
    if (value !== undefined) {
      return value;
    }
  }
  return undefined;
}

function abapLiteral(text) {
  return "`" + text.replace(/`/g, "``").replace(/\s+/g, " ").trim() + "`";
}

// "EC CI_SUBRC" becomes "CI_SUBRC", the ATC pseudo comment is written without the "#EC "
function pseudoComment(text) {
  return text === undefined ? "" : text.replace(/^"?#?EC\s+/i, "").trim();
}

if (!existsSync(classesFolder)) {
  throw new Error(`${classesFolder} does not exist, run the transpilation first`);
}

const sources = new Map();
for (const filename of readdirSync(classesFolder)) {
  const match = /^([^.]+)\.(clas|intf)\.abap$/.exec(filename);
  if (match) {
    // normalize line endings, git may check the files out with CRLF
    sources.set(match[1], readFileSync(path.join(classesFolder, filename), "utf-8").replace(/\r\n/g, "\n"));
  }
}

for (const name of handWritten) {
  if (sources.has(name)) {
    throw new Error(`${name} is both hand written in src and generated in src/generated, rename the hand written object`);
  }
}

function implementsRule(name, seen = new Set()) {
  const source = sources.get(name);
  if (source === undefined || seen.has(name)) {
    return false;
  }
  seen.add(name);
  return /^\s*INTERFACES zif_lnt_rule\.$/im.test(source) || implementsRule(superclassOf(source), seen);
}

const rules = [];
const skipped = [];
for (const [name, source] of [...sources].sort(([a], [b]) => a.localeCompare(b))) {
  const metadata = methodBody(source, "get_metadata");
  if (metadata === undefined || !metadata.includes("|SingleFile|")) {
    continue;
  }
  const call = /NEW zcl_lnt_irule_metadata\( i_key = (t\d+) i_title = (t\d+)/.exec(metadata);
  const key = call && stringValue(metadata, call[1]);
  const title = call && stringValue(metadata, call[2]);
  const pseudoCall = / i_pseudo_comment = (t\d+)/.exec(metadata);
  const pseudo = pseudoComment(pseudoCall ? stringValue(metadata, pseudoCall[1]) : undefined);
  if (key === undefined || title === undefined) {
    console.warn(`Skipping ${name}: cannot read the rule key and title`);
  } else if (/^CLASS \S+ DEFINITION\b[^.]*\bABSTRACT\b/im.test(source) || !implementsRule(name)) {
    console.warn(`Skipping ${name}: not an instantiable rule`);
  } else if (/^\s*METHODS constructor IMPORTING\b/im.test(source)) {
    console.warn(`Skipping ${name}: the constructor takes parameters`);
  } else if (!name.startsWith("zcl_lnt_")) {
    console.warn(`Skipping ${name}: unexpected class name`);
  } else if (skip.has(key)) {
    skipped.push(`${key} (${skip.get(key)})`);
  } else {
    rules.push({rule: name, check: name.replace(/^zcl_lnt_/, "zcl_lnc_"), chko: `zlnc_${key}`.substring(0, 30), key, title, pseudo});
  }
}

const unusedSkips = [...skip.keys()].filter(key => !skipped.some(text => text.startsWith(`${key} (`)));
if (unusedSkips.length > 0) {
  console.warn(`Skip list entries not matching a single file rule: ${unusedSkips.join(", ")}`);
}

const chkoNames = new Map();
for (const {chko, key} of rules) {
  if (chkoNames.has(chko)) {
    throw new Error(`ATC check name ${chko} is used for both rule ${chkoNames.get(chko)} and rule ${key}`);
  }
  chkoNames.set(chko, key);
}

mkdirSync(checksFolder, {recursive: true});
for (const filename of readdirSync(checksFolder)) {
  if (!keep.has(filename)) {
    rmSync(path.join(checksFolder, filename), {recursive: true, force: true});
  }
}
if (!existsSync(path.join(checksFolder, "package.devc.xml"))) {
  writeFileSync(path.join(checksFolder, "package.devc.xml"), abapGitXml("LCL_OBJECT_DEVC", `   <DEVC>
    <CTEXT>ATC checks for abaplint rules</CTEXT>
   </DEVC>`));
}

for (const {rule, check, chko, key, title, pseudo} of rules) {
  const descript = `${key}: ${title}`.trim();
  writeFileSync(path.join(checksFolder, `${check}.clas.abap`), `* abaplint rule ${key}, generated by scripts/checks.mjs
CLASS ${check} DEFINITION PUBLIC FINAL INHERITING FROM zcl_lnt_atc_check CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS constructor.
  PROTECTED SECTION.
    METHODS create_rule REDEFINITION.
ENDCLASS.

CLASS ${check} IMPLEMENTATION.
  METHOD constructor.
    super->constructor(
      iv_key            = ${abapLiteral(key)}
      iv_title          = ${abapLiteral(title)}
      iv_pseudo_comment = ${abapLiteral(pseudo)} ).
  ENDMETHOD.

  METHOD create_rule.
    ri_rule = NEW ${rule}( ).
  ENDMETHOD.
ENDCLASS.
`);
  writeFileSync(path.join(checksFolder, `${check}.clas.xml`), abapGitXml("LCL_OBJECT_CLAS", `   <VSEOCLASS>
    <CLSNAME>${check.toUpperCase()}</CLSNAME>
    <LANGU>E</LANGU>
    <DESCRIPT>${escapeXml(truncate(descript))}</DESCRIPT>
    <STATE>1</STATE>
    <CLSCCINCL>X</CLSCCINCL>
    <FIXPT>X</FIXPT>
    <UNICODE>X</UNICODE>
   </VSEOCLASS>`));
  writeJson(`${chko}.chko.json`, {
    formatVersion: "1",
    header: header(descript),
    category: category.toUpperCase(),
    implementingClass: check.toUpperCase(),
    checkType: "remoteEnabled",
  });
}

writeJson(`${category}.chkc.json`, {
  formatVersion: "1",
  header: header("abaplint"),
});
writeJson(`${variant}.chkv.json`, {
  formatVersion: "1",
  header: header("All abaplint checks"),
  selectedChecks: rules.map(({chko}) => ({checkName: chko.toUpperCase()})),
});

console.log(`Skipped ${skipped.length} rules: ${skipped.join(", ")}.`);
console.log(`Wrote ${rules.length} ATC checks for single file abaplint rules to ${path.relative(packageRoot, checksFolder)}.`);
