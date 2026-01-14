# Backup dulu
cp src/command.rs src/command.rs.backup2

# Hapus duplikat imports dan FLUSH_IN_PROGRESS
# Cek file terlebih dahulu
echo "=== Checking command.rs for duplicates ==="
head -20 src/command.rs

# Hapus baris duplikat (baris 6-14 mungkin duplikat)
sed -i '6,14d' src/command.rs

# Verifikasi
echo "=== After cleanup ==="
head -15 src/command.rs