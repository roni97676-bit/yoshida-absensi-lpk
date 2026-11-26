# Yoshida Gakkou — audit lanjutan dan Preview Release Candidate 1

Tanggal audit: 26 November 2026  
Sumber: tiga ZIP yang diunggah pada percakapan ini; backup CSV terlampir di `BACKUP_YOSHIDA_2026-11-26(2).zip`.

## 1. Backup data lama — validasi tambahan

| Pemeriksaan | Hasil |
|---|---:|
| Baris `app_docs` | 446 |
| Baris `app_users` | 6 |
| JSON `data` tidak valid | 0 |
| Duplikat composite key `(collection,id)` | 0 |
| NIS siswa tanpa kelas yang cocok | 0 |
| Kelas tanpa batch yang cocok | 0 |
| Attendance dengan NIS tanpa siswa | 0 |
| Grades dengan NIS tanpa siswa | 0 |
| Duplikat attendance `(date,nis)` | 0 |
| ID user duplikat | 0 |
| Email user duplikat | 0 |

Rincian koleksi: `attendance=219`, `audit=126`, `batches=3`, `classes=3`, `grades=60`, `presence=6`, `students=29`.

Hasil relasi yang diperiksa: semua referensi `students -> classes`, `classes -> batches`, `attendance -> students`, dan `grades -> students` cocok pada backup. Tidak ditemukan duplikat absensi untuk tanggal dan NIS yang sama.

## 2. Akun yang tercatat di backup

- Total akun: 6; semuanya berstatus aktif pada snapshot.
- Role snapshot: `{'sensei': 5, 'admin': 1}`.
- Akun dengan nama `TESTER` masih tersimpan dengan role `sensei` pada backup. Paket Tahap 2 menambah pilihan role `tester`, tetapi tidak otomatis mengubah akun tersebut. Perubahan role itu perlu keputusan pemilik.
- Master Admin lama teridentifikasi dari UUID `860c2a25-63cb-4b86-af1b-f57e19a585ed`; migration v2 memeriksa UUID, email backup, role `admin`, status aktif, dan hanya satu legacy admin.

## 3. Perbaikan yang masuk ke paket RC1

1. Menambahkan `config.example.js` karena `index.html` memuat `config.js`, sedangkan file konfigurasi belum ada di ZIP. File contoh hanya berisi placeholder; tidak ada secret key.
2. Migration v2 memeriksa identitas/keaktifan owner sebelum perubahan, tidak mengaktifkan ulang akun secara diam-diam, menormalkan `is_master`, dan tidak mengubah data `app_docs` atau RLS policies.
3. Edge Function sekarang memvalidasi body, role, izin boolean, email, dan status aktif; akun Master Admin tidak dapat dihapus/dinonaktifkan atau diubah role/permissions melalui endpoint.
4. Menambahkan SQL diagnostik read-only untuk mengekspor schema, constraints, RLS policies, functions, triggers, grants, dan hitungan data Preview menjadi satu JSON.


## 4. Perbaikan aplikasi dan RLS yang disiapkan untuk RC1

1. Izin `edit` kini membatasi tanggal absensi lampau pada antarmuka; tanggal harian memakai zona waktu `Asia/Jakarta` agar selaras dengan kebijakan database untuk tanggal sekolah.
2. Setiap penulisan absensi, nilai, kehadiran online, dan audit menyertakan `byId` dari UUID akun Supabase yang sedang login.
3. Hak edit nilai mengenali `byId` dan tetap mendukung data lama melalui `byPhone` selama belum ada `byId`.
4. Penghapusan siswa satuan maupun massal dialihkan ke RPC `yg_delete_students_with_history`, sehingga riwayat absensi dan nilai dihapus dalam satu transaksi dan tidak mengandalkan baris yang kebetulan terlihat oleh filter RLS pengguna.
5. Draft migration `20261126_tahap2_permission_hardening_REVIEW_v1.sql` mengganti kebijakan `app_docs` lama: daftar siswa/kelas/batch tetap terbaca oleh akun aktif untuk kegiatan mengajar; akses riwayat absensi/nilai dibatasi oleh izin `rekap`, `edit`, atau kepemilikan; perubahan absensi lampau memerlukan `edit`; penghapusan siswa harus melalui RPC.
6. Migration hardening bersifat fail-closed terhadap policy `app_docs` yang tidak dikenal dan juga berhenti bila `FORCE ROW LEVEL SECURITY` aktif. Jika project Preview memiliki policy tambahan selain policy backup dan nama policy Tahap 2 yang diharapkan, migration berhenti agar tidak menghapus aturan yang belum ditinjau.
7. Uji pemetaan `byPhone` terhadap backup menghasilkan 219/219 attendance dan 60/60 grades dapat dipetakan ke tepat satu UUID akun; tidak ada nilai ambigu/tidak cocok pada snapshot tersebut. Ini adalah hasil simulasi terhadap backup, bukan hasil query project Preview live.

