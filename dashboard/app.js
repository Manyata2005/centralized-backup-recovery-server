const T=location.hash.slice(1)||sessionStorage.t||'';sessionStorage.t=T;history.replaceState(null,'',location.pathname);
const $=s=>document.querySelector(s),E=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
async function api(p,m='GET'){$('#busy').hidden=false;try{return await(await fetch('/api/'+p,{method:m,headers:{'X-Token':T}})).json()}
catch(e){return{ok:false,message:'Cannot reach server: '+e}}finally{$('#busy').hidden=true}}
function toast(ok,msg){const t=$('#toast');t.className=ok?'ok':'bad';t.textContent=(ok?'✔ ':'✖ ')+msg;setTimeout(()=>t.className='',5000)}
const badge=s=>`<span class="b ${s=='OK'||s=='SUCCESS'?'ok':s&&s!='-'?'bad':'na'}">${E(s||'Not verified')}</span>`;
const size=n=>n>1048576?(n/1048576).toFixed(2)+' MB':(n/1024).toFixed(1)+' KB';
async function stats(){const d=await api('status');if(!d.ok)return toast(0,d.message);
$('#c-full').textContent=d.full;$('#c-incr').textContent=d.incr;$('#c-total').textContent=d.total;$('#c-time').textContent=d.latest_time||'None yet';
$('#c-stat').innerHTML=badge(d.latest_status.trim()||'');$('#recent').textContent=d.recent||'No activity yet'}
async function hist(){const d=await api('history');if(!d.ok)return toast(0,d.message);
$('#tb').innerHTML=d.items.map(i=>`<tr><td>${E(i.name)}</td><td>${E(i.type)}</td><td>${size(i.size)}</td><td>${E(i.time)}</td><td>${badge(i.verified)}</td></tr>`).join('')||'<tr><td colspan=5>No archives found</td></tr>';
$('#sv').innerHTML=d.items.map(i=>`<option>${E(i.name)}</option>`).join('');$('#sr').innerHTML=d.items.filter(i=>i.type=='Full').map(i=>`<option>${E(i.name)}</option>`).join('')}
async function act(path,out,m='POST'){const d=await api(path,m);toast(d.ok,d.message);$(out).textContent=(d.message||'')+'\n\n'+(d.output||'');stats();hist()}
$('#b-full').onclick=()=>act('backup_full','#out1');$('#b-incr').onclick=()=>act('backup_incr','#out1');
$('#b-ver').onclick=()=>$('#sv').value?act('verify?file='+encodeURIComponent($('#sv').value),'#out2'):toast(0,'Select a backup first');
$('#b-res').onclick=()=>{const f=$('#sr').value;if(!f)return toast(0,'Select a full backup');
if(confirm(`Restore ${f} into a new folder under restore/ ?\nOriginal source files will NOT be touched.`))act('restore?confirm=yes&file='+encodeURIComponent(f),'#out3')};
async function logs(){const d=await api('logs');$('#out4').textContent=d.ok?`[${d.file}]\n`+d.text:d.message}
async function cron(){const d=await api('cron');$('#out5').textContent=d.ok?(d.entries||'(no cron jobs)')+`\n\ncron service: ${d.service||'unknown'}\nDashboard job: ${d.ours?'ACTIVE':'not set'}`:d.message}
$('#b-log').onclick=logs;
$('#b-sch').onclick=async()=>{if(confirm('Add daily full backup at 8:00 PM to your crontab? Other jobs are kept.')){await act('schedule?confirm=yes','#out5');cron()}};
const load={dash:stats,history:hist,verify:hist,restore:hist,logs:logs,sched:cron};
document.querySelectorAll('nav a').forEach(a=>a.onclick=()=>{document.querySelectorAll('nav a').forEach(x=>x.classList.remove('on'));a.classList.add('on');
document.querySelectorAll('section').forEach(s=>s.hidden=s.id!=a.dataset.p);(load[a.dataset.p]||(()=>{}))()});
stats();hist();
