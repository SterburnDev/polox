extends RefCounted
## /test: the phone-side Connection Test. One static page, no dependencies,
## big text, for iPhone Safari and Android Chrome alike. It runs each rung of
## the ladder from the phone and shows green/red with timings and the exact
## error text, then sends its report to the PC (POST /api/report, falling back
## to a compact GET when POST fails):
##   page loaded (the phone reached the PC on this port), GET /ping, a small
##   JSON fetch, the browser's abilities (WebAssembly, WebGL 2 and texture size,
##   storage, cookies, ...), a ~20 MB download checked by SHA-256 with its speed,
##   and on the real host the launcher's API.
## Built with replace(): no % formatting, and no backslashes in the JavaScript
## (GDScript would read them as escapes). SHA-256 is plain JavaScript because
## crypto.subtle only exists on https pages.

const STYLE := """
*{box-sizing:border-box}
body{margin:0;padding:18px 16px 60px;background:#fff;color:#111;font:22px/1.4 -apple-system,system-ui,Roboto,'Segoe UI',sans-serif}
h1{font-size:34px;margin:0 0 4px}
.sub{color:#444;font-size:19px;margin:0 0 14px}
.row{display:flex;gap:12px;align-items:flex-start;padding:12px 0;border-bottom:1px solid #ddd}
.mark{flex:0 0 46px;height:46px;border-radius:23px;display:flex;align-items:center;justify-content:center;font-size:28px;font-weight:700;color:#fff;background:#999}
.ok .mark{background:#1a7f37}.bad .mark{background:#c62828}.warn .mark{background:#b26a00}.run .mark{background:#1565c0}
.name{font-weight:700}
.detail{color:#333;font-size:19px;word-break:break-word}
.hint{background:#fff6d6;border:2px solid #e0b000;border-radius:12px;padding:12px;margin:12px 0;font-size:20px}
.big{font-size:28px;font-weight:700}
button{font:inherit;font-size:22px;padding:14px 18px;margin:8px 8px 0 0;border-radius:12px;border:2px solid #333;background:#f2f2f2;color:#111}
button.main{background:#1565c0;color:#fff;border-color:#1565c0}
textarea{width:100%;height:160px;font-size:14px;margin-top:10px}
#status{margin:14px 0;font-size:24px;font-weight:700}
.small{font-size:16px;color:#555}
"""

const BODY := """
<h1>Polox Connection Test</h1>
<p class="sub" id="where">Checking the connection between this phone and your PC...</p>
<div id="status">Running...</div>
<div id="rows"></div>
<div id="hints"></div>
<div>
<button class="main" id="again">Run again</button>
<button id="copy">Copy report</button>
<button id="send">Send to PC</button>
</div>
<p class="small" id="sent"></p>
<textarea id="report" readonly></textarea>
<p class="small">This page sends no passwords, keys or PINs: only what you see here and your browser's name and screen size.</p>
"""

