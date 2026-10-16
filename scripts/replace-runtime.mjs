import {existsSync, readFileSync, writeFileSync} from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";

// ABAPiti currently emits GET RUN TIME FIELD in the generated telemetry timer,
// but that statement is not allowed in ABAP for Cloud Development. Replace the
// timer with a UTCLONG based implementation after each transpilation. The
// rewrite is idempotent and fails if the generated legacy implementation drifts.

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const timerFile = path.join(packageRoot, "src", "generated", "zlnt_runtime_tele_970d5104e5f4.clas.abap");

if (!existsSync(timerFile)) {
  throw new Error(`${timerFile} does not exist, run the transpilation first`);
}

const original = readFileSync(timerFile, "utf-8");
const crlf = original.includes("\r\n");
let source = crlf ? original.replace(/\r\n/g, "\n") : original;

const methodPattern = /^  METHOD now\.\n[\s\S]*?^  ENDMETHOD\./m;
const methods = source.match(methodPattern);
if (!methods || methods.length !== 1) {
  throw new Error(`${path.basename(timerFile)}: generated now method was not found`);
}
if (!/\bGET RUN TIME FIELD\b/i.test(methods[0])) {
  console.log("No legacy GET RUN TIME timer found; generated timer is already Cloud-compatible.");
  process.exit(0);
}

function replaceExactlyOnce(input, search, replacement, description) {
  const count = input.split(search).length - 1;
  if (count !== 1) {
    throw new Error(`${path.basename(timerFile)}: expected one ${description}, found ${count}`);
  }
  return input.replace(search, replacement);
}

source = replaceExactlyOnce(source,
  "CLASS-DATA previous TYPE i.",
  "CLASS-DATA previous TYPE utclong.",
  "previous declaration");
source = replaceExactlyOnce(source,
  "CLASS-DATA elapsed TYPE f.",
  "CLASS-DATA elapsed TYPE decfloat34.",
  "elapsed declaration");

const cloudMethod = [
  "  METHOD now.",
  "    DATA(current) = utclong_current( ).",
  "    IF initialized = abap_false.",
  "      initialized = abap_true.",
  "      previous = current.",
  "    ELSE.",
  "      DATA(delta) = utclong_diff( high = current low = previous ).",
  "      IF delta > 0.",
  "        elapsed = elapsed + delta.",
  "      ENDIF.",
  "      previous = current.",
  "    ENDIF.",
  "    result = trunc( elapsed * 1000 ).",
  "  ENDMETHOD.",
].join("\n");

source = source.replace(methodPattern, cloudMethod);

const rewrittenMethod = source.match(methodPattern)?.[0] ?? "";
if (/\bGET RUN TIME FIELD\b/i.test(rewrittenMethod) || !rewrittenMethod.includes("utclong_current( )")) {
  throw new Error(`${path.basename(timerFile)}: timer rewrite did not produce the expected Cloud-compatible implementation`);
}

const result = crlf ? source.replace(/\n/g, "\r\n") : source;
if (result !== original) {
  writeFileSync(timerFile, result);
  console.log(`Replaced GET RUN TIME FIELD in ${path.relative(packageRoot, timerFile)} with UTCLONG timing.`);
}
