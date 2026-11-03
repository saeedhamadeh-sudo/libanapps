/* ============================================================
   LibanApps Local — بديل محلي لمكتبة supabase-js
   البرنامج نفسه (app-alum / app-trade) ما بيتغيّر: بيحكي مع «supabase» متل العادة،
   بس هالملف بيبعت كل الطلبات للسيرفر المحلي على الكمبيوتر بدل السحابة.
   ============================================================ */
(function(){
  'use strict';
  var SID_KEY = 'la_local_sid';
  function rnd(n){ var a = new Uint8Array(n); crypto.getRandomValues(a); return Array.prototype.map.call(a, function(b){ return ('0' + b.toString(16)).slice(-2); }).join(''); }
  function sid(){
    var s = null; try{ s = localStorage.getItem(SID_KEY); }catch(e){}
    if(!s){ s = rnd(32); try{ localStorage.setItem(SID_KEY, s); }catch(e){} }
    return s;
  }
  var CONN = rnd(8);

  function post(path, body){
    return fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-LA-Sid': sid() }, body: JSON.stringify(body || {}) })
      .then(function(r){ return r.json().catch(function(){ return { data: null, error: { message: 'HTTP ' + r.status } }; }); })
      .then(function(j){ return { data: j.data === undefined ? null : j.data, error: j.error || null, status: 200 }; })
      .catch(function(e){ return { data: null, error: { message: 'TypeError: Failed to fetch', details: String(e && e.message || e), code: '' } }; });
  }

  // ---------- QueryBuilder: نفس سلسلة supabase .from().select().eq()... ----------
  function Query(table){ this.q = { t: table, op: 'select', cols: '*', f: [] }; }
  Query.prototype.select = function(cols){ if(this.q.op === 'select') this.q.cols = cols || '*'; else this.q.returning = true; return this; };
  Query.prototype.upsert = function(rows, opts){ this.q.op = 'upsert'; this.q.rows = rows; this.q.onConflict = opts && opts.onConflict; return this; };
  Query.prototype.insert = function(rows){ this.q.op = 'insert'; this.q.rows = rows; return this; };
  Query.prototype.update = function(values){ this.q.op = 'update'; this.q.values = values; return this; };
  Query.prototype['delete'] = function(){ this.q.op = 'delete'; return this; };
  Query.prototype.eq = function(c, v){ this.q.f.push([c, 'eq', v]); return this; };
  Query.prototype.neq = function(c, v){ this.q.f.push([c, 'neq', v]); return this; };
  Query.prototype.gt = function(c, v){ this.q.f.push([c, 'gt', v]); return this; };
  Query.prototype.gte = function(c, v){ this.q.f.push([c, 'gte', v]); return this; };
  Query.prototype.lt = function(c, v){ this.q.f.push([c, 'lt', v]); return this; };
  Query.prototype.lte = function(c, v){ this.q.f.push([c, 'lte', v]); return this; };
  Query.prototype.is = function(c, v){ this.q.f.push([c, 'is', v]); return this; };
  Query.prototype['in'] = function(c, arr){ this.q.f.push([c, 'in', arr || []]); return this; };
  Query.prototype.match = function(obj){ var s = this; Object.keys(obj || {}).forEach(function(k){ s.eq(k, obj[k]); }); return this; };
  Query.prototype.filter = function(c, op, v){
    if(op === 'in') return this['in'](c, parseList(v));
    this.q.f.push([c, op, v]); return this;
  };
  Query.prototype.not = function(c, op, v){
    if(op === 'in'){ this.q.f.push([c, 'notin', parseList(v)]); return this; }
    if(op === 'eq'){ this.q.f.push([c, 'neq', v]); return this; }
    if(op === 'is' && v === null){ this.q.f.push([c, 'notnull', null]); return this; }
    this.q.f.push([c, 'not.' + op, v]); return this;
  };
  Query.prototype.order = function(c, opts){ this.q.order = [c, !(opts && opts.ascending === false)]; return this; };
  Query.prototype.range = function(a, b){ this.q.range = [a, b]; return this; };
  Query.prototype.limit = function(n){ this.q.limit = n; return this; };
  Query.prototype.maybeSingle = function(){ this.q.single = 'maybe'; return this; };
  Query.prototype.single = function(){ this.q.single = 'one'; return this; };
  Query.prototype.abortSignal = function(){ return this; };
  Query.prototype.then = function(ok, bad){ return post('/local-api/q', this.q).then(ok, bad); };
  Query.prototype['catch'] = function(bad){ return this.then(null, bad); };
  Query.prototype['finally'] = function(fn){ return this.then(function(v){ fn(); return v; }, function(e){ fn(); throw e; }); };

  // '("a","b")' أو '(a,b)' → ['a','b']
  function parseList(v){
    if(Array.isArray(v)) return v;
    var s = String(v || '').trim().replace(/^\(/, '').replace(/\)$/, ''), out = [], cur = '', q = false;
    for(var i = 0; i < s.length; i++){
      var ch = s[i];
      if(q){ if(ch === '"' && s[i + 1] === '"'){ cur += '"'; i++; } else if(ch === '"'){ q = false; } else cur += ch; }
      else if(ch === '"') q = true;
      else if(ch === ','){ out.push(cur); cur = ''; }
      else cur += ch;
    }
    if(s.length) out.push(cur);
    return out;
  }

  // ---------- لايف (بدل Realtime) ----------
  function Channel(name){ this.name = name; this.handlers = []; this.es = null; }
  Channel.prototype.on = function(type, filter, cb){ this.handlers.push({ type: type, event: filter && filter.event, cb: cb }); return this; };
  Channel.prototype.subscribe = function(cb){
    var self = this;
    try{
      var es = new EventSource('/local-api/live?ch=' + encodeURIComponent(this.name) + '&conn=' + CONN);
      this.es = es;
      es.onopen = function(){ cb && cb('SUBSCRIBED'); };
      es.onmessage = function(ev){
        var m; try{ m = JSON.parse(ev.data); }catch(e){ return; }
        self.handlers.forEach(function(h){ if(h.type === 'broadcast' && (!h.event || h.event === m.event)) h.cb({ event: m.event, payload: m.payload, type: 'broadcast' }); });
      };
      es.onerror = function(){ if(es.readyState === 2){ cb && cb('CHANNEL_ERROR'); } };
    }catch(e){ cb && cb('CHANNEL_ERROR'); }
    return this;
  };
  Channel.prototype.send = function(msg){
    return fetch('/local-api/live', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ch: this.name, conn: CONN, event: msg && msg.event, payload: msg && msg.payload }) })
      .then(function(){ return 'ok'; }, function(){ return 'error'; });
  };
  Channel.prototype.unsubscribe = function(){ if(this.es){ this.es.close(); this.es = null; } return Promise.resolve('ok'); };

  // ---------- العميل ----------
  function createClient(){
    var session = { access_token: 'local', token_type: 'bearer', user: { id: 'local-owner', email: '' } };
    var client = {
      from: function(t){ return new Query(t); },
      rpc: function(name, args){ return { then: function(ok, bad){ return post('/local-api/rpc/' + encodeURIComponent(name), args || {}).then(ok, bad); } }; },
      channel: function(name){ return new Channel(name); },
      removeChannel: function(ch){ if(ch && ch.unsubscribe) ch.unsubscribe(); return Promise.resolve('ok'); },
      removeAllChannels: function(){ return Promise.resolve([]); },
      auth: {
        getSession: function(){ return Promise.resolve({ data: { session: session }, error: null }); },
        getUser: function(){ return Promise.resolve({ data: { user: session.user }, error: null }); },
        signOut: function(){ return Promise.resolve({ error: null }); },
        verifyOtp: function(){ return Promise.resolve({ data: { session: session }, error: null }); },
        refreshSession: function(){ return Promise.resolve({ data: { session: session }, error: null }); },
        onAuthStateChange: function(){ return { data: { subscription: { unsubscribe: function(){} } } }; },
        signInWithPassword: function(){ return Promise.resolve({ data: null, error: { message: 'غير متاح بالنسخة المحلية' } }); }
      },
      storage: { from: function(){ var e = function(){ return Promise.resolve({ data: null, error: { message: 'التخزين السحابي غير متاح بالنسخة المحلية' } }); };
        return { upload: e, download: e, remove: e, list: e, getPublicUrl: function(){ return { data: { publicUrl: '' } }; } }; } }
    };
    return client;
  }
  window.supabase = { createClient: createClient };
})();
