echo "=== FIXING UNCLOSED DELIMITER IN MONITOR/MOD.RS ==="

# 1. Lihat context error
echo "1. Error at line 460: unclosed delimiter"
echo "   Function starts at line 447: pub async fn flush_final() {"

# 2. Tampilkan sekitar error
echo ""
echo "2. Showing context around error..."
sed -n '440,470p' src/monitor/mod.rs

# 3. Cek kurung kurawal dari line 447
echo ""
echo "3. Checking brace balance from line 447..."
BRACE_COUNT=0
for i in {447..460}; do
    line=$(sed -n "${i}p" src/monitor/mod.rs)
    open=$(echo "$line" | grep -o "{" | wc -l)
    close=$(echo "$line" | grep -o "}" | wc -l)
    BRACE_COUNT=$((BRACE_COUNT + open - close))
    echo "Line $i: $BRACE_COUNT braces - '$line'"
done

# 4. Cari di mana seharusnya tutup kurung
echo ""
echo "4. Looking for missing closing brace..."
# Cari dari line 447 sampai akhir file
MISSING_LINE=$(awk 'NR >= 447 { 
    open += gsub(/{/, "") 
    close += gsub(/}/, "")
    if (open == 1 && close == 0 && NR > 447) {
        print "Missing closing brace around line " NR
        print "Current line: " $0
    }
}' src/monitor/mod.rs)

if [ -n "$MISSING_LINE" ]; then
    echo "Found: $MISSING_LINE"
fi

# 5. Perbaiki dengan menutup fungsi flush_final()
echo ""
echo "5. Fixing by adding closing brace..."
# Cari baris terakhir dari fungsi flush_final()
# Asumsi fungsi berakhir sebelum fungsi berikutnya

# Cari pattern fungsi berikutnya setelah line 447
NEXT_FUNC=$(awk 'NR > 447 && /^pub (async )?fn [a-zA-Z_]/ {print NR ": " $0; exit}' src/monitor/mod.rs)

if [ -n "$NEXT_FUNC" ]; then
    NEXT_LINE=$(echo "$NEXT_FUNC" | cut -d: -f1)
    echo "Next function starts at line: $NEXT_LINE"
    
    # Tambahkan } sebelum fungsi berikutnya
    sed -i "$((NEXT_LINE - 1))i\\}" src/monitor/mod.rs
    echo "✅ Added closing brace before line $NEXT_LINE"
else
    # Jika tidak ditemukan, tambahkan di akhir file
    echo "}"
    echo "✅ Added closing brace at end of file"
fi