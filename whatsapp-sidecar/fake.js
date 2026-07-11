// Fake WhatsApp sidecar — a "MailCatcher for WhatsApp". Drop-in replacement for the real
// wwebjs sidecar for LOCAL, VISUAL testing: no QR, no Chromium, no real number, no ban risk.
//
//   • Reports itself permanently "connected" on /health + /session/* → the admin panel shows
//     green and WhatsappServiceHealthCheckJob is happy. This is your fake "server number".
//   • Catches Rails' outbound replies (POST /messages) and shows them as chat bubbles.
//   • Lets you send from ANY fake user number to Rails' webhook (text + image/audio/pdf,
//     with optional caption — image + text goes out as one message, like real WhatsApp).
//
// Run it INSTEAD of `npm start`:  node fake.js   (same port 3001, same shared token).
// Then open http://localhost:3001 in a browser and chat.  Reuses src/config.js verbatim.
//
// ponytail: in-memory history (lost on restart), single fake "server number". Add persistence
// only if you need chats to survive a reload.

const express = require('express');
const cors = require('cors');
const axios = require('axios');
const config = require('./src/config');

const app = express();
app.use(cors());
app.use(express.json({ limit: '25mb' })); // room for base64 image/audio inject

// ── in-memory state ─────────────────────────────────────────────────────────
const history = []; // { dir: 'in'|'out', jid, body, ts }
const clients = []; // SSE response streams
let seq = 0;

const push = (event) => {
  history.push(event);
  const line = `data: ${JSON.stringify(event)}\n\n`;
  clients.forEach((res) => res.write(line));
};

// Fire an event AT Rails, exactly like the real sidecar does (same bearer, same envelope).
const postWebhook = (event, data = {}) => axios.post(config.railsWebhookUrl, { event, data }, {
  headers: { Authorization: `Bearer ${config.railsApiToken}` }, timeout: 10000,
});

// ── fake session surface: always connected ──────────────────────────────────
const CONNECTED = { wa_status: 'connected', wa_phone: '5599999999999', state: 'CONNECTED' };
app.get('/health', (_req, res) => res.json({ ...CONNECTED, status: 'ok', connectedAt: new Date().toISOString() })); // Rails checks status=='ok'
app.get('/session/status', (_req, res) => res.json(CONNECTED));
app.get('/session/qr', (_req, res) => res.json({ qr: null, status: 'connected' })); // no QR needed
app.delete('/session', (_req, res) => res.json({ status: 'logged_out' }));
// Admin "Connect" button lands here → tell Rails we're connected so the panel flips green,
// mirroring the real sidecar's `ready` → `connected` webhook.
app.post('/session/initialize', async (_req, res) => {
  await postWebhook('connected', { phone_number: CONNECTED.wa_phone }).catch(() => {});
  res.json({ status: 'connected' });
});

// ── outbound: Rails → here. Same bearer auth + shape as the real sidecar. ─────
const auth = (req, res, next) => {
  const token = (req.headers.authorization || '').split(' ')[1];
  if (token !== config.railsApiToken) return res.status(401).json({ error: 'unauthorized' });
  next();
};
app.post('/messages', auth, (req, res) => {
  const { phone_number, chat_id, message } = req.body || {};
  const jid = chat_id || phone_number;
  if (!jid || !message) return res.status(400).json({ error: 'phone_number (or chat_id) and message are required' });
  push({ dir: 'out', jid, body: message, ts: Date.now() });
  res.json({ success: true, messageId: `fake_out_${++seq}`, error: null });
});

// ── inbound: browser → here → Rails webhook (as the real sidecar would). ──────
app.post('/_inject', async (req, res) => {
  const { jid, body, type = 'text', media } = req.body || {};
  if (!jid) return res.status(400).json({ error: 'jid required' });
  const data = { from: jid, message_id_serialized: `fake_in_${Date.now()}_${++seq}`, type, body: body || '' };
  if (media) data.media = media; // { data: <base64, no prefix>, mimetype, filename }
  const ev = { dir: 'in', jid, body: body || '', ts: Date.now() };
  if (media) { // decorate the UI event so the bubble shows the media itself (caption in body)
    const uri = `data:${media.mimetype};base64,${media.data}`;
    if (/ptt|audio|voice/.test(type)) ev.audio = uri;
    else if (type === 'image') ev.image = uri;
    else ev.doc = media.filename || 'documento';
  }
  push(ev);
  try {
    await postWebhook('message_received', data);
    res.json({ ok: true });
  } catch (err) {
    push({ dir: 'out', jid, body: `⚠️ Rails webhook error: ${err.message}`, ts: Date.now() });
    res.status(502).json({ error: err.message });
  }
});

