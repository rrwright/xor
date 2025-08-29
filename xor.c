/*
 * XOR Tool - XOR two files together
 * 
 * A Unix-style command-line utility for XOR operations on files.
 * Supports streaming I/O, progress reporting, and optional zero preservation.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <signal.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdbool.h>

#define VERSION "1.0.0"
#define CHUNK_SIZE 65536  // 64KB chunks
#define PROG_NAME "xor"

// Exit codes
#define EXIT_SUCCESS 0
#define EXIT_ERROR 1
#define EXIT_USAGE 2

// Global state
static volatile sig_atomic_t interrupted = 0;
static bool show_progress = false;
static bool preserve_zeros = false;

// Function prototypes
static void signal_handler(int signum);
static void setup_signal_handling(void);
static void die(const char *message, int exit_code);
static void progress(const char *message);
static FILE *open_input_stream(const char *filename);
static void xor_files(const char *file1, const char *file2);
static void show_help(void);
static void show_version(void);
static void validate_file_access(const char *filename, const char *description);
static bool is_same_file(const char *file1, const char *file2);

static void signal_handler(int signum) {
    interrupted = 1;
    
    switch (signum) {
        case SIGINT:
            die("interrupted", 130);
            break;
        case SIGTERM:
            die("terminated", 143);
            break;
        case SIGHUP:
            die("hangup", 129);
            break;
        default:
            die("received signal", 128 + signum);
            break;
    }
}

static void setup_signal_handling(void) {
    // Handle SIGPIPE gracefully for Unix pipes
    signal(SIGPIPE, SIG_DFL);
    
    // Handle other common signals
    signal(SIGINT, signal_handler);   // Ctrl+C
    signal(SIGTERM, signal_handler);  // Termination request
    signal(SIGHUP, signal_handler);   // Hangup (terminal closed)
}

static void die(const char *message, int exit_code) {
    fprintf(stderr, "%s: %s\n", PROG_NAME, message);
    exit(exit_code);
}

static void progress(const char *message) {
    if (show_progress) {
        fprintf(stderr, "%s: %s\n", PROG_NAME, message);
    }
}

static FILE *open_input_stream(const char *filename) {
    if (filename == NULL || strcmp(filename, "-") == 0) {
        return stdin;
    }
    
    FILE *fp = fopen(filename, "rb");
    if (fp == NULL) {
        if (errno == ENOENT) {
            die("file not found", EXIT_USAGE);
        } else if (errno == EACCES) {
            die("permission denied", EXIT_USAGE);
        } else {
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg), "cannot open %s: %s", 
                    filename, strerror(errno));
            die(error_msg, EXIT_ERROR);
        }
    }
    
    return fp;
}

static void xor_files(const char *file1, const char *file2) {
    // Check if waiting for stdin input
    int stdin_count = 0;
    if (strcmp(file1, "-") == 0) stdin_count++;
    if (strcmp(file2, "-") == 0) stdin_count++;
    
    if (stdin_count == 1 && isatty(STDIN_FILENO)) {
        progress("waiting for input from stdin...");
    }
    
    char progress_msg[256];
    snprintf(progress_msg, sizeof(progress_msg), "reading file1: %s", 
            strcmp(file1, "-") == 0 ? "stdin" : file1);
    progress(progress_msg);
    FILE *stream1 = open_input_stream(file1);
    
    snprintf(progress_msg, sizeof(progress_msg), "reading file2: %s", 
            strcmp(file2, "-") == 0 ? "stdin" : file2);
    progress(progress_msg);
    FILE *stream2 = open_input_stream(file2);
    
    if (isatty(STDOUT_FILENO)) {
        progress("warning: output going to terminal (consider redirecting to file)");
    }
    
    // Buffer for collecting all output data
    unsigned char *all_data = NULL;
    size_t total_size = 0;
    size_t bytes_processed = 0;
    
    progress("XORing input streams");
    
    while (!interrupted) {
        unsigned char chunk1[CHUNK_SIZE];
        unsigned char chunk2[CHUNK_SIZE];
        
        size_t read1 = fread(chunk1, 1, CHUNK_SIZE, stream1);
        size_t read2 = fread(chunk2, 1, CHUNK_SIZE, stream2);
        
        if (read1 == 0 && read2 == 0) {
            break;  // Both streams exhausted
        }
        
        // Pad shorter chunk with zeros
        size_t max_len = (read1 > read2) ? read1 : read2;
        if (read1 < max_len) {
            memset(chunk1 + read1, 0, max_len - read1);
        }
        if (read2 < max_len) {
            memset(chunk2 + read2, 0, max_len - read2);
        }
        
        // XOR the chunks
        unsigned char *result_chunk = malloc(max_len);
        if (result_chunk == NULL) {
            die("memory allocation failed", EXIT_ERROR);
        }
        
        for (size_t i = 0; i < max_len; i++) {
            result_chunk[i] = chunk1[i] ^ chunk2[i];
        }
        
        // Append to all_data buffer
        all_data = realloc(all_data, total_size + max_len);
        if (all_data == NULL) {
            die("memory allocation failed", EXIT_ERROR);
        }
        memcpy(all_data + total_size, result_chunk, max_len);
        total_size += max_len;
        bytes_processed += max_len;
        
        free(result_chunk);
        
        if (show_progress && bytes_processed % (CHUNK_SIZE * 16) == 0) {  // Every 1MB
            snprintf(progress_msg, sizeof(progress_msg), "processed %zu bytes", bytes_processed);
            progress(progress_msg);
        }
    }
    
    // Handle trailing zeros
    size_t output_size = total_size;
    if (!preserve_zeros && total_size > 0) {
        // Strip trailing zero bytes
        while (output_size > 0 && all_data[output_size - 1] == 0) {
            output_size--;
        }
    }
    
    // Write output
    if (output_size > 0) {
        size_t written = fwrite(all_data, 1, output_size, stdout);
        if (written != output_size) {
            die("write error", EXIT_ERROR);
        }
        fflush(stdout);
    }
    
    // Progress message
    const char *zero_msg = preserve_zeros ? "preserved" : "after stripping trailing zeros";
    snprintf(progress_msg, sizeof(progress_msg), 
            "XOR complete: %zu bytes processed, %zu bytes %s", 
            bytes_processed, output_size, zero_msg);
    progress(progress_msg);
    
    // Cleanup
    free(all_data);
    if (stream1 != stdin) fclose(stream1);
    if (stream2 != stdin) fclose(stream2);
}

static void show_help(void) {
    printf("usage: %s [-h] [-p] [-z] [--version] file file\n\n", PROG_NAME);
    printf("XOR two files together, padding shorter with zeros\n\n");
    printf("positional arguments:\n");
    printf("  file file             Two input files to XOR (use '-' for stdin)\n\n");
    printf("options:\n");
    printf("  -h, --help            show this help message and exit\n");
    printf("  -p, --progress        Show progress information to stderr\n");
    printf("  -z, --preserve-zeros  Preserve trailing zero bytes in output (default: strip them)\n");
    printf("  --version             show program's version number and exit\n\n");
    printf("Examples:\n");
    printf("  %s plaintext ciphertext > result.bin     # XOR two files\n", PROG_NAME);
    printf("  %s file1 - < file2 > result              # Use stdin for second file\n", PROG_NAME);
    printf("  cat file2 | %s file1 - > result          # Use stdin for second file\n", PROG_NAME);
    printf("  %s -z file1 file2 > result.bin           # Preserve trailing zeros\n\n", PROG_NAME);
    printf("XOR Properties:\n");
    printf("  If result = A ⊕ B, then A = result ⊕ B and B = result ⊕ A\n");
    printf("  This means any two components can recover the third:\n");
    printf("  %s fileA fileB > result                  # XOR A and B\n", PROG_NAME);
    printf("  %s result fileB > recovered_A            # Recover A using result and B\n", PROG_NAME);
    printf("  %s result fileA > recovered_B            # Recover B using result and A\n\n", PROG_NAME);
    printf("Version %s\n", VERSION);
}

static void show_version(void) {
    printf("%s %s\n", PROG_NAME, VERSION);
}

static void validate_file_access(const char *filename, const char *description) {
    if (strcmp(filename, "-") == 0) {
        return;  // stdin is always valid
    }
    
    struct stat st;
    if (stat(filename, &st) != 0) {
        char error_msg[256];
        snprintf(error_msg, sizeof(error_msg), "%s not found: %s", description, filename);
        die(error_msg, EXIT_USAGE);
    }
    
    // Allow regular files, FIFOs (named pipes), and character devices
    if (!S_ISREG(st.st_mode) && !S_ISFIFO(st.st_mode) && !S_ISCHR(st.st_mode)) {
        char error_msg[256];
        snprintf(error_msg, sizeof(error_msg), "%s is not a readable file: %s", description, filename);
        die(error_msg, EXIT_USAGE);
    }
    
    if (access(filename, R_OK) != 0) {
        char error_msg[256];
        snprintf(error_msg, sizeof(error_msg), "cannot read %s: %s", description, filename);
        die(error_msg, EXIT_USAGE);
    }
}

static bool is_same_file(const char *file1, const char *file2) {
    if (strcmp(file1, "-") == 0 || strcmp(file2, "-") == 0) {
        return false;
    }
    
    struct stat st1, st2;
    if (stat(file1, &st1) != 0 || stat(file2, &st2) != 0) {
        return false;
    }
    
    return (st1.st_dev == st2.st_dev) && (st1.st_ino == st2.st_ino);
}

int main(int argc, char *argv[]) {
    setup_signal_handling();
    
    static struct option long_options[] = {
        {"help", no_argument, 0, 'h'},
        {"progress", no_argument, 0, 'p'},
        {"preserve-zeros", no_argument, 0, 'z'},
        {"version", no_argument, 0, 'V'},
        {0, 0, 0, 0}
    };
    
    int c;
    while ((c = getopt_long(argc, argv, "hpz", long_options, NULL)) != -1) {
        switch (c) {
            case 'h':
                show_help();
                exit(EXIT_SUCCESS);
                break;
            case 'p':
                show_progress = true;
                break;
            case 'z':
                preserve_zeros = true;
                break;
            case 'V':
                show_version();
                exit(EXIT_SUCCESS);
                break;
            case '?':
                exit(EXIT_USAGE);
                break;
            default:
                exit(EXIT_USAGE);
                break;
        }
    }
    
    // Check for required positional arguments
    if (argc - optind != 2) {
        fprintf(stderr, "%s: error: requires exactly two file arguments\n", PROG_NAME);
        fprintf(stderr, "Try '%s --help' for more information.\n", PROG_NAME);
        exit(EXIT_USAGE);
    }
    
    const char *file1 = argv[optind];
    const char *file2 = argv[optind + 1];
    
    // Validate arguments
    validate_file_access(file1, "first input file");
    validate_file_access(file2, "second input file");
    
    // Check for stdin conflicts
    int stdin_count = 0;
    if (strcmp(file1, "-") == 0) stdin_count++;
    if (strcmp(file2, "-") == 0) stdin_count++;
    
    if (stdin_count > 1) {
        die("cannot read multiple files from stdin", EXIT_USAGE);
    }
    
    // Check for same file
    if (is_same_file(file1, file2)) {
        die("cannot use the same file for both inputs", EXIT_USAGE);
    }
    
    // XOR the files
    xor_files(file1, file2);
    
    return EXIT_SUCCESS;
}
