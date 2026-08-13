'use strict';
const fs = require('fs');
const out = {
  unlinkSync: fs.unlinkSync.toString(),
  rmdirSync: fs.rmdirSync.toString(),
  rmSync: fs.rmSync ? fs.rmSync.toString() : 'undefined',
};
// Wrapped functions contain either toAbsPath (the wrapper's first line) or
// tryTrash / wrappedRmSync / wrappedPromisesRm (named wrapper functions).
const isWrapped = (s) =>
  s.includes('toAbsPath') ||
  s.includes('tryTrash') ||
  s.includes('wrappedRmSync') ||
  s.includes('wrappedPromisesRm');
const wrap = {
  unlinkSync: isWrapped(out.unlinkSync),
  rmdirSync: isWrapped(out.rmdirSync),
  rmSync: isWrapped(out.rmSync),
};
const confirmed = wrap.unlinkSync && wrap.rmdirSync && wrap.rmSync;
console.log('FS_WRAPPED=' + JSON.stringify(wrap));
console.log('SESSION_ID=' + (process.env.CODEBUDDY_SESSION_ID || ''));
console.log('NODE_OPTIONS=' + (process.env.NODE_OPTIONS || ''));
console.log('SHIM_INJECTION_CONFIRMED=' + (confirmed ? 'YES' : 'NO'));
