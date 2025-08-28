#!/usr/bin/env python3
"""
XOR Tool - XOR two files together.

A Unix-style command-line utility for XOR operations on files.
"""

import argparse
import os
import signal
import stat
import sys
from typing import Optional


__version__ = "1.0.0"

# Default chunk size for streaming operations (64KB)
CHUNK_SIZE = 65536

# Unix exit codes
EXIT_SUCCESS = 0
EXIT_ERROR = 1
EXIT_USAGE = 2

# Global interrupt state
interrupted = False

# Global progress state
show_progress = False


def signal_handler(signum, frame):
    """Handle Unix signals gracefully."""
    global interrupted
    interrupted = True
    
    if signum == signal.SIGINT:
        die("interrupted", 130)
    elif signum == signal.SIGTERM:
        die("terminated", 143)
    elif signum == signal.SIGHUP:
        die("hangup", 129)
    else:
        die("received signal", 128 + signum)


def setup_signal_handling():
    """Set up comprehensive Unix signal handling."""
    # Handle SIGPIPE gracefully for Unix pipes
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    
    # Handle other common signals
    signal.signal(signal.SIGINT, signal_handler)   # Ctrl+C
    signal.signal(signal.SIGTERM, signal_handler)  # Termination request
    signal.signal(signal.SIGHUP, signal_handler)   # Hangup (terminal closed)


def die(message: str, exit_code: int = EXIT_ERROR) -> None:
    """Print error message to stderr and exit with specified code."""
    print(f"xor: {message}", file=sys.stderr)
    sys.exit(exit_code)


def progress(message: str) -> None:
    """Print progress message to stderr if progress mode is enabled."""
    if show_progress:
        print(f"xor: {message}", file=sys.stderr)


def is_terminal(file_obj) -> bool:
    """Check if file object is connected to a terminal."""
    try:
        return file_obj.isatty()
    except (AttributeError, OSError):
        return False


def xor_chunk(chunk1: bytes, chunk2: bytes) -> bytes:
    """
    XOR two byte chunks of potentially different lengths.
    
    Pads the shorter chunk with zeros to match the longer one.
    
    Args:
        chunk1: First byte chunk
        chunk2: Second byte chunk
        
    Returns:
        XOR result as bytes
    """
    if not chunk1 and not chunk2:
        return b""
    
    max_len = max(len(chunk1), len(chunk2))
    chunk1 = chunk1.ljust(max_len, b'\x00')
    chunk2 = chunk2.ljust(max_len, b'\x00')
    
    return bytes(b1 ^ b2 for b1, b2 in zip(chunk1, chunk2))




def open_input_stream(filename: Optional[str]):
    """
    Open input stream for reading.
    
    Args:
        filename: File path or None/'-' for stdin
        
    Returns:
        File object for reading binary data
        
    Raises:
        SystemExit: On file open errors
    """
    try:
        if filename is None or filename == "-":
            return sys.stdin.buffer
        else:
            return open(filename, "rb")
    except FileNotFoundError:
        die(f"file not found: {filename}")
    except PermissionError:
        die(f"permission denied: {filename}")
    except IOError as e:
        die(f"cannot open {filename}: {e}")


def stream_xor_generate(stream1, stream2, output_stream, preserve_zeros=False):
    """
    XOR two input streams together.
    
    Args:
        stream1: First input stream
        stream2: Second input stream  
        output_stream: Output stream for result data
    """
    global interrupted
    
    try:
        progress("XORing input streams")
        bytes_processed = 0
        all_chunks = []  # Collect chunks to strip trailing zeros
        
        while not interrupted:
            chunk1 = stream1.read(CHUNK_SIZE)
            chunk2 = stream2.read(CHUNK_SIZE)
            
            if not chunk1 and not chunk2:
                break
            
            result_chunk = xor_chunk(chunk1, chunk2)
            if result_chunk:
                all_chunks.append(result_chunk)
                bytes_processed += len(result_chunk)
                
                if show_progress and bytes_processed % (CHUNK_SIZE * 16) == 0:  # Every 1MB
                    progress(f"processed {bytes_processed} bytes")
        
        # Combine all chunks and optionally strip trailing zeros
        if all_chunks:
            all_data = b"".join(all_chunks)
            
            if not preserve_zeros:
                # Strip trailing zero bytes
                all_data = all_data.rstrip(b'\x00')
            
            # Binary output - write data directly
            if all_data:
                output_stream.write(all_data)
                output_stream.flush()
                
        zero_msg = "preserved" if preserve_zeros else "after stripping trailing zeros"
        progress(f"XOR complete: {bytes_processed} bytes processed, {len(all_data) if all_chunks else 0} bytes {zero_msg}")
                
    except BrokenPipeError:
        sys.exit(0)
    except IOError:
        die("write error")






