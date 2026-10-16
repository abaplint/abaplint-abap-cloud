import {existsSync, readdirSync, readFileSync, writeFileSync} from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

// Replaces cl_abap_conv_out_ce and cl_abap_conv_in_ce in the ABAPiti output with cl_abap_conv_codepage,
// the conversion API released for ABAP Cloud. Run after call-abapiti.mjs, running it twice changes nothing.
//
//   TYPE REF TO cl_abap_conv_out_ce / _in_ce             -> TYPE REF TO if_abap_conv_out / if_abap_conv_in
//   cl_abap_conv_out_ce=>create( encoding = '4103' )     -> cl_abap_conv_codepage=>create_out( codepage = `UTF-16LE` )
//   cl_abap_conv_in_ce=>create( encoding = '4103' )      -> cl_abap_conv_codepage=>create_in( codepage = `UTF-16LE` )
//   conv->convert( EXPORTING data = a IMPORTING buffer = b ).  -> b = conv->convert( |{ a WIDTH = 1 }| ).
//   conv->convert( EXPORTING input = a IMPORTING data = b ).   -> b = conv->convert( a ).
//   cl_abap_conv_in_ce=>uccpi( 8233 ), =>uccp( '2029' )  -> decodes `2029` as UTF-16BE
//   x = cl_abap_conv_in_ce=>uccpi( code ).               -> the same, via a helper of type x LENGTH 2
//   x = cl_abap_conv_out_ce=>uccpi( ch ).                -> encodes ch as UTF-16LE and adds up the two bytes
//
// "|{ a WIDTH = 1 }|" keeps a blank in a c field, which a conversion to string removes.
// Code points outside the basic multilingual plane were not supported by uccpi either.

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const classesFolder = path.join(packageRoot, "src", "generated");

const operand = "[A-Za-z_][A-Za-z0-9_]*";

function keepBlank(name) {
  return `|{ ${name} WIDTH = 1 }|`;
}

if (!existsSync(classesFolder)) {
  throw new Error(`${classesFolder} does not exist, run the transpilation first`);
}

