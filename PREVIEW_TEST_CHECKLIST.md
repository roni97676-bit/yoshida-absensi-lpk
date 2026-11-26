# Preview test checklist — Yoshida Gakkou Tahap 2

## Persiapan
- [ ] Pastikan URL project pada `config.js` adalah Supabase PREVIEW, bukan Production.
- [ ] `config.js` dibuat dari `config.example.js`; gunakan anon/publishable key Preview saja.
- [ ] Edge Function `admin-users` di-deploy pada project Preview dengan secret backend yang benar.
- [ ] Roles/master migration v2 berhasil di Preview dan hasil post-check: tepat satu `is_master=true`.
- [ ] Snapshot RLS dan timezone Preview sudah diperiksa; tidak ada policy `app_docs` tak dikenal.
- [ ] Permission hardening RC1 berhasil; hitungan koleksi tidak berubah dan jumlah `attendance/grades` tanpa `byId` sudah diperiksa.
- [ ] RPC `yg_delete_students_with_history` tersedia dan hanya dapat dipanggil akun berizin `siswa` atau Master.

## Master Admin
- [ ] Login berhasil.
- [ ] Menu `Sensei & Hak Akses` dan `Riwayat Perubahan` tampil.
- [ ] Daftar akun tampil.
- [ ] Buat akun baru berhasil dan akun baru bukan Master Admin.
- [ ] Ubah role/perms akun biasa berhasil.
- [ ] Ubah nama/telepon/password akun Master dapat dilakukan; role dan perms Master tetap tidak berubah.
- [ ] Endpoint menolak menonaktifkan atau menghapus Master Admin.

## Sensei / Admin / Tester
- [ ] Akun dengan `perms.siswa=true` dapat mengelola siswa/kelas/batch sesuai policy yang sudah diverifikasi.
- [ ] Role `admin` tanpa izin tambahan tidak otomatis mendapat hak Master Admin.
- [ ] Akun Tester hanya melihat menu sesuai checkbox izin.
- [ ] Akun nonaktif tidak dapat mengakses data.
- [ ] Hak baca/tulis langsung via API cocok dengan keputusan RLS (bukan hanya tampilan).

## Data dan fungsi
- [ ] Dashboard memuat 29 siswa dari snapshot uji (atau jumlah aktual Preview yang disetujui).
- [ ] Batch dan kelas terbaca dengan relasi yang benar.
- [ ] Absensi hari ini dapat disimpan dan ditampilkan ulang.
- [ ] Akun tanpa izin `edit` tidak dapat memilih atau mengubah absensi tanggal lampau.
- [ ] Akun dengan izin `edit` dapat mengubah absensi tanggal lampau.
- [ ] Tanggal hari ini konsisten menggunakan zona waktu sekolah `Asia/Jakarta`.
- [ ] Penilaian baru dapat disimpan.
- [ ] Pengguna dapat mengubah/menghapus nilai miliknya.
- [ ] Pengguna tanpa izin `edit` tidak dapat mengubah/menghapus nilai milik Sensei lain melalui API.
- [ ] Pengguna dengan izin `edit` dapat mengubah/menghapus nilai lintas pemilik.
- [ ] Filter monitoring/rekap bekerja.
- [ ] Export PDF/CSV hanya tersedia sesuai keputusan izin.
- [ ] Realtime update dan logout/login ulang bekerja.

## Pengamanan
- [ ] Tidak ada data siswa/kelas/batch/absensi/nilai yang berubah/hilang setelah migration, kecuali backfill metadata `byId` yang jumlahnya dicatat.
- [ ] Uji hapus satu siswa dan hapus massal: siswa, absensi, dan nilai terhapus atomik; jika RPC gagal, semua tetap ada.
- [ ] Backup terbaru disimpan sebelum deploy Preview.
- [ ] Tidak ada secret/service-role key di browser, Git repository, atau file `config.js` yang dipublikasikan.
- [ ] Production tidak disentuh.
