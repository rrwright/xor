#!/bin/bash
set -euo pipefail

# XOR Tool Test Suite
# Tests functionality, error handling, and argument validation

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

cleanup() {
    # Clean up temp files
    rm -f test_*.tmp single_*.tmp stdin_result*.tmp recovered_*.tmp expected_*.tmp progress_output.tmp xor_result.tmp *.tmp
    rmdir testdir 2>/dev/null || true
}
trap cleanup EXIT

pass_test() {
    echo -e "${GREEN}✓ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail_test() {
    echo -e "${RED}✗ $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_error() {
    local name="$1"
    local expected_error="$2"
    shift 2
    local cmd=("$@")
    
    echo -ne "${YELLOW}Testing error: $name${NC} ... "
    
    if output=$("${cmd[@]}" 2>&1); then
        fail_test "$name - expected error but command succeeded"
        echo "  Output: $output"
    else
        if [[ "$output" == *"$expected_error"* ]]; then
            pass_test "$name"
        else
            fail_test "$name - wrong error message"
            echo "  Expected: $expected_error"
            echo "  Got: $output"
        fi
    fi
}

test_roundtrip() {
    local name="$1"
    local file1="$2"
    local file2="$3"
    
    echo -e "${YELLOW}Testing: $name${NC}"
    
    # XOR file1 and file2 to get result
    ./xor "$file1" "$file2" > xor_result.tmp
    
    # XOR result with file2 to recover file1
    ./xor xor_result.tmp "$file2" > recovered_file1.tmp
    
    # XOR result with file1 to recover file2
    ./xor xor_result.tmp "$file1" > recovered_file2.tmp
    
    # Compare sizes to determine expected behavior
    local size1=$(wc -c < "$file1")
    local size2=$(wc -c < "$file2")
    local max_size=$((size1 > size2 ? size1 : size2))
    
    # With zero stripping, recovered files should match original files exactly
    # (trailing zeros from padding are stripped)
    local success=true
    if ! cmp -s "$file1" recovered_file1.tmp; then
        success=false
    fi
    if ! cmp -s "$file2" recovered_file2.tmp; then
        success=false
    fi
    
    if [ "$success" = "true" ]; then
        pass_test "$name roundtrip test"
    else
        fail_test "$name roundtrip test - files differ"
        echo "  File1 size: $size1, File2 size: $size2, Max size: $max_size"
        echo "  Recovered file1 size: $(wc -c < recovered_file1.tmp)"
        echo "  Recovered file2 size: $(wc -c < recovered_file2.tmp)"
    fi
    
    rm -f xor_result.tmp recovered_file1.tmp recovered_file2.tmp
}

echo "=== XOR Tool Comprehensive Test Suite ==="
echo

# Create test files
echo -n "hello world" > test_text.tmp
printf '\x00\x01\x02\x03\xFF\xFE\xFD\xFC' > test_binary.tmp
touch test_empty.tmp
echo -e "Line 1\nLine 2\nSpecial: àáâã\x00\xFF" > test_multiline.tmp

# Create additional test files for roundtrip tests
echo -n "key_data_123" > test_key.tmp
echo -n "binary_key" > test_binary_key.tmp
printf 'large_file_content_with_more_data_123456789' > test_large.tmp
printf 'small' > test_small.tmp

# Basic functional tests
test_roundtrip "Simple text" test_text.tmp test_key.tmp
test_roundtrip "Binary data" test_binary.tmp test_binary_key.tmp
test_roundtrip "Empty file with text" test_empty.tmp test_text.tmp
test_roundtrip "Multiline text" test_multiline.tmp test_key.tmp
test_roundtrip "Different sized files" test_large.tmp test_small.tmp


echo
echo -e "${BLUE}=== Different Length File Tests ===${NC}"
echo

# Test different length files
test_roundtrip "Large vs small files" test_large.tmp test_small.tmp

# Test single byte files
echo -n "A" > single_a.tmp
echo -n "B" > single_b.tmp
test_roundtrip "Single byte files" single_a.tmp single_b.tmp

echo
echo -e "${BLUE}=== Argument Validation Tests ===${NC}"
echo

# Error tests
test_error "No arguments" "requires exactly two file arguments" ./xor
test_error "One argument only" "requires exactly two file arguments" ./xor test_text.tmp
test_error "Too many arguments" "requires exactly two file arguments" ./xor test_text.tmp test_binary.tmp test_multiline.tmp
test_error "Nonexistent first file" "first input file not found" ./xor nonexistent.tmp test_text.tmp
test_error "Nonexistent second file" "second input file not found" ./xor test_text.tmp nonexistent.tmp
test_error "Same file twice" "cannot use the same file for both inputs" ./xor test_text.tmp test_text.tmp

# Create directory for testing
mkdir -p testdir
test_error "Directory as first file" "first input file is not a readable file" ./xor testdir test_text.tmp
test_error "Directory as second file" "second input file is not a readable file" ./xor test_text.tmp testdir

echo
echo -e "${BLUE}=== stdin/stdout Tests ===${NC}"
echo