// the helper variables are numbered per file, so they are unique within each method
function replaceSource(source, filename) {
  let counter = 0;
  const counts = {types: 0, create: 0, convert: 0, uccpiConstant: 0, uccpiIn: 0, uccpiOut: 0};

  source = source.replace(/\bTYPE REF TO cl_abap_conv_(out|in)_ce\b/gi, (_, direction) => {
    counts.types++;
    return `TYPE REF TO if_abap_conv_${direction.toLowerCase()}`;
  });

  source = source.replace(/\bcl_abap_conv_(out|in)_ce=>create\( encoding = '(\d+)' \)/gi, (match, direction, encoding) => {
    if (encoding !== "4103") {
      throw new Error(`${filename}: unexpected encoding in ${match}`);
    }
    counts.create++;
    return `cl_abap_conv_codepage=>create_${direction.toLowerCase()}( codepage = \`UTF-16LE\` )`;
  });

  source = source.replace(new RegExp(`^(\\s*)(${operand})->convert\\( EXPORTING data = (${operand}) IMPORTING buffer = (${operand}) \\)\\.$`, "gm"),
    (_, indent, converter, data, buffer) => {
      counts.convert++;
      return `${indent}${buffer} = ${converter}->convert( ${keepBlank(data)} ).`;
    });
  source = source.replace(new RegExp(`^(\\s*)(${operand})->convert\\( EXPORTING input = (${operand}) IMPORTING data = (${operand}) \\)\\.$`, "gm"),
    (_, indent, converter, input, data) => {
      counts.convert++;
      return `${indent}${data} = ${converter}->convert( ${input} ).`;
    });

  source = source.replace(/\bcl_abap_conv_in_ce=>uccpi\( (\d+) \)/gi, (match, code) => {
    const value = Number(code);
    if (value > 0xFFFF) {
      throw new Error(`${filename}: code point out of range in ${match}`);
    }
    counts.uccpiConstant++;
    const hex = value.toString(16).toUpperCase().padStart(4, "0");
    return `cl_abap_conv_codepage=>create_in( codepage = \`UTF-16BE\` )->convert( CONV xstring( \`${hex}\` ) )`;
  });

  // only as a statement, rule documentation has uccp( 'BF51' ) inside string templates
  source = source.replace(new RegExp(`^(\\s*)(${operand}) = cl_abap_conv_in_ce=>uccp\\( '([0-9A-Fa-f]{4})' \\)\\.$`, "gim"),
    (_, indent, target, hex) => {
      counts.uccpiConstant++;
      return `${indent}${target} = cl_abap_conv_codepage=>create_in( codepage = \`UTF-16BE\` )->convert( CONV xstring( \`${hex.toUpperCase()}\` ) ).`;
    });

  source = source.replace(new RegExp(`^(\\s*)(${operand}) = cl_abap_conv_in_ce=>uccpi\\( (${operand}) \\)\\.$`, "gim"),
    (_, indent, target, code) => {
      counts.uccpiIn++;
      const unit = `zlnt_conv_${++counter}`;
      return [
        `${indent}DATA ${unit} TYPE x LENGTH 2.`,
        `${indent}${unit} = ${code}.`,
        `${indent}${target} = cl_abap_conv_codepage=>create_in( codepage = \`UTF-16BE\` )->convert( CONV xstring( ${unit} ) ).`,
      ].join("\n");
    });

  source = source.replace(new RegExp(`^(\\s*)(${operand}) = cl_abap_conv_out_ce=>uccpi\\( (${operand}) \\)\\.$`, "gim"),
    (_, indent, target, character) => {
      counts.uccpiOut++;
      const bytes = `zlnt_conv_${++counter}`;
      return [
        `${indent}DATA(${bytes}) = cl_abap_conv_codepage=>create_out( codepage = \`UTF-16LE\` )->convert( ${keepBlank(character)} ).`,
        `${indent}DATA ${bytes}_low TYPE i.`,
        `${indent}${bytes}_low = ${bytes}(1).`,
        `${indent}${target} = ${bytes}+1(1).`,
        `${indent}${target} = ${target} * 256 + ${bytes}_low.`,
      ].join("\n");
    });

  // anything left must be text inside a string template, like rule documentation
  for (const line of source.split("\n")) {
    const outside = line.replace(/\|(?:[^|\\]|\\.)*\|/g, "").replace(/'[^']*'/g, "").replace(/`[^`]*`/g, "").replace(/".*$/, "");
    if (/\bcl_abap_conv_(out|in)_ce\b/i.test(outside)) {
      throw new Error(`${filename}: cannot replace "${line.trim()}"`);
    }
  }

  return {source, counts};
}

// all files are converted before any is written, so a failure leaves src/generated unchanged
const totals = {files: 0, types: 0, create: 0, convert: 0, uccpiConstant: 0, uccpiIn: 0, uccpiOut: 0};
const changed = [];
for (const filename of readdirSync(classesFolder)) {
  if (!filename.endsWith(".abap")) {
    continue;
  }
  const file = path.join(classesFolder, filename);
  const original = readFileSync(file, "utf-8");
  if (!/\bcl_abap_conv_(out|in)_ce\b/i.test(original)) {
    continue;
  }
  // keep the line endings of the file
  const crlf = original.includes("\r\n");
  const {source, counts} = replaceSource(crlf ? original.replace(/\r\n/g, "\n") : original, filename);
  const result = crlf ? source.replace(/\n/g, "\r\n") : source;
  if (result !== original) {
    changed.push({file, result});
    totals.files++;
    for (const key of Object.keys(counts)) {
      totals[key] += counts[key];
    }
  }
}
for (const {file, result} of changed) {
  writeFileSync(file, result);
}

console.log(`Replaced cl_abap_conv_out_ce and cl_abap_conv_in_ce with cl_abap_conv_codepage in ${totals.files} files: ` +
  `${totals.types} declarations, ${totals.create} converters, ${totals.convert} conversions, ` +
  `${totals.uccpiConstant + totals.uccpiIn} code points to characters, ${totals.uccpiOut} characters to code points.`);
