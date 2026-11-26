import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

const ROLES = ['sensei', 'admin', 'tester'] as const;
const PERMISSION_KEYS = ['siswa', 'edit', 'rekap', 'export'] as const;
type Role = typeof ROLES[number];
type Permissions = Record<typeof PERMISSION_KEYS[number], boolean>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function normalizePermissions(value: unknown): Permissions | null {
  if (!isRecord(value)) return null;
  const result = {} as Permissions;
  for (const key of PERMISSION_KEYS) {
    const v = value[key];
    if (typeof v !== 'boolean') return null;
    result[key] = v;
  }
  return result;
}

function isValidEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors });
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405);
  }

  try {
    const url = Deno.env.get('SUPABASE_URL');
    const secretKeysRaw = Deno.env.get('SUPABASE_SECRET_KEYS');
    if (!url || !secretKeysRaw) {
      return json({ error: 'Konfigurasi Supabase tidak ditemukan.' }, 500);
    }

    const secretKeys = JSON.parse(secretKeysRaw);
    const serviceKey = secretKeys?.default;
    if (typeof serviceKey !== 'string' || !serviceKey) {
      return json({ error: 'Secret API Key default tidak ditemukan.' }, 500);
    }

    const authHeader = req.headers.get('Authorization') || '';
    const tokenMatch = authHeader.match(/^Bearer\s+(.+)$/i);
    if (!tokenMatch) {
      return json({ error: 'Token login tidak ditemukan.' }, 401);
    }

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const {
      data: { user: caller },
      error: authError,
    } = await admin.auth.getUser(tokenMatch[1]);
    if (authError || !caller) {
      return json({ error: 'Unauthorized' }, 401);
    }

    const { data: callerProfile, error: callerProfileError } = await admin
      .from('app_users')
      .select('is_master,active')
      .eq('id', caller.id)
      .maybeSingle();

    if (callerProfileError) {
      return json({ error: 'Gagal memeriksa hak akses pemanggil.' }, 500);
    }
    if (!callerProfile || callerProfile.is_master !== true || callerProfile.active !== true) {
      return json({ error: 'Hanya Master Admin aktif yang boleh mengelola akun.' }, 403);
    }

    const body: unknown = await req.json();
    if (!isRecord(body)) {
      return json({ error: 'Format permintaan tidak valid.' }, 400);
    }

    const action = body.action;
    const emailRaw = body.email;
    if (typeof emailRaw !== 'string') {
      return json({ error: 'Email wajib diisi.' }, 400);
    }
    const normalizedEmail = emailRaw.trim().toLowerCase();
    if (!isValidEmail(normalizedEmail)) {
      return json({ error: 'Format email tidak valid.' }, 400);
    }

    if (action === 'create') {
      const name = typeof body.name === 'string' ? body.name.trim() : '';
      const password = typeof body.password === 'string' ? body.password : '';
      const phone = typeof body.phone === 'string' ? body.phone.trim() : '';
      const role = body.role;
      const perms = normalizePermissions(body.perms);

      if (!name || password.length < 8) {
        return json({ error: 'Nama dan password minimal 8 karakter wajib diisi.' }, 400);
      }
      if (typeof role !== 'string' || !ROLES.includes(role as Role)) {
        return json({ error: 'Role akun tidak valid.' }, 400);
      }
      if (!perms) {
        return json({ error: 'Format izin tidak valid; semua izin harus bernilai true/false.' }, 400);
      }

      const { data, error } = await admin.auth.admin.createUser({
        email: normalizedEmail,
        password,
        email_confirm: true,
      });
      if (error || !data.user) {
        return json({ error: error?.message || 'Akun Auth gagal dibuat.' }, 400);
      }

      const { error: profileError } = await admin.from('app_users').insert({
        id: data.user.id,
        email: normalizedEmail,
        name,
        phone: phone || null,
        role,
        perms,
        active: true,
        is_master: false,
      });

      if (profileError) {
        await admin.auth.admin.deleteUser(data.user.id);
        return json({ error: profileError.message }, 400);
      }
      return json({ ok: true });
    }

    if (!['update', 'set-active', 'delete'].includes(String(action))) {
      return json({ error: 'Aksi tidak dikenal.' }, 400);
    }

    const { data: profile, error: profileLookupError } = await admin
      .from('app_users')
      .select('id,email,role,is_master')
      .eq('email', normalizedEmail)
      .maybeSingle();

    if (profileLookupError) {
      return json({ error: 'Gagal mencari akun.' }, 500);
    }
    if (!profile) {
      return json({ error: 'Akun tidak ditemukan.' }, 404);
    }

    if (action === 'update') {
      const name = typeof body.name === 'string' ? body.name.trim() : '';
      const phone = typeof body.phone === 'string' ? body.phone.trim() : '';
      const password = typeof body.password === 'string' ? body.password : '';
      if (!name) return json({ error: 'Nama wajib diisi.' }, 400);
      if (password && password.length < 8) {
        return json({ error: 'Password minimal 8 karakter.' }, 400);
      }

      const patch: Record<string, unknown> = {
        name,
        phone: phone || null,
        updated_at: new Date().toISOString(),
      };

      // Keep the owner account's role and permissions immutable through this endpoint.
      if (profile.is_master !== true) {
        const role = body.role;
        const perms = normalizePermissions(body.perms);
        if (typeof role !== 'string' || !ROLES.includes(role as Role)) {
          return json({ error: 'Role akun tidak valid.' }, 400);
        }
        if (!perms) {
          return json({ error: 'Format izin tidak valid; semua izin harus bernilai true/false.' }, 400);
        }
        patch.role = role;
        patch.perms = perms;
      }

      const { error: updateError } = await admin
        .from('app_users')
        .update(patch)
        .eq('id', profile.id);
      if (updateError) return json({ error: updateError.message }, 400);

      if (password) {
        const { error: pwError } = await admin.auth.admin.updateUserById(profile.id, { password });
        if (pwError) return json({ error: pwError.message }, 400);
      }
      return json({ ok: true });
    }

    if (action === 'set-active') {
      if (typeof body.active !== 'boolean') {
        return json({ error: 'Status aktif harus true atau false.' }, 400);
      }
      if (profile.is_master === true || (profile.id === caller.id && body.active === false)) {
        return json({ error: 'Akun Master Admin tidak dapat dinonaktifkan melalui endpoint ini.' }, 400);
      }
      const { error } = await admin
        .from('app_users')
        .update({ active: body.active, updated_at: new Date().toISOString() })
        .eq('id', profile.id);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    if (action === 'delete') {
      if (profile.is_master === true || profile.id === caller.id) {
        return json({ error: 'Akun Master Admin atau akun sendiri tidak dapat dihapus.' }, 400);
      }
      const { error } = await admin.auth.admin.deleteUser(profile.id);
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true });
    }

    return json({ error: 'Aksi tidak dikenal.' }, 400);
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : 'Internal error' }, 500);
  }
});
