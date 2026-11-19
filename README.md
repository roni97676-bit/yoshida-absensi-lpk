# Website Absensi LPK Yoshida Gakkou — Paket UAT Online

Paket ini mengadaptasi HTML Claude Artifact ke hosting web biasa dengan Supabase Auth + PostgreSQL + Realtime. Ini adalah **lingkungan TESTING/UAT terpisah**, bukan produksi.

## Status paket

- Tampilan dan fitur dari file HTML sumber dipertahankan.
- Penyimpanan Claude Artifact (`claude.use("db")`) diganti dengan adapter Supabase.
- Login menggunakan email + password Supabase Auth.
- Akun Sensei dikelola oleh Master Admin melalui Edge Function.
- Data bersama tersimpan di tabel `app_docs` dan tersinkron realtime.
- Semua Sensei aktif dapat mengisi dan mengedit absensi tanggal sebelumnya.
- Data testing dipisah dari data operasional; gunakan siswa dummy/anonymized.

**Belum online:** paket ini belum terhubung ke project Supabase atau akun hosting milik Yoshida. Untuk membuat link publik, project Supabase dan Vercel perlu dibuat/diotorisasi oleh pemilik akun. Jangan pernah memasukkan `service_role` key ke HTML atau membagikannya ke Sensei.

## 1. Buat project Supabase khusus TESTING

1. Buat project baru di Supabase dengan nama misalnya `yoshida-absensi-uat`.
2. Pilih region terdekat dengan mayoritas pengguna (misalnya Singapore jika tersedia).
3. Simpan Project URL dan `anon`/publishable key.
4. Jangan gunakan project database produksi.

## 2. Buat tabel dan aturan keamanan

Buka SQL Editor di Supabase, lalu jalankan seluruh isi `supabase/schema.sql`.

## 3. Buat akun Master Admin pertama

1. Di Supabase → Authentication → Users → Add user, buat email dan password Master Admin.
2. Salin UUID user tersebut.
3. Di SQL Editor jalankan (ganti nilai contoh):

```sql
insert into public.app_users (id, email, phone, name, role, perms, active)
values (
  'UUID-DARI-AUTH-USERS',
  'admin@yoshida.example',
  '628123456789',
  'Master Admin Yoshida',
  'admin',
  '{"siswa":true,"edit":true,"rekap":true,"export":true}'::jsonb,
  true
);
```

Gunakan email asli yang dikelola Yoshida, bukan alamat contoh.

## 4. Konfigurasi website

Salin `config.example.js` menjadi `config.js`, isi nilai project, lalu commit file `config.js` ke repository private Yoshida (URL dan anon/publishable key memang dipakai browser dan bukan service-role secret):

```js
window.YOSHIDA_CONFIG = {
  SUPABASE_URL: 'https://PROJECT-REF.supabase.co',
  SUPABASE_ANON_KEY: 'ANON_OR_PUBLISHABLE_KEY'
};
```

`config.js` hanya boleh berisi URL project dan anon/publishable key. **Jangan masukkan service_role key.** File ini boleh berada di repository private; anon key tetap harus dilindungi oleh RLS.

## 5. Deploy Edge Function untuk manajemen akun Sensei

Install Supabase CLI di komputer admin, login, lalu dari folder project jalankan:

```bash
supabase link --project-ref PROJECT-REF
supabase secrets set SUPABASE_URL=https://PROJECT-REF.supabase.co SUPABASE_SERVICE_ROLE_KEY=SERVICE_ROLE_KEY
supabase functions deploy admin-users
```

Service role key hanya disimpan sebagai secret di Supabase Functions, bukan di file website.

## 6. Deploy ke Vercel

1. Upload folder project ini ke repository GitHub private milik Yoshida.
2. Import repository tersebut di Vercel.
3. Framework preset: Other; build command dan output directory dikosongkan/default static.
4. Pastikan `config.js` ikut ter-deploy (jangan commit key service role; anon key boleh publik).
5. Deploy, lalu buka URL Vercel dari laptop Sensei di Indonesia dan Jepang.

## 7. Uji sebelum mengundang semua Sensei

- Buat 2 akun Sensei uji melalui menu Sensei & Akses.
- Login di dua browser/perangkat berbeda.
- Ubah status absensi dari perangkat A dan pastikan perangkat B menerima perubahan.
- Edit absensi tanggal sebelumnya dari akun Sensei biasa.
- Pastikan akun nonaktif tidak bisa login/mengakses data.
- Pastikan audit log menunjukkan nama dan waktu perubahan.
- Coba impor siswa dummy dan ekspor laporan.

## Catatan penting

- Email dipakai sebagai identitas login. Nomor HP tetap disimpan sebagai data profil.
- Semua Sensei aktif mendapat akses baca data bersama dan hak tulis absensi.
- Pengelolaan akun hanya oleh Master Admin.
- Data asli siswa jangan diimpor sebelum aturan akses, backup, dan pengujian keamanan disetujui.
- File ini masih perlu pengujian end-to-end setelah dikonfigurasi pada project Supabase milik Yoshida.
