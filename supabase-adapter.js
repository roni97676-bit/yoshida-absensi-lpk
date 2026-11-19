(() => {
  const cfg = window.YOSHIDA_CONFIG || {};
  if (!window.supabase || !cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY || cfg.SUPABASE_URL.includes('YOUR-PROJECT')) {
    window.ygConfigError = 'Konfigurasi Supabase belum diisi. Salin config.example.js menjadi config.js dan isi URL serta anon key.';
    return;
  }
  const sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  window.ygSupabase = sb;
  const snapshot = rows => ({ docs: rows.map(row => ({ id: row.__id, data: () => row.__data })) });
  class Query {
    constructor(name, sort = null, max = null) { this.name = name; this.sort = sort; this.max = max; }
    orderBy(field, direction = 'asc') { return new Query(this.name, {field, direction}, this.max); }
    limit(n) { return new Query(this.name, this.sort, n); }
    async rows() {
      if (this.name === 'users') {
        const {data,error} = await sb.from('app_users').select('*');
        if (error) throw error;
        return (data || []).map(x => ({__id:x.email,__data:x}));
      }
      let q = sb.from('app_docs').select('id,data').eq('collection', this.name);
      const {data,error} = await q;
      if (error) throw error;
      let rows = (data || []).map(x => ({__id:x.id,__data:x.data || {}}));
      if (this.sort) {
        const f = this.sort.field;
        rows.sort((a,b) => String(a.__data?.[f] ?? '').localeCompare(String(b.__data?.[f] ?? '')) * (this.sort.direction === 'desc' ? -1 : 1));
      }
      if (this.max) rows = rows.slice(0,this.max);
      return rows;
    }
    onSnapshot(callback, onError) {
      let dead = false, busy = false, pending = false;
      const refresh = async () => {
        if (dead) return;
        if (busy) { pending = true; return; }
        busy = true;
        try { const rows = await this.rows(); if (!dead) callback(snapshot(rows)); }
        catch(e) { if (!dead && onError) onError(e); }
        busy = false;
        if (pending) { pending = false; refresh(); }
      };
      refresh();
      const table = this.name === 'users' ? 'app_users' : 'app_docs';
      const filter = this.name === 'users' ? undefined : `collection=eq.${this.name}`;
      const channel = sb.channel(`yg-${this.name}-${Math.random().toString(36).slice(2)}`)
        .on('postgres_changes', {event:'*',schema:'public',table,...(filter?{filter}:{})}, refresh)
        .subscribe();
      return () => { dead = true; sb.removeChannel(channel); };
    }
  }
  class Doc {
    constructor(collection,id) { this.collection=collection; this.id=String(id); }
    async set(value) {
      if (this.collection === 'users') throw new Error('Akun Sensei harus dikelola melalui fungsi admin.');
      const {error} = await sb.from('app_docs').upsert({collection:this.collection,id:this.id,data:value,updated_at:new Date().toISOString()},{onConflict:'collection,id'});
      if (error) throw error;
    }
    async update(patch) {
      const {data,error} = await sb.from('app_docs').select('data').eq('collection',this.collection).eq('id',this.id).single();
      if (error) throw error;
      await this.set({...data.data,...patch});
    }
    async delete() {
      if (this.collection === 'users') throw new Error('Akun Sensei harus dikelola melalui fungsi admin.');
      const {error} = await sb.from('app_docs').delete().eq('collection',this.collection).eq('id',this.id);
      if (error) throw error;
    }
  }
  window.ygDb = { collection: name => ({
    doc: id => new Doc(name,id),
    orderBy: (field,direction) => new Query(name,{field,direction},null).orderBy(field,direction),
    limit: n => new Query(name,null,n),
    onSnapshot: (cb,err) => new Query(name).onSnapshot(cb,err)
  }) };
  window.ygDownloads = { save: async ({filename,data}) => {
    const blob = new Blob([data],{type:'text/csv;charset=utf-8'});
    const url = URL.createObjectURL(blob); const a=document.createElement('a'); a.href=url; a.download=filename; a.click(); URL.revokeObjectURL(url);
  }};
})();
