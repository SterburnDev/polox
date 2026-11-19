extends RefCounted
## /reset: clears what this site keeps on the phone, after saying exactly what
## goes, for when a stale cache or a broken saved state is the suspect. Only
## this address's data (the browser keeps it per address), only after a tap.
## Then: open the launcher again (or try a private tab). No backslashes in the
## JavaScript (GDScript would read them as escapes).

const HTML := """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Polox: start fresh on this phone</title>
<style>body{margin:0;padding:20px 16px 50px;font:21px/1.45 -apple-system,system-ui,Roboto,sans-serif;background:#fff;color:#111}h1{font-size:30px;margin:0 0 10px}
li{margin:6px 0}button,a.b{display:inline-block;font:inherit;font-size:21px;padding:14px 18px;margin:10px 10px 0 0;border-radius:12px;border:2px solid #333;background:#f2f2f2;color:#111;text-decoration:none}
button.danger{background:#c62828;border-color:#c62828;color:#fff}.note{background:#fff6d6;border:2px solid #e0b000;border-radius:12px;padding:12px;margin:14px 0}#done{font-weight:700;color:#1a7f37}</style></head>
<body><h1>Start fresh on this phone</h1>
<p>This clears what Polox keeps <b>in this browser, for this address only</b>:</p>
<ul><li>the pairing key (you'll type the PIN shown on the PC again),</li>
<li>this phone's copy of your worlds (the PC keeps the master copy: <b>changes made on the phone since its last sync are lost</b>),</li>
<li>remembered choices (the last world you picked),</li>
<li>cached files and any leftover offline helpers.</li></ul>
<p>Nothing on your PC changes.</p>
<button class="danger" id="go">Clear and start fresh</button><a class="b" href="/">Cancel</a>
<p id="done"></p><div id="what"></div>
<div class="note">Tip: a <b>private/incognito tab</b> is another quick way to try with a clean slate (pairing won't be remembered there).</div>
<script>
var $=function(i){return document.getElementById(i);};
function line(t){var d=document.createElement("div");d.textContent=t;$("what").appendChild(d);}
function wipeDbs(){if(!window.indexedDB){return Promise.resolve();}
var names=["/userfs","polox_test"];var list=(indexedDB.databases?indexedDB.databases():Promise.resolve([])).then(function(dbs){(dbs||[]).forEach(function(d){if(d&&d.name&&names.indexOf(d.name)<0){names.push(d.name);}});},function(){});
return list.then(function(){return Promise.all(names.map(function(n){return new Promise(function(res){try{var q=indexedDB.deleteDatabase(n);q.onsuccess=q.onerror=q.onblocked=function(){line("Removed saved data: "+n);res();};}catch(e){res();}});}));});}
$("go").onclick=function(){$("go").disabled=true;var n=0;
try{n=localStorage.length;localStorage.clear();line("Removed "+n+" remembered setting(s), including the pairing key.");}catch(e){line("Couldn't clear remembered settings: "+e.message);}
try{sessionStorage.clear();}catch(e){}
try{document.cookie.split(";").forEach(function(c){var k=c.split("=")[0].trim();if(k){document.cookie=k+"=; path=/; max-age=0";}});}catch(e){}
var jobs=[wipeDbs()];
if(window.caches&&caches.keys){jobs.push(caches.keys().then(function(ks){return Promise.all(ks.map(function(k){line("Removed cache: "+k);return caches.delete(k);}));},function(){}));}
if(navigator.serviceWorker&&navigator.serviceWorker.getRegistrations){jobs.push(navigator.serviceWorker.getRegistrations().then(function(rs){return Promise.all(rs.map(function(r){line("Removed an offline helper.");return r.unregister();}));},function(){}));}
Promise.all(jobs).then(function(){$("done").innerHTML="Done. <a class=b href=/>Open the Polox Launcher</a>";});};
</script></body></html>
"""


static func html() -> String:
	return HTML