// ── browser live feed ────────────────────────────────────────────────────────
app.get('/_state', (_req, res) => res.json(history));
app.get('/_stream', (req, res) => {
  res.set({ 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' });
  res.flushHeaders();
  clients.push(res);
  req.on('close', () => clients.splice(clients.indexOf(res), 1));
});

app.get('/', (_req, res) => res.type('html').send(PAGE));

app.listen(config.port, () => {
  console.log(`🟢 FAKE WhatsApp sidecar on http://localhost:${config.port}  →  Rails: ${config.railsWebhookUrl}`);
  console.log('   Open the URL in a browser to chat. No QR, no Chromium — Rails thinks it is connected.');
  // Announce "connected" so the admin panel flips green on its own. Rails may still be booting,
  // so retry a couple of times, then give up quietly — clicking Connect in the panel also works.
  let tries = 0;
  const announce = () => postWebhook('connected', { phone_number: CONNECTED.wa_phone })
    .then(() => console.log('   ✅ told Rails: connected (admin panel is green)'))
    .catch(() => { if (++tries < 5) setTimeout(announce, 2000); else console.log('   ⚠️ Rails not reachable yet — click Connect in /admin/whatsapp_connection'); });
  setTimeout(announce, 2500);
});

// ── the chat UI (single inline page) ─────────────────────────────────────────
// Demo-seed verified numbers are prefilled (see lib/demo_seed.rb). An UNVERIFIED number
// gets the AZUL-XXXX handshake — send a bogus number, Rails replies asking to verify.
const PAGE = /* html */ `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Fake WhatsApp</title>
<style>
  *{box-sizing:border-box} body{margin:0;font:15px/1.4 system-ui,sans-serif;background:#0b141a;color:#e9edef;display:flex;height:100vh}
  aside{width:230px;background:#111b21;border-right:1px solid #222d34;padding:12px;overflow:auto}
  aside h2{font-size:12px;text-transform:uppercase;color:#8696a0;margin:0 0 8px}
  .num{display:block;width:100%;text-align:left;padding:9px 10px;margin:4px 0;border:0;border-radius:8px;background:#202c33;color:#e9edef;cursor:pointer;font-size:13px}
  .num.active{background:#005c4b} .num small{color:#8696a0;display:block}
  main{flex:1;display:flex;flex-direction:column} header{padding:12px 16px;background:#202c33;font-weight:600}
  #log{flex:1;overflow:auto;padding:16px;display:flex;flex-direction:column;gap:8px}
  .b{max-width:70%;padding:8px 12px;border-radius:10px;white-space:pre-wrap;word-break:break-word}
  .in{align-self:flex-end;background:#005c4b} .out{align-self:flex-start;background:#202c33}
  .b time{display:block;font-size:10px;color:#ffffff88;margin-top:3px}
  .b audio{display:block;height:34px;max-width:240px}
  .b img{display:block;max-width:240px;border-radius:8px;margin-bottom:4px}
  .b .doc{display:flex;align-items:center;gap:6px;background:#ffffff14;border-radius:8px;padding:8px 10px;margin-bottom:4px}
  #fn{font-size:11px;color:#00a884;max-width:120px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  form{display:flex;gap:8px;padding:12px;background:#202c33}
  input[type=text]{flex:1;padding:10px;border:0;border-radius:20px;background:#2a3942;color:#e9edef}
  button.send{padding:0 18px;border:0;border-radius:20px;background:#00a884;color:#fff;cursor:pointer}
  label.clip{display:flex;align-items:center;padding:0 10px;cursor:pointer;color:#8696a0} input[type=file]{display:none}
  button.mic{border:0;border-radius:50%;width:40px;background:#2a3942;color:#e9edef;cursor:pointer;font-size:16px}
  button.mic.rec{background:#ef4444;animation:pulse 1s infinite} @keyframes pulse{50%{opacity:.4}}
</style></head><body>
<aside>
  <h2>Números (fake)</h2>
  <div id="nums"></div>
  <input id="newjid" class="num" placeholder="+55… ou jid@c.us" style="background:#2a3942">
  <button class="num" onclick="addNum()">+ adicionar número</button>
  <p style="font-size:11px;color:#8696a0;margin-top:16px">Verificados vêm do demo seed. Um número novo dispara o handshake AZUL-XXXX.</p>
</aside>
<main>
  <header id="title">—</header>
  <div id="log"></div>
  <form onsubmit="send(event)">
    <label class="clip">📎<input type="file" id="file" accept="image/*,audio/*,application/pdf" onchange="pickFile()"><span id="fn"></span></label>
    <button type="button" class="mic" id="mic" onclick="toggleRec()" title="Gravar áudio (como no WhatsApp)">🎤</button>
    <input type="text" id="msg" placeholder="Mensagem (ex: gastei 42 no mercado no débito)" autocomplete="off">
    <button class="send" type="submit">Enviar</button>
  </form>
</main>
<script>
  const seed = [
    { jid: '5511987654321@c.us', name: 'Marina (verificada)' },
    { jid: '5511976543210@c.us', name: 'Rafael (verificado)' },
  ];
  let nums = [...seed], active = seed[0].jid, all = [];
  const el = (id) => document.getElementById(id);
  function renderNums(){ el('nums').innerHTML=''; nums.forEach(n=>{ const b=document.createElement('button');
    b.className='num'+(n.jid===active?' active':''); b.innerHTML=n.name+'<small>'+n.jid+'</small>';
    b.onclick=()=>{active=n.jid;renderNums();renderLog()}; el('nums').appendChild(b); }); el('title').textContent=active; }
  function renderLog(){ const log=el('log'); log.innerHTML='';
    all.filter(e=>e.jid===active).forEach(e=>{ const d=document.createElement('div');
      d.className='b '+e.dir;
      let h='';
      if(e.audio) h+='<audio controls src="'+e.audio+'"></audio>';
      if(e.image) h+='<img src="'+e.image+'">';
      if(e.doc) h+='<div class="doc">📄 '+esc(e.doc)+'</div>';
      if(e.body) h+=esc(e.body);
      d.innerHTML=h+'<time>'+new Date(e.ts).toLocaleTimeString()+'</time>';
      log.appendChild(d); });
    log.scrollTop=log.scrollHeight; }
  function esc(s){ return String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }
  function addNum(){ const j=el('newjid').value.trim(); if(!j)return; const jid=j.includes('@')?j:j.replace(/\\D/g,'')+'@c.us';
    if(!nums.find(n=>n.jid===jid)) nums.push({jid,name:'Novo número'}); active=jid; el('newjid').value=''; renderNums(); renderLog(); }
  const b64=(blob)=>new Promise(r=>{const fr=new FileReader();fr.onload=()=>r(fr.result.split(',')[1]);fr.readAsDataURL(blob)});
  const inject=(payload)=>fetch('/_inject',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
  function pickFile(){ const f=el('file').files[0]; el('fn').textContent=f?f.name:''; }
  async function send(ev){ ev.preventDefault(); const body=el('msg').value; const f=el('file').files[0];
    if(!body && !f) return;
    let payload={ jid:active, body };
    if(f){ payload.type=f.type.startsWith('audio')?'audio':f.type==='application/pdf'?'document':'image';
      payload.media={ data:await b64(f), mimetype:f.type, filename:f.name }; el('file').value=''; el('fn').textContent=''; }
    el('msg').value=''; inject(payload); }
  // Record a voice note like WhatsApp and send it as a 'ptt'. MediaRecorder captures cleanly on
  // the audio thread (the old ScriptProcessorNode ran on the main thread and dropped buffers,
  // glitching speech → garbage transcripts). We then decode to PCM and re-encode WAV, because
  // Groq's decoder rejects Chrome's webm (unfinalized duration header) but always accepts WAV.
  // Keep the mic stream warm after the first grant so later recordings start INSTANTLY —
  // getUserMedia device warmup is the ~1.5s "takes a while to start" delay. The button shows ⏳
  // only while acquiring (first time); start talking once you see the red ⏹. ponytail: the tab's
  // mic indicator stays on for the session; release with micStream.getTracks stop() on unload.
  let rec, chunks, micStream;
  async function toggleRec(){ const btn=el('mic');
    if(rec && rec.state==='recording'){ rec.stop(); return; }
    if(!micStream){ btn.textContent='⏳';
      micStream=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true}}); }
    for(let n=3;n>0;n--){ btn.textContent=n; await new Promise(r=>setTimeout(r,1000)); }  // 3-2-1 get-ready countdown
    rec=new MediaRecorder(micStream); chunks=[];
    rec.ondataavailable=e=>chunks.push(e.data);
    rec.onstop=async()=>{ btn.textContent='🎤'; btn.classList.remove('rec');
      const ac=new AudioContext(); const audio=await ac.decodeAudioData(await new Blob(chunks).arrayBuffer()); ac.close();
      const data=await b64(encodeWav(audio.getChannelData(0), audio.sampleRate));
      inject({ jid:active, type:'ptt', body:'', media:{ data, mimetype:'audio/wav', filename:'voice.wav' } }); };
    rec.start(); btn.textContent='⏹'; btn.classList.add('rec'); }
  function encodeWav(samples, rate){
    const len=samples.length, buf=new ArrayBuffer(44+len*2), v=new DataView(buf);
    const w=(o,s)=>{for(let i=0;i<s.length;i++)v.setUint8(o+i,s.charCodeAt(i));};
    w(0,'RIFF'); v.setUint32(4,36+len*2,true); w(8,'WAVE'); w(12,'fmt '); v.setUint32(16,16,true);
    v.setUint16(20,1,true); v.setUint16(22,1,true); v.setUint32(24,rate,true); v.setUint32(28,rate*2,true);
    v.setUint16(32,2,true); v.setUint16(34,16,true); w(36,'data'); v.setUint32(40,len*2,true);
    let o=44; for(let i=0;i<len;i++){ const s=Math.max(-1,Math.min(1,samples[i])); v.setInt16(o,s<0?s*0x8000:s*0x7fff,true); o+=2; }
    return new Blob([buf],{type:'audio/wav'}); }
  const es=new EventSource('/_stream'); es.onmessage=(m)=>{ all.push(JSON.parse(m.data)); if(!nums.find(n=>n.jid===JSON.parse(m.data).jid)){}; renderLog(); };
  fetch('/_state').then(r=>r.json()).then(h=>{all=h;renderLog()}); renderNums();
</script></body></html>`;