const SCRIPT := """
var K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
function Sha256(){this.h=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];this.buf=new Uint8Array(64);this.n=0;this.total=0;this.w=new Int32Array(64);}
Sha256.prototype.block=function(b,o){var w=this.w,h=this.h,i;
for(i=0;i<16;i++){w[i]=(b[o+4*i]<<24)|(b[o+4*i+1]<<16)|(b[o+4*i+2]<<8)|b[o+4*i+3];}
for(i=16;i<64;i++){var x=w[i-15],y=w[i-2];var s0=((x>>>7)|(x<<25))^((x>>>18)|(x<<14))^(x>>>3);var s1=((y>>>17)|(y<<15))^((y>>>19)|(y<<13))^(y>>>10);w[i]=(w[i-16]+s0+w[i-7]+s1)|0;}
var a=h[0],c1=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],k=h[7];
for(i=0;i<64;i++){var S1=((e>>>6)|(e<<26))^((e>>>11)|(e<<21))^((e>>>25)|(e<<7));var ch=(e&f)^((~e)&g);var t1=(k+S1+ch+K[i]+w[i])|0;var S0=((a>>>2)|(a<<30))^((a>>>13)|(a<<19))^((a>>>22)|(a<<10));var mj=(a&c1)^(a&c)^(c1&c);var t2=(S0+mj)|0;k=g;g=f;f=e;e=(d+t1)|0;d=c;c=c1;c1=a;a=(t1+t2)|0;}
h[0]=(h[0]+a)|0;h[1]=(h[1]+c1)|0;h[2]=(h[2]+c)|0;h[3]=(h[3]+d)|0;h[4]=(h[4]+e)|0;h[5]=(h[5]+f)|0;h[6]=(h[6]+g)|0;h[7]=(h[7]+k)|0;};
Sha256.prototype.absorb=function(data){var i=0,n=data.length;
if(this.n>0){while(i<n&&this.n<64){this.buf[this.n++]=data[i++];}if(this.n===64){this.block(this.buf,0);this.n=0;}}
while(i+64<=n){this.block(data,i);i+=64;}
while(i<n){this.buf[this.n++]=data[i++];}};
Sha256.prototype.update=function(data){this.total+=data.length;this.absorb(data);};
Sha256.prototype.hex=function(){var bits=this.total*8;var len=(this.n<56?56:120)-this.n;var pad=new Uint8Array(len+8);pad[0]=0x80;
var hi=Math.floor(bits/4294967296),lo=bits%4294967296,L=pad.length;
pad[L-8]=(hi>>>24)&255;pad[L-7]=(hi>>>16)&255;pad[L-6]=(hi>>>8)&255;pad[L-5]=hi&255;pad[L-4]=(lo>>>24)&255;pad[L-3]=(lo>>>16)&255;pad[L-2]=(lo>>>8)&255;pad[L-1]=lo&255;
this.absorb(pad);var s='';for(var i=0;i<8;i++){var v=(this.h[i]>>>0).toString(16);while(v.length<8){v='0'+v;}s+=v;}return s;};
function sha256text(t){var s=new Sha256();var b=[];for(var i=0;i<t.length;i++){b.push(t.charCodeAt(i)&255);}s.update(new Uint8Array(b));return s.hex();}

var results=[],env={},info={},hints=[],sentOK=false,running=false;
var $=function(id){return document.getElementById(id);};
function esc(t){return String(t).split('&').join('&amp;').split('<').join('&lt;').split('>').join('&gt;');}
function now(){return (window.performance&&performance.now)?performance.now():Date.now();}
function row(id,name){var d=document.createElement('div');d.className='row run';d.id='r_'+id;d.innerHTML='<div class="mark">&#8230;</div><div><div class="name">'+esc(name)+'</div><div class="detail">Checking...</div></div>';$('rows').appendChild(d);return d;}
function setRow(id,state,detail){var d=$('r_'+id);if(!d){return;}d.className='row '+state;d.querySelector('.mark').innerHTML=state==='ok'?'&#10003;':(state==='bad'?'&#10007;':(state==='warn'?'!':'&#8230;'));d.querySelector('.detail').textContent=detail;}
function add(id,name,ok,ms,detail,level){results.push({id:id,name:name,ok:ok,ms:Math.round(ms||0),detail:String(detail).slice(0,300),level:level||(ok?'ok':'bad')});setRow(id,level||(ok?'ok':'bad'),detail+(ms?'  ('+Math.round(ms)+' ms)':''));}
function errText(e){if(!e){return 'unknown error';}var m=(e.name&&e.name!=='Error'?e.name+': ':'')+(e.message||String(e));return m.slice(0,200);}
function fetchT(url,opts,ms){opts=opts||{};opts.cache='no-store';var ctl=window.AbortController?new AbortController():null;if(ctl){opts.signal=ctl.signal;}
return new Promise(function(res,rej){var done=false;var t=setTimeout(function(){if(!done){done=true;if(ctl){ctl.abort();}rej(new Error('timed out after '+Math.round(ms/1000)+' s'));}},ms);
fetch(url,opts).then(function(r){if(!done){done=true;clearTimeout(t);res(r);}},function(e){if(!done){done=true;clearTimeout(t);rej(e);}});});}

async function rungPing(){row('ping','GET /ping (plain text)');var t=now();try{var r=await fetchT('/ping?t='+Date.now(),{},10000);var txt=await r.text();var ok=r.status===200&&txt.indexOf('Polox OK')>=0;add('ping','GET /ping',ok,now()-t,ok?'The PC answered "Polox OK".':'Unexpected answer: HTTP '+r.status+' '+txt.slice(0,60));}catch(e){add('ping','GET /ping',false,now()-t,'Failed: '+errText(e));}}

async function rungInfo(){row('info','Small JSON fetch');var t=now();try{var r=await fetchT('/test/info.json?t='+Date.now(),{},10000);info=await r.json();var ok=r.status===200&&info.app==='Polox';add('info','Small JSON fetch',ok,now()-t,ok?('From '+info.server_name+' on '+info.pc+' (your phone is '+info.your_ip+').'):'Unexpected answer (HTTP '+r.status+').');
$('where').textContent='This phone reached '+(info.pc||'your PC')+' at '+location.host+' ('+(info.server_name||'Polox')+').';}catch(e){add('info','Small JSON fetch',false,now()-t,'Failed: '+errText(e));}}

function rungEnv(){row('env','What this browser can do');var t=now();var bad=[],warn=[];
env.ua=navigator.userAgent;env.url=location.href.split('#')[0];env.protocol=location.protocol;env.origin=location.origin;env.secure=!!window.isSecureContext;env.online=navigator.onLine;
env.screen=screen.width+'x'+screen.height+' @'+(window.devicePixelRatio||1);env.viewport=window.innerWidth+'x'+window.innerHeight;env.cores=navigator.hardwareConcurrency||0;env.memory_gb=navigator.deviceMemory||0;env.lang=navigator.language;
try{env.wasm=typeof WebAssembly==='object'&&WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0]));}catch(e){env.wasm=false;}
if(!env.wasm){bad.push('no WebAssembly');}
try{var cv=document.createElement('canvas');var gl=cv.getContext('webgl2');env.webgl2=!!gl;if(gl){env.max_texture=gl.getParameter(gl.MAX_TEXTURE_SIZE);var dbg=gl.getExtension('WEBGL_debug_renderer_info');env.gpu=dbg?String(gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL)).slice(0,80):'';}}catch(e){env.webgl2=false;}
if(!env.webgl2){bad.push('no WebGL 2');}else if(env.max_texture<2048){warn.push('small textures ('+env.max_texture+')');}
try{localStorage.setItem('polox_test','1');env.local_storage=localStorage.getItem('polox_test')==='1';localStorage.removeItem('polox_test');}catch(e){env.local_storage=false;}
if(!env.local_storage){bad.push('storage blocked (private tab?)');}
try{document.cookie='polox_test=1; path=/; SameSite=Strict';env.cookies=document.cookie.indexOf('polox_test=1')>=0;document.cookie='polox_test=; path=/; max-age=0';}catch(e){env.cookies=false;}
env.indexeddb=!!window.indexedDB;env.service_worker='serviceWorker' in navigator;
var label=bad.length?('Problems: '+bad.join(', ')):(warn.length?('Works, but: '+warn.join(', ')):'WebAssembly, WebGL 2 (textures '+env.max_texture+'), storage and cookies all work.');
add('env','What this browser can do',bad.length===0,now()-t,label,bad.length?'bad':(warn.length?'warn':'ok'));
if(!env.wasm||!env.webgl2){hints.push('This browser can&#39;t run the game (WebAssembly or WebGL 2 missing). Update it, switch off battery saver, or try Chrome (Android) / Safari (iPhone).');}
if(!env.local_storage){hints.push('This browser blocks storage (private tab, or "block cookies"). Polox can&#39;t remember the pairing here: use a normal tab.');}}

function idbCheck(){return new Promise(function(res){if(!window.indexedDB){res(false);return;}var done=false;var t=setTimeout(function(){if(!done){done=true;res(false);}},4000);
try{var q=indexedDB.open('polox_test');q.onsuccess=function(){try{q.result.close();indexedDB.deleteDatabase('polox_test');}catch(e){}if(!done){done=true;clearTimeout(t);res(true);}};q.onerror=function(){if(!done){done=true;clearTimeout(t);res(false);}};}catch(e){if(!done){done=true;clearTimeout(t);res(false);}}});}

async function rungStorage(){row('storage','Saving games on this phone');var t=now();var idb=await idbCheck();env.indexeddb_works=idb;var persisted='unknown';
try{if(navigator.storage&&navigator.storage.persisted){persisted=(await navigator.storage.persisted())?'yes':'no';}}catch(e){}env.persisted=persisted;
add('storage','Saving games on this phone',idb,now()-t,idb?('IndexedDB works (kept for good: '+persisted+').'):'IndexedDB doesn&#39;t work here, so the phone can&#39;t keep your worlds (private tab?).'.split('&#39;').join("'"));}

async function rungBig(){row('big','Big download (like the game files)');var t=now();var got=0,len=0,last=now(),stalled=false;
try{var mr=await fetchT('/test/big.json?t='+Date.now(),{},10000);var meta=await mr.json();len=meta.size;
var ctl=window.AbortController?new AbortController():null;var sha=new Sha256();
var watch=setInterval(function(){if(now()-last>15000){stalled=true;if(ctl){ctl.abort();}}},1000);
try{var r=await fetch('/test/big?t='+Date.now(),{cache:'no-store',signal:ctl?ctl.signal:undefined});
if(r.status!==200){throw new Error('HTTP '+r.status);}
if(r.body&&r.body.getReader){var rd=r.body.getReader();for(;;){var x=await rd.read();if(x.done){break;}sha.update(x.value);got+=x.value.length;last=now();
setRow('big','run','Downloading: '+(got/1048576).toFixed(1)+' of '+(len/1048576).toFixed(1)+' MB');}}
else{var ab=new Uint8Array(await r.arrayBuffer());sha.update(ab);got=ab.length;}}finally{clearInterval(watch);}
var secs=(now()-t)/1000;var mbps=(got/1048576)/Math.max(secs,0.001);var hash=sha.hex();var ok=got===len&&hash===meta.sha256;
add('big','Big download',ok,now()-t,ok?((got/1048576).toFixed(1)+' MB arrived intact, '+mbps.toFixed(1)+' MB/s.'):(got!==len?('Only '+(got/1048576).toFixed(1)+' of '+(len/1048576).toFixed(1)+' MB arrived.'):'The file arrived changed (checksum differs).'));
env.big_mbps=Math.round(mbps*10)/10;
if(!ok&&got!==len){hints.push('The connection broke during a big download. Keep the screen on, move closer to the router, and switch off Wi-Fi power saving or battery saver; then Run again.');}
if(!ok&&got===len){hints.push('The file arrived changed on the way. Something on the network (a filter, proxy or antivirus) is altering data: try Tailscale instead.');}}
catch(e){add('big','Big download',false,now()-t,(stalled?'Stalled: nothing arrived for 15 s after ':'Failed after ')+(got/1048576).toFixed(1)+' MB: '+errText(e));
hints.push('The big download didn&#39;t finish. The phone game needs about 40 MB the first time: keep the screen on and stay near the router, then Run again.');}}

async function rungLauncher(){if(info.server!=='host'){return;}row('launcher','Polox Launcher (PIN and worlds)');var t=now();try{var r=await fetchT('/api/pairing?t='+Date.now(),{},10000);var j=await r.json();
add('launcher','Polox Launcher',r.status===200,now()-t,r.status===200?('Ready: '+(j.paused?'pairing is paused on the PC (Unlock there).':'type the PIN shown on the PC.')):'HTTP '+r.status);}catch(e){add('launcher','Polox Launcher',false,now()-t,'Failed: '+errText(e));}}

function platformHints(){var ua=navigator.userAgent;
if(/CriOS|FxiOS|EdgiOS|OPiOS/.test(ua)){hints.push('On iPhone, browsers other than Safari need permission to reach your PC: Settings > (this browser) > Local Network ON. Safari works without it.');}
if(location.protocol==='https:'&&info.server!=='host'){hints.push('This page came over https://. Polox Ping and Same Wi-Fi use http://; type the address with http:// in front.');}}

function report(){return {v:1,app:'Polox',page:'test',when:new Date().toISOString(),server:info.server||'',server_name:info.server_name||'',engine:info.engine||'',pc:info.pc||'',build_id:info.build_id||'',your_ip:info.your_ip||'',address:location.host,results:results,env:env,hints:hints.map(function(h){return h.split('&#39;').join("'");})};}
function reportText(){var r=report();var lines=['Polox Connection Test '+r.when,'Address: '+r.address+' ('+(r.server_name||'?')+', '+(r.engine||'?')+')','Phone: '+r.your_ip+' | '+env.ua];
r.results.forEach(function(x){lines.push((x.ok?'OK  ':(x.level==='warn'?'WARN':'FAIL'))+' '+x.name+': '+x.detail+(x.ms?' ('+x.ms+' ms)':''));});
lines.push('secure='+env.secure+' wasm='+env.wasm+' webgl2='+env.webgl2+' maxtex='+env.max_texture+' storage='+env.local_storage+' idb='+env.indexeddb_works+' cookies='+env.cookies+' screen='+env.screen);
r.hints.forEach(function(h){lines.push('Hint: '+h);});return lines.join(String.fromCharCode(10));}
function b64url(s){var b=btoa(unescape(encodeURIComponent(s)));return b.split('+').join('-').split('/').join('_').split('=').join('');}

async function send(){$('sent').textContent='Sending to the PC...';var body=JSON.stringify(report());
try{var r=await fetchT('/api/report',{method:'POST',headers:{'Content-Type':'text/plain'},body:body},10000);if(r.status===200){sentOK=true;$('sent').textContent='Sent to the PC: it shows up in the Doctor (and in Polox Ping).';return;}throw new Error('HTTP '+r.status);}
catch(e){try{var c={v:1,c:1,s:results.map(function(x){return x.id+':'+(x.ok?1:0)+':'+x.ms;}).join(','),d:results.filter(function(x){return !x.ok;}).map(function(x){return x.id+'='+x.detail;}).join(' | ').slice(0,600),ua:env.ua.slice(0,160),a:location.host,w:env.webgl2?1:0,m:env.wasm?1:0,t:env.max_texture||0};
var r2=await fetchT('/api/report?r='+b64url(JSON.stringify(c)),{},10000);if(r2.status===200){sentOK=true;$('sent').textContent='Sent to the PC (short version: the long one failed with '+errText(e)+').';return;}throw new Error('HTTP '+r2.status);}
catch(e2){$('sent').textContent='Couldn&#39;t send it to the PC ('+errText(e2)+'). Use Copy report and paste it instead.'.split('&#39;').join("'");}}}

async function runAll(){if(running){return;}running=true;results=[];hints=[];$('rows').innerHTML='';$('hints').innerHTML='';$('status').textContent='Running...';
add('page','This phone reached the PC',true,0,'This page loaded from '+location.host+', so the PC answers on this port.');
if(sha256text('abc')!=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'){hints.push('(The checksum code failed its self-test on this browser: the big-download result may be wrong.)');}
await rungPing();await rungInfo();rungEnv();await rungStorage();await rungBig();await rungLauncher();platformHints();
var bad=results.filter(function(x){return !x.ok&&x.level!=='warn';}).length;
$('status').textContent=bad?(bad+' problem'+(bad>1?'s':'')+' found: see the red rows and tips.'):'All good: this phone and your PC talk fine.';$('status').style.color=bad?'#c62828':'#1a7f37';
$('hints').innerHTML=hints.map(function(h){return '<div class="hint">'+h+'</div>';}).join('');$('report').value=reportText();running=false;await send();}

$('again').onclick=function(){runAll();};
$('send').onclick=function(){send();};
$('copy').onclick=function(){var t=$('report');t.value=reportText();t.focus();t.select();var ok=false;try{ok=document.execCommand('copy');}catch(e){}
if(!ok&&navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t.value).then(function(){$('sent').textContent='Copied.';},function(){$('sent').textContent='Select the text below and copy it.';});}else{$('sent').textContent=ok?'Copied: paste it where you ask for help.':'Select the text below and copy it.';}};
window.addEventListener('error',function(e){hints.push('Page error: '+esc(e.message||'?'));});
runAll();
"""


static func html() -> String:
	return "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Polox Connection Test</title><style>" + STYLE + "</style></head><body>" + BODY + "<script>" + SCRIPT + "</script></body></html>"
