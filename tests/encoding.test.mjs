import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
import {encodeKeyOctal} from '../scripts/key-encoding.mjs';

test('all byte values encode as unambiguous POSIX octal escapes',()=>{
 const bytes=Buffer.from(Array.from({length:256},(_,i)=>i));
 const octal=encodeKeyOctal(bytes);
 assert.match(octal,/^(\\0[0-3][0-7]{2}){256}$/);
 assert.deepEqual(Buffer.from(octal.match(/\\0[0-3][0-7]{2}/g).map(s=>parseInt(s.slice(2),8))),bytes);
 const installer=fs.readFileSync('scripts/installer.sh','utf8');
 assert.doesNotMatch(installer,/\bbase64\b/);
 assert.match(installer,/printf '%b' '@@KEY_OCTAL@@'/);
 assert.match(installer,/-l ql-@@PROFILE@@ @@RELAY_HOST@@/);
});

test('actual BusyBox ash reconstructs all bytes with builtin printf', {skip:!process.env.QL_TEST_SSH},()=>{
 const bytes=Buffer.from(Array.from({length:256},(_,i)=>i));
 const result=execFileSync('ssh',['-o','BatchMode=yes','-o','StrictHostKeyChecking=yes',process.env.QL_TEST_SSH,'busybox ash'],{input:`printf '%b' '${encodeKeyOctal(bytes)}'\n`});
 assert.deepEqual(result,bytes);
});