Catatan: checkbox `export` tetap merupakan kontrol fitur antarmuka. Karena browser perlu membaca data roster untuk menjalankan absensi dan penilaian, izin ekspor tidak dapat dianggap sebagai penghalang total terhadap pengunduhan manual data yang memang dapat dibaca oleh akun tersebut.

## 5. Temuan yang wajib diverifikasi pada Preview sebelum Production

### A. Kondisi baseline RLS

Backup RLS tanggal 26 November memperlihatkan:
- `SELECT` semua `app_docs` diberikan kepada semua pengguna aktif.
- `INSERT/UPDATE/DELETE` untuk `attendance`, `presence`, dan `grades` juga didasarkan pada `yg_is_active()`, bukan seluruhnya pada izin atau kepemilikan record.
- Checkbox `rekap` dan `export` pada baseline terutama menjadi kontrol antarmuka; policy baca lama tidak mencegah pengguna aktif mengambil seluruh data langsung melalui API.
- UI lama membatasi edit/hapus nilai berdasarkan `can('edit')` atau `byPhone`, tetapi RLS backup tidak sepenuhnya menegakkan pembatasan itu.

RC1 menyiapkan migration permission hardening untuk mengganti baseline tersebut. Migration belum dijalankan pada project mana pun. Karena itu keamanan RLS yang aktif sekarang belum berubah sampai migration tersebut berhasil dijalankan dan diuji di Preview.

### B. Policy `batches` dan policy tambahan

Backup policy insert/update master data mencakup `students`, `classes`, dan `batches` untuk pengguna dengan `yg_can_manage_students()`. Policy delete `batches` menggunakan `yg_is_admin()`, yang setelah migration v2 berarti khusus Master Admin. Migration hardening RC1 memeriksa policy yang tidak dikenal dan akan berhenti bila project Preview memiliki policy tambahan yang belum direkonsiliasi.

### C. Snapshot Preview aktual belum tersedia

Belum ada snapshot aktual dari project Supabase Preview pada sesi ini. Maka belum bisa dipastikan apakah schema, policies, grants, triggers, counts dan timezone project yang hidup sama dengan backup. Diagnostics read-only disediakan untuk mendapatkan bukti tersebut.

### D. Catatan batas izin `export`

Karena frontend perlu membaca roster untuk absensi dan penilaian, `export` masih merupakan pembatas fitur unduh di UI, bukan jaminan bahwa data roster yang dapat dibaca tidak bisa disalin manual. Jangan menganggap checkbox `export` sebagai data-loss-prevention.

## 6. Belum dilakukan

- Tidak ada SQL yang dijalankan ke Supabase.
- Tidak ada deploy Edge Function.
- Tidak ada commit/push GitHub.
- Tidak ada deploy Cloudflare.
- Tidak ada perubahan Production.

## 7. Urutan aman

1. Pastikan project Supabase PREVIEW benar-benar terpisah dari Production.
2. Jalankan `supabase/diagnostics/00_preview_readonly_audit_snapshot.sql` (satu SELECT, read-only) dan simpan hasil JSON.
3. Cocokkan jumlah dokumen, user, policy, fungsi, trigger, grants dan timezone dengan backup serta desain RC1.
4. Ambil backup Preview terbaru setelah snapshot cocok.
5. Jalankan roles/master migration v2 pada Preview saja.
6. Jalankan diagnostics ulang dan pastikan tepat satu `is_master=true`.
7. Jalankan permission hardening RC1 hanya bila guard policy lolos dan project sesuai baseline.
8. Jalankan diagnostics ulang; bandingkan total row counts, koleksi, jumlah `byId` kosong, dan policies.
9. Deploy Edge Function `admin-users`, buat `config.js` dari `config.example.js` dengan URL + anon/publishable key Preview, lalu deploy frontend pada branch Preview.
10. Jalankan seluruh checklist Preview; Production tetap tidak disentuh sampai seluruh tes lolos.
