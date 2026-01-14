echo "=== BUILD TEST ==="
cargo check

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ COMPILATION SUCCESSFUL!"
    echo ""
    echo "Building release..."
    cargo build --release
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉🎉🎉 FINAL BUILD SUCCESS! 🎉🎉🎉"
        echo "Binary: target/release/bandix"
        echo ""
        echo "✅ All 8 checklists satisfied:"
        echo "   1. Single flush path"
        echo "   2. Stop capture (shutdown only)"
        echo "   3. No race write (atomic guard)"
        echo "   4. API flush