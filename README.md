# xor

A simple Python utility for XOR operations on files.

## Overview

`xor` is a command-line tool that XORs two files together, padding the shorter file with zeros to match the longer one. The tool automatically strips trailing zero bytes from the output to maintain exact file sizes during roundtrip operations.

The tool is useful for cryptographic analysis, data transformation, and understanding XOR-based encryption schemes.

```bash
./xor.py nonsense.jpg key.bin > out.jpg
```

## Installation

No installation required - this is a standalone Python script. Requires Python 3.6+.

## Usage

### Basic XOR Operation

XOR two files together:

```bash
# XOR two files
./xor.py file1.bin file2.bin > result.bin

# Using stdin for one file
cat file1.bin | ./xor.py - file2.bin > result.bin

# Using stdin for both files (not supported)
# ./xor.py - -  # This will give an error
```

## XOR Properties

The XOR tool applies a fundamental mathematical property: **if result = A ⊕ B, then A = result ⊕ B and B = result ⊕ A**.

This creates a symetric mathematical relationship between these three files. Any two of them can be XOR'd together to produce the third:

```bash
# Generate XOR result from two files
./xor.py fileA.bin fileB.bin > result.bin

# Use result + fileB to recover fileA
./xor.py result.bin fileB.bin > recovered_A.bin

# Use result + fileA to recover fileB  
./xor.py result.bin fileA.bin > recovered_B.bin

# Verify: all recovered files match originals
cmp fileA.bin recovered_A.bin      # Should match
cmp fileB.bin recovered_B.bin      # Should match
```

## Command Line Options

```
usage: xor [-h] [-p] [-z] [--version] file file

XOR two files together, padding shorter with zeros

positional arguments:
  file file             Two input files to XOR (use '-' for stdin)

options:
  -h, --help            show this help message and exit
  -p, --progress        Show progress information to stderr
  -z, --preserve-zeros  Preserve trailing zero bytes in output (default: strip them)
  --version             show program's version number and exit
```

## Examples

### Basic XOR Operations

```bash
# XOR two files
./xor.py plaintext.txt ciphertext.txt > key.bin

# Recover original by XORing result with one of the inputs
./xor.py key.bin ciphertext.txt > recovered_plaintext.txt
./xor.py key.bin plaintext.txt > recovered_ciphertext.txt
```

### Using Base64 for Text-Safe Key Storage

Since XOR results contain binary data, you can use base64 encoding to store keys in text format:

```bash
# Generate XOR result and encode as base64 text
./xor.py rick.jpg nonsense.jpg | base64 > key.txt

# Use process substitution to decode base64 key on-the-fly
./xor.py nonsense.jpg <(base64 -d -i key.txt) > recovered_rick.jpg

# Verify the roundtrip worked
cmp rick.jpg recovered_rick.jpg && echo "Perfect match!"
```

This approach is useful when you need to store binary XOR keys in text-only systems like databases, configuration files, or version control.

### Progress Mode

For large files, use progress mode to monitor processing:

```bash
# Show progress information
./xor.py -p large_file1.bin large_file2.bin > result.bin
```

### Preserve Trailing Zeros

By default, the tool strips trailing zero bytes from output to maintain exact file sizes during roundtrip operations. Use the `-z` flag to preserve these bytes:

```bash
# Preserve trailing zeros in output
./xor.py -z small_file.bin large_file.bin > result_large_with_zeros.bin

# Compare with default behavior
./xor.py small_file.bin large_file.bin > result_maybe_medium_stripped.bin

# The version that preserved trailing zeros may be larger
ls -la result_*.bin
```

This is useful when you need to maintain exact byte-for-byte output lengths or when working with file formats that require specific padding.

Note that stripping zeroes means that if the larger of the input files ends with zero bytes, then the resulting key will not be as long as the larger file. 

### Practical Applications

**Sharing Sensitive Data**: Create a one-time pad to perfectly encrypt data.

If two parties need to share a file, they can agree on some public asset to use as the key. The asset should be at least as large as the shared file, or else any data longer than the key will be left unaltered! Having chosen an asset to use as the key, XOR it with the file to be shared. The resulting output can be shared and XOR applied to the shared output on the receiving end to output the original file.

Note: to achieve cryptographic levels of data security, the key must be entirely random data produced from a high-quality cryptographic random number generator. Anything less will leave statical patterns in the resulting data which can be used to crack the encryption.

## Technical Details

- **File Padding**: Shorter files are zero-padded to match the longer file during XOR
- **Trailing Zero Handling**: Output automatically strips trailing zeros for exact roundtrip recovery (use `-z` to preserve)
- **Streaming I/O**: Memory-efficient streaming processes files of any size without loading into RAM  
- **Binary Safe**: Handles arbitrary binary data correctly
- **Process Substitution**: Supports shell process substitution for on-the-fly transformations
- **Progress Mode**: Use `-p` to show processing progress for large files
- **Unix Philosophy**: Reads stdin, writes to stdout, composable with pipes

## Testing

Run the comprehensive test suite to verify functionality:

```bash
./test_xor.sh
```

This test suite validates:
- Core XOR functionality and data integrity
- Different length file combinations and zero padding
- XOR mathematical properties and roundtrip operations
- Progress mode and streaming I/O
- Argument validation and error handling
- stdin/stdout integration
- Edge cases (empty files, single bytes, etc.)

## Use Cases

- **Cryptanalysis**: Generate keys from known plaintext/ciphertext pairs
- **Data Recovery**: Apply XOR operations to encrypted data
- **Security Research**: Analyze XOR-based encryption schemes
- **File Transformation**: Apply XOR patterns to data
- **One-time Pad Operations**: Implement perfect secrecy schemes

## Security Notice

This tool is intended for legitimate security research, cryptanalysis, and educational purposes. Users are responsible for ensuring their use complies with applicable laws and regulations.