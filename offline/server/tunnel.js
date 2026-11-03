// ============================================================
//  الوصول من برّا — Cloudflare Tunnel
//  البيانات بتضل عالكمبيوتر؛ cloudflared بيفتح خط آمن من الكمبيوتر لـCloudflare
//  فبتفوت عالبرنامج من أي مكان على رابط متل shop1.libanapps.com — بلا فتح بورتات بالراوتر.
//  · token: نفق ثابت (بتعملو من لوحة Cloudflare وبتربطو برابط)
//  · quick: رابط مؤقت trycloudflare.com للتجربة (بيتغيّر كل مرة)
// ============================================================
'use strict';
const { spawn } = require('child_process');
const fs = require('fs');

class Tunnel {
  constructor(store, opts){
    this.store = store; this.port = opts.port; this.bin = opts.cloudflaredPath;
    this.proc = null; this.url = ''; this.log = []; this.state = 'stopped'; this.error = '';
    this._retry = 0; this._stopping = false;
  }
  get cfg(){ return this.store.kvGet('tunnel_cfg', { enabled: false, mode: 'token', token: '', hostname: '' }); }
  setCfg(v){
    const cur = this.cfg;
    const next = { enabled: !!v.enabled, mode: v.mode === 'quick' ? 'quick' : 'token',
      token: v.token !== undefined ? String(v.token).trim() : cur.token, hostname: v.hostname !== undefined ? String(v.hostname).trim().replace(/^https?:\/\//, '').replace(/\/.*$/, '') : cur.hostname };
    // اللصق ممكن يكون الأمر كامل: cloudflared ... --token eyJ...
    const m = next.token.match(/eyJ[A-Za-z0-9_\-=]+/); if(m) next.token = m[0];
    if(next.enabled && next.mode === 'token' && !next.token) throw new Error('حط رمز النفق (Tunnel token)');
    this.store.kvSet('tunnel_cfg', next);
    this.stop();
    if(next.enabled) this.start();
    return this.status();
  }
  status(){
    const c = this.cfg;
    const url = c.mode === 'token' ? (c.hostname ? 'https://' + c.hostname : '') : this.url;
    return { enabled: c.enabled, mode: c.mode, hasToken: !!c.token, hostname: c.hostname, state: this.state, url,
      error: this.error, available: this.available(), log: this.log.slice(-12) };
  }
  available(){ try{ return !!this.bin && fs.existsSync(this.bin); }catch(e){ return false; } }
  _push(line){ this.log.push(new Date().toLocaleTimeString() + '  ' + line); if(this.log.length > 200) this.log.shift(); }
  start(){
    const c = this.cfg;
    if(!c.enabled || this.proc) return;
    if(!this.available()){ this.state = 'error'; this.error = 'ملف cloudflared مش موجود مع البرنامج'; return; }
    const local = 'http://127.0.0.1:' + this.port;
    const args = c.mode === 'quick'
      ? ['tunnel', '--no-autoupdate', '--url', local]
      : ['tunnel', '--no-autoupdate', 'run', '--token', c.token];
    this._stopping = false; this.state = 'starting'; this.error = ''; this.url = '';
    const p = spawn(this.bin, args, { windowsHide: true });
    this.proc = p;
    const onData = d => String(d).split(/\r?\n/).filter(Boolean).forEach(line => {
      this._push(line.replace(/eyJ[A-Za-z0-9_\-=]{20,}/g, '***'));
      const m = line.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
      if(m){ this.url = m[0]; this.state = 'running'; }
      if(/Registered tunnel connection|Connection [a-f0-9-]+ registered/i.test(line)){ this.state = 'running'; this._retry = 0; }
      if(/Unauthorized|invalid token|failed to unmarshal/i.test(line)) this.error = 'رمز النفق غلط';
    });
    p.stdout.on('data', onData); p.stderr.on('data', onData);
    p.on('error', e => { this.error = String(e.message); });
    p.on('exit', code => {
      this.proc = null;
      if(this._stopping){ this.state = 'stopped'; return; }
      this.state = 'error'; if(!this.error) this.error = 'cloudflared وقف (' + code + ') — عم نرجع نشغّلو';
      const wait = Math.min(60000, 3000 * Math.pow(2, this._retry++));
      setTimeout(() => { if(this.cfg.enabled && !this.proc) this.start(); }, wait);
    });
  }
  stop(){
    this._stopping = true;
    if(this.proc){ try{ this.proc.kill(); }catch(e){} this.proc = null; }
    this.state = 'stopped'; this.url = '';
  }
}

module.exports = { Tunnel };
