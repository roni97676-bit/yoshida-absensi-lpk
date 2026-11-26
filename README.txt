YOSHIDA GAKKOU — TAHAP 2 PREVIEW RELEASE CANDIDATE 1 (RC1)

Paket ini adalah revisi kode Tahap 2 yang siap dipasang untuk UJI PREVIEW setelah snapshot project Supabase cocok. Paket ini BUKAN Production dan belum dideploy.

ISI UTAMA
- index.html: frontend Tahap 2; perbaikan izin edit tanggal absensi, tanggal Asia/Jakarta, byId, dan hapus siswa + riwayat melalui RPC.
- supabase-adapter.js: adapter Supabase.
- config.example.js: template; salin menjadi config.js dan isi URL + anon/publishable key khusus Preview.
- supabase/functions/admin-users/index.ts: Edge Function untuk pengelolaan akun, dengan validasi input dan proteksi Master Admin.
- supabase/migrations/20261126_tahap2_roles_master_REVIEWED_v2.sql: migration identitas Master Admin dan role.
- supabase/migrations/20261126_tahap2_permission_hardening_REVIEW_v1.sql: migration draft RLS, metadata byId, dan RPC hapus siswa/riwayat.
- supabase/diagnostics/00_preview_readonly_audit_snapshot.sql: satu SELECT read-only untuk mengekspor kondisi project Preview.
- docs/AUDIT_REPORT_V2.md: hasil audit dan blocker yang diketahui.
- docs/PREVIEW_TEST_CHECKLIST.md: checklist uji Preview.

PERBAIKAN RC1 YANG SUDAH DIBUAT
1. Izin `edit` membatasi akses edit absensi tanggal lampau di UI; RLS juga menegakkan batas ini.
2. Tanggal aplikasi dan kebijakan database memakai Asia/Jakarta sebagai zona waktu sekolah.
3. Catatan baru menyimpan `byId` UUID Supabase selain by/byPhone.
4. Hak edit nilai mendukung kepemilikan berdasarkan byId; data lama masih dikenali lewat byPhone sebelum byId di-backfill.
5. Penghapusan siswa satuan/massal memakai RPC transaksional agar semua riwayat absensi dan nilai terhapus bersama siswa.
6. RLS membedakan akses roster, absensi, nilai, presence, dan audit. Permission `export` tetap fitur UI, bukan jaminan bahwa data yang diperlukan untuk kegiatan belajar tak dapat disalin manual.

URUTAN EKSEKUSI WAJIB — PREVIEW SAJA
1. Pastikan project Supabase Preview benar-benar terpisah dari Production.
2. Jalankan diagnostics SQL read-only. Simpan JSON hasilnya dan cocokkan table, row counts, role, policy, fungsi, trigger, grants, dan timezone.
3. Jika dan hanya jika snapshot cocok dengan backup, ambil backup Preview terbaru.
4. Jalankan roles/master migration v2 pada Preview.
5. Jalankan ulang diagnostics dan periksa tepat satu is_master=true.
6. Periksa policy app_docs. Permission hardening RC1 sengaja abort bila ada policy app_docs yang tidak dikenal. Jangan menghapus atau mengubah policy tambahan tanpa audit.
7. Setelah snapshot cocok, jalankan permission hardening RC1 pada Preview. Catat jumlah byId yang terisi dan data count sebelum/sesudah.
8. Deploy Edge Function `admin-users` pada Preview. Supabase menyediakan SUPABASE_URL dan SUPABASE_SECRET_KEYS untuk Edge Functions; jangan menyalin secret/service-role key ke browser.
9. Salin config.example.js menjadi config.js, isi URL Preview dan anon/publishable key Preview saja.
10. Deploy frontend ke Cloudflare Pages Preview branch, bukan production branch.
11. Jalankan seluruh checklist. Production tetap tidak disentuh sampai semua tes lolos dan RLS disetujui.

BLOCKER YANG MEMERLUKAN AKSES PROJECT
- Snapshot aktual Supabase Preview belum tersedia di paket ini.
- URL dan publishable/anon key Preview belum diberikan.
- Belum ada konfirmasi project Preview terpisah dari Production.
- Belum ada deploy/tes real ke Cloudflare Pages.

PENTING
- Jangan jalankan migration apa pun di Production.
- Jangan memasukkan service-role/secret key ke `config.js`, browser, repository publik, atau Cloudflare Pages frontend.
- Bila diagnostics menemukan policy tambahan atau schema berbeda, hentikan migration hardening dan audit perbedaannya lebih dulu.
