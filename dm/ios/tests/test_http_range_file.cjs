const assert=require('node:assert/strict');
require('../Engines/Web/http-range-file.js');
const data=Uint8Array.from({length:2560},(_,i)=>i&255);let requests=[],mode='ok';
global.XMLHttpRequest=class {
 open(method,url,async){assert.equal(method,'GET');assert.equal(async,false);}
 overrideMimeType(value){assert.match(value,/x-user-defined/);}
 setRequestHeader(name,value){assert.equal(name,'Range');this.range=value;}
 send(){const m=/^bytes=(\d+)-(\d+)$/.exec(this.range);let a=+m[1],b=+m[2];requests.push([a,b]);this.status=mode==='status'?200:206;this.header=`bytes ${a}-${b}/${data.length}`;this.responseText=String.fromCharCode(...data.slice(a,b+1));if(mode==='short')this.responseText=this.responseText.slice(1);if(mode==='range')this.header='bytes 0-1/2';}
 getResponseHeader(name){assert.equal(name,'Content-Range');return this.header;}
};
const fakeNode={stream_ops:{llseek:'preserved'}};
const FS={lookupPath(path){assert.equal(path,'/game.zip');return {node:fakeNode};},createDataFile(parent,name,contents,r,w){assert.equal(parent,'/');assert.equal(name,'game.zip');assert.equal(contents.length,0);assert.equal(r,true);assert.equal(w,false);fakeNode.stream_ops={llseek:'preserved'};}};
const node=TonTonRangeFile.attach(FS,'/game.zip','/game.zip',data.length,{blockBytes:128,cacheBlocks:3});
assert.equal(node.usedBytes,data.length);assert.equal(node.stream_ops.llseek,'preserved');
for(const [p,n] of [[0,1],[126,5],[255,600],[2550,20],[2560,12],[4000,0],[100,24]]){
 let dest=new Uint8Array(n+4).fill(42);let got=node.stream_ops.read({},dest,2,n,p);let want=Math.min(n,Math.max(0,data.length-p));assert.equal(got,want);assert.deepEqual(dest.slice(2,2+got),data.slice(p,p+got));assert.equal(dest[0],42);assert.equal(dest.at(-1),42);
}
assert.ok(requests.every(([a,b])=>b-a+1<=128));
let before=requests.length;node.stream_ops.read({},new Uint8Array(4),0,4,100);assert.equal(requests.length,before);
for(const modeName of ['status','short','range']){
 mode=modeName;let n=TonTonRangeFile.attach(FS,'/game.zip','/game.zip',data.length,{blockBytes:128});assert.throws(()=>n.stream_ops.read({},new Uint8Array(1),0,1,0));
}
mode='ok';assert.throws(()=>node.stream_ops.read({},new Uint8Array(1),0,1,-1));assert.throws(()=>node.stream_ops.read({},new Uint8Array(1),1,1,0));assert.throws(()=>node.stream_ops.write());assert.throws(()=>node.stream_ops.mmap());
assert.throws(()=>TonTonRangeFile.attach(FS,'/game.zip','/game.zip',Infinity));assert.throws(()=>TonTonRangeFile.attach(FS,'/game.zip','/game.zip',1,{blockBytes:9000000}));
console.log('range reads, binary bytes, EOF, bounds, cache, non-range and truncation rejection: passed');
