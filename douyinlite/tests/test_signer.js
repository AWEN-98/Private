// Offline cross-language regression vectors, produced from the Apache-2.0
// upstream Python signer at b5505e3830a2e4b9b8608962f58e96dfe75f23c5.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const path=require('node:path'),root=path.join(__dirname,'..');
const ctx=vm.createContext({});vm.runInContext(fs.readFileSync(path.join(root,'Resources','DLSigner.js'),'utf8'),ctx);
const signer=ctx.DLSigner;
const hex=a=>Array.from(a).map(x=>x.toString(16).padStart(2,'0')).join('');
assert.equal(hex(signer.sm3('abc')),'66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0');
assert.equal(hex(signer.sm3('abcd'.repeat(16))),'debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732');
for(const v of JSON.parse(fs.readFileSync(path.join(__dirname,'signer-vectors.json'),'utf8'))){
 assert.equal(signer.sign(v.query,v.body,v.ua,v.now,()=>.25),v.expected);
 assert.notEqual(signer.sign(v.query,v.body+'x',v.ua,v.now,()=>.25),v.expected);
 assert.notEqual(signer.sign(v.query+'x',v.body,v.ua,v.now,()=>.25),v.expected);
}
assert.throws(()=>signer.sign('','','Chrome',1,()=>.25),/clock/);
console.log('SM3 standard vectors, cross-language signatures, query/body binding, clock rejection: passed');
