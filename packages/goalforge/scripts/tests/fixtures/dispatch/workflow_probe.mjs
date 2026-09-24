// workflow_probe.mjs — EXECUTE a compiled Workflow script against stub hooks
// and print what it did, as JSON (wp-08 b1 structural oracle).
//
//   node workflow_probe.mjs <compiled-script.mjs> <runner exit_code>
//
// The stubs record every agent() call with the pipeline STAGE it ran in
// (1-based; 0 = outside any pipeline stage), every log() line and every
// pipeline's items. The agent whose opts carry a `schema` is the runner; it
// returns {exit_code: <arg>, stderr: ""}. A stage that throws drops the item,
// exactly as the Workflow tool's pipeline() does. So "gate B/C run only after,
// and only when, the runner exited 0" is observed, not read off the text.
import { pathToFileURL } from "node:url";

const [scriptPath, exitArg] = process.argv.slice(2);
const events = [];
const pipelines = [];
let stage = 0;

globalThis.phase = () => {};
globalThis.log = (message) => { events.push({ kind: "log", message }); };
globalThis.parallel = async (thunks) =>
  Promise.all(thunks.map((t) => (typeof t === "function" ? t() : t)));
globalThis.agent = async (opts) => {
  events.push({ kind: "agent", stage, ...opts });
  return opts && opts.schema
    ? { exit_code: Number(exitArg), stderr: "" }
    : { verdict: "stub" };
};
globalThis.pipeline = async (items, ...stages) => {
  pipelines.push({ items, stageCount: stages.length });
  const out = [];
  for (const [index, item] of items.entries()) {
    let result = item;
    try {
      for (const [k, fn] of stages.entries()) {
        stage = k + 1;
        result = await fn(result, item, index);
      }
      out.push(result);
    } catch {
      out.push(null);
    }
    stage = 0;
  }
  return out;
};

const mod = await import(pathToFileURL(scriptPath).href);
const result = await mod.default();
console.log(JSON.stringify({ events, pipelines, result }));