def xor_files(file1: str, file2: str, preserve_zeros: bool = False) -> None:
    """XOR two files together using streaming I/O."""
    # Check if waiting for stdin input
    stdin_count = sum(1 for f in [file1, file2] if f == "-")
    if stdin_count == 1 and is_terminal(sys.stdin):
        progress("waiting for input from stdin...")
    
    progress(f"reading file1: {file1 if file1 != '-' else 'stdin'}")
    stream1 = open_input_stream(file1)
    progress(f"reading file2: {file2 if file2 != '-' else 'stdin'}")
    stream2 = open_input_stream(file2)
    output_stream = sys.stdout.buffer
    
    if is_terminal(sys.stdout):
        progress("warning: output going to terminal (consider redirecting to file)")
    
    try:
        stream_xor_generate(stream1, stream2, output_stream, preserve_zeros)
    finally:
        if stream1 != sys.stdin.buffer:
            stream1.close()
        if stream2 != sys.stdin.buffer:
            stream2.close()


def create_parser() -> argparse.ArgumentParser:
    """Create and configure argument parser."""
    parser = argparse.ArgumentParser(
        prog="xor",
        description="XOR two files together, padding shorter with zeros",
        usage="xor [-h] [-p] [-z] [--version] file file",
        epilog=(
            "Examples:\n"
            "  xor plaintext ciphertext > result.bin     # XOR two files\n"
            "  xor file1 - < file2 > result              # Use stdin for second file\n"
            "  cat file2 | xor file1 - > result          # Use stdin for second file\n"
            "  xor -z file1 file2 > result.bin           # Preserve trailing zeros\n"
            "\n"
            "XOR Properties:\n"
            "  If result = A ⊕ B, then A = result ⊕ B and B = result ⊕ A\n"
            "  This means any two components can recover the third:\n"
            "  xor fileA fileB > result                  # XOR A and B\n"
            "  xor result fileB > recovered_A            # Recover A using result and B\n" 
            "  xor result fileA > recovered_B            # Recover B using result and A\n"
            "\n"
            f"Version {__version__}"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        "files",
        nargs=2,
        help="Two input files to XOR (use '-' for stdin)"
    )
    parser.add_argument(
        "-p", "--progress",
        action="store_true",
        help="Show progress information to stderr"
    )
    parser.add_argument(
        "-z", "--preserve-zeros",
        action="store_true",
        help="Preserve trailing zero bytes in output (default: strip them)"
    )
    parser.add_argument(
        "--version",
        action="version", 
        version=f"xor {__version__}"
    )

    return parser


def validate_file_access(filename: str, description: str) -> None:
    """Validate that a file can be read."""
    if filename == "-":
        return  # stdin is always valid
    
    if not os.path.exists(filename):
        die(f"{description} not found: {filename}", EXIT_USAGE)
    
    # Allow regular files, FIFOs (named pipes), and character devices (like /dev/fd/*)
    if not (os.path.isfile(filename) or stat.S_ISFIFO(os.stat(filename).st_mode) or stat.S_ISCHR(os.stat(filename).st_mode)):
        die(f"{description} is not a readable file: {filename}", EXIT_USAGE)
    
    if not os.access(filename, os.R_OK):
        die(f"cannot read {description}: {filename}", EXIT_USAGE)


def validate_arguments(args) -> None:
    """Validate command-line arguments for consistency and file access."""
    file1, file2 = args.files[0], args.files[1]
    
    # Validate input files
    validate_file_access(file1, "first input file")
    validate_file_access(file2, "second input file") 
    
    # Check for stdin conflicts
    stdin_count = sum(1 for f in [file1, file2] if f == "-")
    if stdin_count > 1:
        die("cannot read multiple files from stdin", EXIT_USAGE)
    
    # Check for same file
    if file1 != "-" and file2 != "-" and os.path.samefile(file1, file2):
        die("cannot use the same file for both inputs", EXIT_USAGE)


def main() -> None:
    """Main entry point."""
    setup_signal_handling()
    
    # Ensure proper encoding for output
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    if hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(encoding='utf-8', errors='replace')
    
    try:
        parser = create_parser()
        args = parser.parse_args()

        # Set global progress flag
        global show_progress
        show_progress = args.progress

        # Comprehensive argument validation
        validate_arguments(args)

        # XOR two files together
        xor_files(args.files[0], args.files[1], args.preserve_zeros)
            
    except KeyboardInterrupt:
        die("interrupted", 130)  # Standard Unix signal exit code
    except Exception as e:
        die(f"unexpected error: {e}")


if __name__ == "__main__":
    main()