# Test stdin for first file
echo -ne "${YELLOW}Testing: stdin for first file${NC} ... "
if echo -n "stdin_test" | ./xor - test_text.tmp > stdin_result1.tmp; then
    # Verify we can recover the original
    if ./xor stdin_result1.tmp test_text.tmp > recovered_stdin1.tmp; then
        # With zero stripping, recovered should match original exactly
        echo -n "stdin_test" > expected_stdin.tmp
        
        if cmp -s expected_stdin.tmp recovered_stdin1.tmp; then
            pass_test "stdin for first file"
        else
            fail_test "stdin for first file - recovery failed"
        fi
    else
        fail_test "stdin for first file - recovery command failed"
    fi
else
    fail_test "stdin for first file - command failed"
fi

# Test stdin for second file
echo -ne "${YELLOW}Testing: stdin for second file${NC} ... "
if echo -n "stdin_test2" | ./xor test_text.tmp - > stdin_result2.tmp; then
    # Verify we can recover the original
    if ./xor stdin_result2.tmp test_text.tmp > recovered_stdin2.tmp; then
        # Create expected result (stdin_test2 padded to match test_text.tmp length)
        echo -n "stdin_test2" > expected_stdin2.tmp
        text_size=$(wc -c < test_text.tmp)
        stdin_size=$(wc -c < expected_stdin2.tmp)
        if [ "$stdin_size" -lt "$text_size" ]; then
            dd if=/dev/zero bs=1 count=$((text_size - stdin_size)) >> expected_stdin2.tmp 2>/dev/null
        fi
        
        if cmp -s expected_stdin2.tmp recovered_stdin2.tmp; then
            pass_test "stdin for second file"
        else
            fail_test "stdin for second file - recovery failed"
        fi
    else
        fail_test "stdin for second file - recovery command failed"
    fi
else
    fail_test "stdin for second file - command failed"
fi

# Test error: both files from stdin
test_error "Both files from stdin" "cannot read multiple files from stdin" ./xor - -

echo
echo -e "${BLUE}=== Progress Mode Tests ===${NC}"
echo

# Test progress mode
echo -ne "${YELLOW}Testing: Progress mode${NC} ... "
if ./xor -p test_text.tmp test_binary.tmp > /dev/null 2>progress_output.tmp; then
    if grep -q "reading file" progress_output.tmp; then
        pass_test "Progress mode"
    else
        fail_test "Progress mode - no progress messages found"
    fi
else
    fail_test "Progress mode - command failed"
fi

rm -f stdin_result1.tmp recovered_stdin1.tmp expected_stdin.tmp
rm -f stdin_result2.tmp recovered_stdin2.tmp expected_stdin2.tmp  
rm -f progress_output.tmp single_a.tmp single_b.tmp

echo
echo -e "${BLUE}=== Preserve Zeros Tests ===${NC}"
echo

# Test preserve zeros option
echo -ne "${YELLOW}Testing: Preserve zeros short option${NC} ... "
if ./xor -z test_text.tmp test_binary.tmp > preserve_result1.tmp 2>/dev/null; then
    # Test without preserve zeros for comparison
    ./xor test_text.tmp test_binary.tmp > normal_result1.tmp 2>/dev/null
    
    # With preserve zeros, result should be longer or same size
    preserve_size=$(wc -c < preserve_result1.tmp)
    normal_size=$(wc -c < normal_result1.tmp)
    
    if [ "$preserve_size" -ge "$normal_size" ]; then
        pass_test "Preserve zeros short option (-z)"
    else
        fail_test "Preserve zeros short option (-z) - preserved result is smaller"
    fi
else
    fail_test "Preserve zeros short option (-z) - command failed"
fi

echo -ne "${YELLOW}Testing: Preserve zeros long option${NC} ... "
if ./xor --preserve-zeros test_text.tmp test_binary.tmp > preserve_result2.tmp 2>/dev/null; then
    # Compare with short option result - should be identical
    if cmp -s preserve_result1.tmp preserve_result2.tmp; then
        pass_test "Preserve zeros long option (--preserve-zeros)"
    else
        fail_test "Preserve zeros long option (--preserve-zeros) - differs from short option"
    fi
else
    fail_test "Preserve zeros long option (--preserve-zeros) - command failed"
fi

echo -ne "${YELLOW}Testing: Preserve zeros with different sized files${NC} ... "
# Create files with trailing zeros to test the difference
printf 'short' > short_file.tmp
printf 'longer_file_with_content' > long_file.tmp

if ./xor -z short_file.tmp long_file.tmp > preserve_diff_result.tmp 2>/dev/null; then
    ./xor short_file.tmp long_file.tmp > normal_diff_result.tmp 2>/dev/null
    
    preserve_diff_size=$(wc -c < preserve_diff_result.tmp)
    normal_diff_size=$(wc -c < normal_diff_result.tmp)
    
    if [ "$preserve_diff_size" -ge "$normal_diff_size" ]; then
        pass_test "Preserve zeros with different sized files"
    else
        fail_test "Preserve zeros with different sized files - preserved result is smaller"
    fi
else
    fail_test "Preserve zeros with different sized files - command failed"
fi

rm -f preserve_result1.tmp preserve_result2.tmp normal_result1.tmp
rm -f preserve_diff_result.tmp normal_diff_result.tmp short_file.tmp long_file.tmp


# Summary
echo
echo "=== Test Results ==="
echo "Total: $((TESTS_PASSED + TESTS_FAILED))"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed.${NC}"
    exit 1
fi