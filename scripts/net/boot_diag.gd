extends RefCounted
## Rung R6: start-up diagnostics around the Godot Web client. web_build.gd puts
## this script at the top of the exported index.html (between markers, so a
## rebuild replaces it instead of adding a second copy). On the phone it:
##   - keeps the last 200 console lines, page errors and unhandled rejections;
##   - checks, before the engine needs them: WebAssembly, WebGL 2, storage, and
##     that every game file the page expects is there at the size index.html's
##     GODOT_CONFIG.fileSizes says (a missing, stale or cut-off file shows here,
##     not as a black screen), and that the phone version matches the PC;
##   - watches the start: loading that stops for 30 s, Godot's own failure
##     notice, a lost WebGL context, the engine starting but the game never
##     appearing (the game sets window.poloxBooted when it's up);
##   - on any failure shows a big card with what to try, and sends a report to
##     the PC (POST /api/report, a short GET if that fails). A small red chip
##     appears for errors; triple-tap the top-left corner for the full panel
##     (Copy, Send to PC, Connection test, Reload).
## No backslashes in the JavaScript (GDScript would read them as escapes).

const START := "<!--polox-boot-diag-->"
const END := "<!--/polox-boot-diag-->"

const SCRIPT := """
(function(){
try{
if(window.poloxBoot){return;}
var B=window.poloxBoot={log:[],stage:"loading",fatal:"",kind:"",tips:[],checks:[],reported:false,progress:-1,progressAt:Date.now(),engineAt:0,pct:0,errors:0};
var NL=String.fromCharCode(10);
var TIPS={
files:["On the PC: Settings > Phone Link > Build the phone version (or run phone_doctor.bat).","Then open the Polox Launcher again (the address without anything after it)."],
wasm:["This browser can't run WebAssembly. Update it, or use Chrome (Android) or Safari (iPhone)."],
webgl:["This browser can't draw the game (no WebGL 2). Update it, switch off battery saver, or use Chrome (Android) or Safari (iPhone)."],
memory:["Close other tabs and apps, then reload.","If it keeps happening, restart the browser."],
stalled:["The download stopped. Keep the screen on and stay near the router, then reload.","If it stops again, run the Connection test (button below)."],
context:["The phone's graphics were reset (another app, or low memory). Reload the page."],
blank:["Reload once.","If it stays blank, tap Send to PC (or Copy) so the PC has the details."],
godot:["Reload once.","If it happens again, tap Send to PC (or Copy) so the PC has the details."]};
function ts(){return new Date().toTimeString().slice(0,8);}
function txt(a){try{if(a instanceof Error){return a.name+": "+a.message;}if(a&&typeof a==="object"){return JSON.stringify(a).slice(0,300);}return String(a);}catch(e){return String(a);}}
function esc(t){return String(t).split("&").join("&amp;").split("<").join("&lt;").split(">").join("&gt;");}
function add(kind,args){var t=Array.prototype.slice.call(args).map(txt).join(" ");B.log.push(ts()+" "+kind+" "+t.slice(0,400));if(B.log.length>200){B.log.shift();}
if(kind==="error"){B.errors++;chip();var l=t.toLowerCase();if(l.indexOf("aborted(oom)")>=0||l.indexOf("out of memory")>=0||l.indexOf("could not allocate memory")>=0){fail("memory","The phone ran out of memory while starting the game.");}}}
["log","info","warn","error"].forEach(function(k){var o=console[k];console[k]=function(){add(k,arguments);if(o){try{o.apply(console,arguments);}catch(e){}}};});
window.addEventListener("error",function(e){add("error",[(e.message||"page error")+(e.filename?" @"+String(e.filename).split("/").pop()+":"+e.lineno:"")]);});
window.addEventListener("unhandledrejection",function(e){var r=e.reason;add("error",["unhandled rejection: "+(r&&r.message?r.message:txt(r))]);});

var CSS="#pxb-chip{position:fixed;top:6px;left:50%;transform:translateX(-50%);z-index:99999;background:#c62828;color:#fff;border:0;border-radius:20px;padding:10px 16px;font:600 17px system-ui,sans-serif;display:none;touch-action:manipulation}"+
"#pxb-panel{position:fixed;left:0;top:0;right:0;bottom:0;z-index:100000;background:#fff;color:#111;overflow:auto;padding:18px 16px 40px;font:19px/1.4 system-ui,sans-serif;display:none;-webkit-user-select:text;user-select:text;touch-action:auto}"+
"#pxb-panel h2{font-size:28px;margin:0 0 10px}#pxb-panel .bad{background:#fdecea;border:2px solid #c62828;border-radius:12px;padding:12px;font-size:21px;font-weight:700}"+
"#pxb-panel button,#pxb-panel a.b{display:inline-block;font:inherit;font-size:19px;padding:12px 14px;margin:8px 8px 0 0;border-radius:12px;border:2px solid #333;background:#f2f2f2;color:#111;text-decoration:none}"+
"#pxb-panel pre{white-space:pre-wrap;word-break:break-word;font-size:13px;background:#f6f6f6;padding:8px;border-radius:8px}#pxb-panel li{margin:4px 0}";
function ui(){if(B.ui||!document.body){return !!B.ui;}B.ui=true;var s=document.createElement("style");s.textContent=CSS;document.head.appendChild(s);
var c=document.createElement("button");c.id="pxb-chip";c.type="button";c.onclick=function(){show();};document.body.appendChild(c);
var p=document.createElement("div");p.id="pxb-panel";document.body.appendChild(p);return true;}
function chip(){if(!ui()){return;}var c=document.getElementById("pxb-chip");if(c&&!B.open){c.textContent=B.fatal?"The game couldn't start: tap here":"Something went wrong: tap for details";c.style.display="block";}}
function show(){if(!ui()){return;}B.open=true;var c=document.getElementById("pxb-chip");if(c){c.style.display="none";}document.getElementById("pxb-panel").style.display="block";render();}
function hide(){B.open=false;var p=document.getElementById("pxb-panel");if(p){p.style.display="none";}if(B.errors||B.fatal){chip();}}
function render(){if(!ui()){return;}var p=document.getElementById("pxb-panel");var h="<h2>Polox start-up</h2>";
if(B.fatal){h+="<div class=bad>"+esc(B.fatal)+"</div><p><b>What to try:</b></p><ul>"+B.tips.map(function(t){return "<li>"+esc(t)+"</li>";}).join("")+"</ul>";}
h+="<p>Stage: "+esc(B.stage)+(B.pct?" ("+B.pct+"% loaded)":"")+"</p><ul>"+B.checks.map(function(c){return "<li>"+(c.ok?"&#10003; ":"&#10007; ")+esc(c.name)+": "+esc(c.detail)+"</li>";}).join("")+"</ul>";
h+="<div><button id=pxb-send type=button>Send to PC</button><button id=pxb-copy type=button>Copy</button><a class=b href=/test>Connection test</a><button id=pxb-reload type=button>Reload</button><button id=pxb-close type=button>Close</button></div>";
h+="<p id=pxb-sent>"+esc(B.sentText||"")+"</p><textarea id=pxb-text style=position:absolute;left:-9999px></textarea><pre id=pxb-log></pre>";
p.innerHTML=h;document.getElementById("pxb-log").textContent=B.log.slice(-80).join(NL);
document.getElementById("pxb-send").onclick=function(){send(false);};document.getElementById("pxb-copy").onclick=copy;
document.getElementById("pxb-reload").onclick=function(){location.reload();};document.getElementById("pxb-close").onclick=hide;}
function sent(t){B.sentText=t;var e=document.getElementById("pxb-sent");if(e){e.textContent=t;}}
function fail(kind,msg){if(B.fatal){return;}B.fatal=msg;B.kind=kind;B.tips=TIPS[kind]||[];B.stage="failed";add("warn",["start-up failed: "+msg]);show();send(true);}
function check(name,ok,detail){B.checks.push({name:name,ok:ok,detail:String(detail)});if(B.open){render();}}
function report(){var r=[{id:"boot",name:"Game start-up",ok:!B.fatal,detail:B.fatal||("stage: "+B.stage),level:B.fatal?"bad":"ok"}];
B.checks.forEach(function(c){r.push({id:"boot_check",name:c.name,ok:c.ok,detail:c.detail});});
return {v:1,app:"Polox",page:"game",stage:B.stage,address:location.host+location.pathname,results:r,env:{ua:navigator.userAgent,screen:screen.width+"x"+screen.height+" @"+(window.devicePixelRatio||1),memory_gb:navigator.deviceMemory||0,secure:!!window.isSecureContext,webgl2:B.webgl2,max_texture:B.maxTexture||0,wasm:B.wasm},hints:B.tips,log:B.log.slice(-60)};}
function b64url(s){var b=btoa(unescape(encodeURIComponent(s)));return b.split("+").join("-").split("/").join("_").split("=").join("");}
function send(auto){if(auto&&B.reported){return;}B.reported=true;sent("Sending to the PC...");
fetch("/api/report",{method:"POST",headers:{"Content-Type":"text/plain"},body:JSON.stringify(report()),cache:"no-store"}).then(function(r){if(r.status===200){sent("Sent to the PC: it shows in the Doctor and on the Phone Link screen.");}else{throw new Error("HTTP "+r.status);}}).catch(function(e){
var c={v:1,c:1,s:"boot:"+(B.fatal?0:1)+":0",d:"boot="+(B.fatal||B.stage).slice(0,500),ua:navigator.userAgent.slice(0,160),a:location.host,w:B.webgl2?1:0,m:B.wasm?1:0,t:B.maxTexture||0};
fetch("/api/report?r="+b64url(JSON.stringify(c)),{cache:"no-store"}).then(function(r){sent(r.status===200?"Sent to the PC (short version).":"Couldn't send it: use Copy.");},function(){sent("Couldn't reach the PC to send it: use Copy.");});});}
function copy(){var t=document.getElementById("pxb-text");var text=JSON.stringify(report(),null,1);t.value=text;t.focus();t.select();var ok=false;try{ok=document.execCommand("copy");}catch(e){}
if(!ok&&navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(text).then(function(){sent("Copied.");},function(){sent("Couldn't copy here.");});}else{sent(ok?"Copied: paste it where you ask for help.":"Couldn't copy here.");}}

function preflight(){
try{B.wasm=typeof WebAssembly==="object"&&WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0]));}catch(e){B.wasm=false;}
check("WebAssembly",B.wasm,B.wasm?"works":"missing");if(!B.wasm){fail("wasm","This browser can't run WebAssembly, which the game needs.");return;}
var gl=null;try{gl=document.createElement("canvas").getContext("webgl2");}catch(e){}
B.webgl2=!!gl;if(!gl){check("WebGL 2",false,"missing");fail("webgl","This browser can't draw the game: WebGL 2 isn't available.");return;}
B.maxTexture=gl.getParameter(gl.MAX_TEXTURE_SIZE);check("WebGL 2",true,"max texture "+B.maxTexture);try{var lose=gl.getExtension("WEBGL_lose_context");if(lose){lose.loseContext();}}catch(e){}
var ls=false;try{localStorage.setItem("polox_boot","1");ls=localStorage.getItem("polox_boot")==="1";localStorage.removeItem("polox_boot");}catch(e){}
check("Storage",ls,ls?"works":"blocked (private tab?): the phone can't keep your worlds");
var sizes={};try{sizes=(typeof GODOT_CONFIG!=="undefined"&&GODOT_CONFIG.fileSizes)||{};}catch(e){}
var names=Object.keys(sizes);var i=0;
function next(){if(B.fatal){return;}if(i>=names.length){version();return;}var n=names[i++];
fetch(n,{method:"HEAD",cache:"no-store"}).then(function(r){var size=+(r.headers.get("X-Polox-Size")||r.headers.get("content-length")||-1);var ok=r.status===200&&size===sizes[n];
check("File "+n,ok,r.status!==200?"HTTP "+r.status:(size+" bytes, expected "+sizes[n]));if(!ok){fail("files","The game files on the PC don't match this page ("+n+": "+(r.status!==200?"HTTP "+r.status:size+" bytes instead of "+sizes[n])+").");return;}next();},
function(e){check("File "+n,false,txt(e));next();});}
next();}
function version(){var m=location.pathname.split("/");var id=(m.length>3&&m[1]==="game")?m[2]:"";
fetch("/test/info.json",{cache:"no-store"}).then(function(r){return r.json();}).then(function(info){var pc=String(info.build_id||"").slice(0,16);if(id&&pc){check("Same version as the PC",id===pc,id===pc?"yes":"this phone version "+id+", the PC "+pc+": build the phone version again on the PC");}}).catch(function(){});}

setInterval(function(){try{
var st=document.getElementById("status"),pr=document.getElementById("status-progress"),no=document.getElementById("status-notice");
if(B.stage==="loading"){
if(pr&&pr.hasAttribute("value")){var v=+pr.value;if(v!==B.progress){B.progress=v;B.progressAt=Date.now();B.pct=pr.max?Math.round(100*v/pr.max):0;}}
if(no&&no.style.display==="block"&&no.textContent){fail("godot","The game couldn't start: "+no.textContent.slice(0,240));}
else if(!st){B.stage="started";B.engineAt=Date.now();}
else if(Date.now()-B.progressAt>30000){fail("stalled","Loading stopped"+(B.pct?" at "+B.pct+"%":"")+": nothing more arrived for 30 seconds.");}}
else if(B.stage==="started"){if(window.poloxBooted){B.stage="running";}else if(Date.now()-B.engineAt>25000){fail("blank","The game engine started, but the game didn't appear within 25 seconds.");}}
}catch(e){}},1000);

var taps=[];
function corner(x,y){if(x>70||y>70){return;}var n=Date.now();taps=taps.filter(function(t){return n-t<800;});taps.push(n);if(taps.length>=3){taps=[];if(B.open){hide();}else{show();}}}
document.addEventListener("touchend",function(e){var t=e.changedTouches&&e.changedTouches[0];if(t){corner(t.clientX,t.clientY);}},true);
document.addEventListener("mouseup",function(e){corner(e.clientX,e.clientY);},true);
document.addEventListener("DOMContentLoaded",function(){ui();var cv=document.getElementById("canvas");
if(cv){cv.addEventListener("webglcontextlost",function(){add("error",["WebGL context lost"]);if(B.stage!=="running"){fail("context","The phone's graphics were reset while the game was starting.");}},false);}
if(B.errors){chip();}preflight();});
}catch(err){try{console.error("polox boot diagnostics: "+err);}catch(e){}}
})();
"""


## The block web_build.gd puts right after <head> (markers included).
static func block() -> String:
	return START + "<script>" + SCRIPT + "</script>" + END


## index.html with exactly one, current copy of the block (an older one is replaced).
static func inject(html: String) -> String:
	var s := html
	var a := s.find(START)
	if a >= 0:
		var b := s.find(END, a)
		if b >= 0:
			s = s.substr(0, a) + s.substr(b + END.length())
	var head := s.find("<head>")
	if head < 0:
		return ""
	return s.substr(0, head + 6) + block() + s.substr(head + 6)
