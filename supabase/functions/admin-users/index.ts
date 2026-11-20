
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
    const serviceKey = secretKeys.default;

    if (!serviceKey) {
      return json({ error: 'Secret API Key default tidak ditemukan.' }, 500);
    }

    const authHeader = req.headers.get('Authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');

    if (!token) {
      return json({ error: 'Token login tidak ditemukan.' }, 401);
    }

    const admin = createClient(url, serviceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    const {
      data: { user: caller },
      error: authError,
    } = await admin.auth.getUser(token);

    if (authError || !caller) {
      return json({ error: 'Unauthorized' }, 401);
    }

    const { data: callerProfile } = await admin
      .from('app_users')
      .select('role,active')
      .eq('id', caller.id)
      .maybeSingle();

    if (
      !callerProfile ||
      callerProfile.role !== 'admin' ||
      !callerProfile.active
    ) {
      return json({
        error: 'Hanya Master Admin yang boleh mengelola akun.',
      }, 403);
    }

    const body = await req.json();
    const {
      action,
      email,
      name,
      phone,
      role,
      perms,
      password,
      active,
    } = body;

    if (!email || typeof email !== 'string') {
      return json({ error: 'Email wajib diisi.' }, 400);
    }

    const normalizedEmail = email.trim().toLowerCase();

    if (action === 'create') {
      if (!name || !password || password.length < 8) {
        return json({
          error: 'Nama dan password minimal 8 karakter wajib diisi.',
        }, 400);
      }

      const { data, error } = await admin.auth.admin.createUser({
        email: normalizedEmail,
        password,
        email_confirm: true,
      });

      if (error) {
        return json({ error: error.message }, 400);
      }

      const { error: profileError } = await admin
        .from('app_users')
        .insert({
          id: data.user.id,
          email: normalizedEmail,
          name,
          phone: phone || null,
          role: role === 'admin' ? 'admin' : 'sensei',
          perms: perms || {},
          active: true,
        });

      if (profileError) {
        await admin.auth.admin.deleteUser(data.user.id);
        return json({ error: profileError.message }, 400);
      }

      return json({ ok: true });
    }

    const {
      data: profile,
      error: profileLookupError,
    } = await admin
      .from('app_users')
      .select('id,email,role')
      .eq('email', normalizedEmail)
      .maybeSingle();

    if (profileLookupError || !profile) {
      return json({ error: 'Akun tidak ditemukan.' }, 404);
    }

    if (
      profile.id === caller.id &&
      action === 'set-active' &&
      active === false
    ) {
      return json({
        error: 'Tidak bisa menonaktifkan akun sendiri.',
      }, 400);
    }

    if (
      profile.id === caller.id &&
      action === 'update' &&
      role !== 'admin'
    ) {
      return json({
        error: 'Tidak bisa menurunkan peran akun sendiri.',
      }, 400);
    }

    if (action === 'update') {
      const patch: Record<string, unknown> = {
        name,
        phone: phone || null,
        role: role === 'admin' ? 'admin' : 'sensei',
        perms: perms || {},
        updated_at: new Date().toISOString(),
      };

      const { error } = await admin
        .from('app_users')
        .update(patch)
        .eq('id', profile.id);

      if (error) {
        return json({ error: error.message }, 400);
      }

      if (password) {
        if (password.length < 8) {
          return json({
            error: 'Password minimal 8 karakter.',
          }, 400);
        }

        const { error: pwError } =
          await admin.auth.admin.updateUserById(profile.id, {
            password,
          });

        if (pwError) {
          return json({ error: pwError.message }, 400);
        }
      }

      return json({ ok: true });
    }

    if (action === 'set-active') {
      const { error } = await admin
        .from('app_users')
        .update({
          active: !!active,
          updated_at: new Date().toISOString(),
        })
        .eq('id', profile.id);

      if (error) {
        return json({ error: error.message }, 400);
      }

      return json({ ok: true });
    }

    if (action === 'delete') {
      if (profile.id === caller.id) {
        return json({
          error: 'Tidak bisa menghapus akun sendiri.',
        }, 400);
      }

      const { error } =
        await admin.auth.admin.deleteUser(profile.id);

      if (error) {
        return json({ error: error.message }, 400);
      }

      return json({ ok: true });
    }

    return json({ error: 'Aksi tidak dikenal.' }, 400);

  } catch (e) {
    return json({
      error: e instanceof Error ? e.message : 'Internal error',
    }, 500);
  }
});
