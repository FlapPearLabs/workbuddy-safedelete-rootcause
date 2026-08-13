// repro-node-delete.mjs
// Minimal repro: small (under threshold) and large (over threshold) deletes
// under the two modes. Reports exit code, fs result, and whether the target
// directory is still present afterwards.
'use strict';
import fs from 'node:fs';
import path from 'node:path';

const mode = process.argv[2];           // 'normal' or 'workbuddy'
const which = process.argv[3];          // 'small' or 'large'
const target = process.argv[4];         // absolute path to delete

function listFiles(dir) {
  const out = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else out.push(p);
    }
  };
  walk(dir);
  return out;
}

let exit = 0;
let exception = null;
let stillExists = null;
try {
  if (!fs.existsSync(target)) {
    console.log(`MISSING_BEFORE: ${target}`);
    process.exit(2);
  }
  const beforeCount = listFiles(target).length;
  console.log(`MODE=${mode}`);
  console.log(`WHICH=${which}`);
  console.log(`TARGET=${target}`);
  console.log(`FILE_COUNT_BEFORE=${beforeCount}`);
  console.log(`SHIM_SESSION_ID=${process.env.CODEBUDDY_SESSION_ID || ''}`);

  fs.rmSync(target, { recursive: true, force: true });
  stillExists = fs.existsSync(target);
  console.log(`STILL_EXISTS_AFTER=${stillExists}`);
  if (stillExists) {
    const afterCount = listFiles(target).length;
    console.log(`FILE_COUNT_AFTER=${afterCount}`);
  }
} catch (e) {
  exception = e;
  exit = 1;
  console.log(`THROWN=${e && e.constructor && e.constructor.name}: ${e && e.message}`);
  if (e && e.stack) console.log('STACK_HEAD=' + e.stack.split('\n').slice(0, 4).join(' | '));
}

console.log(`EXIT_CODE=${exit}`);
process.exit(exit);
