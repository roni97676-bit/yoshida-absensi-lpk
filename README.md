# Absensi LPK Yoshida Gakkou — paket pemulihan

Paket ini untuk website absensi LPK Yoshida Gakkou yang di-host sebagai situs statis di Cloudflare Pages dan memakai Supabase Auth + Database.

## Isi penting
- `index.html` — website absensi. Pembacaan data database baru dimulai setelah sesi login terverifikasi.
- `config.js` — URL Supabase dan publishable key proyek Yoshida. Publishable key memang untuk dipakai di browser; jangan pernah memasukkan `service_role` atau secret key di sini.
- `supabase-adapter.js` — penghubung website ke Supabase.
- `supabase/schema.sql` — tabel, izin database, dan kebijakan RLS. Data aplikasi tidak dibuka untuk role `anon`.
- `supabase/functions/admin-users/index.ts` — fungsi pengelolaan akun Sensei.
- `ORIGINAL-Claude-Artifact.html` — salinan artefak awal untuk referensi, bukan file yang diunggah sebagai halaman utama.

## Cara memasang ulang ke GitHub
1. Buka repository `yoshida-absensi-lpk`.
2. Unggah isi folder ini (bukan folder pembungkus `yoshida-absensi-reset`) ke root repository.
3. Pastikan `index.html`, `config.js`, `supabase-adapter.js`, dan `supabase/` terlihat di root.
4. Commit perubahan. Cloudflare Pages akan melakukan deploy otomatis.

## Penting tentang Supabase
- Proyek Supabase yang sudah ada tetap digunakan.
- Jangan membuat proyek baru dan jangan menghapus Auth user yang sudah dibuat.
- `config.js` berisi publishable key, bukan secret key. Jangan pernah mengunggah `service_role` atau `YOSHIDA_SERVICE_ROLE_KEY` ke GitHub.
- `schema.sql` disiapkan agar dapat dijalankan ulang: ia mengatur grant untuk `authenticated`, mencabut akses tabel dari `anon`, dan mengatur RLS. Sebelum menjalankannya ulang, minta panduan langkah demi langkah agar perubahan database yang sudah ada dapat dicek dahulu.
- Edge Function `admin-users` yang sudah ada jangan dihapus. Jika perlu diperbarui, unggah isi file `supabase/functions/admin-users/index.ts` ke fungsi tersebut dan pertahankan secret `YOSHIDA_SERVICE_ROLE_KEY` yang sudah disimpan di Supabase.

## Login
Gunakan email dan password akun Supabase Auth yang sudah dibuat. Akun itu harus memiliki baris yang cocok di `public.app_users` dengan `id` sama dengan User UID Auth dan `active = true`.
