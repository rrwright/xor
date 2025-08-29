# Makefile for xor tool
# A Unix-style command-line utility for XOR operations on files

CC = gcc
CFLAGS = -std=c99 -Wall -Wextra -Wpedantic -O2 -D_GNU_SOURCE
TARGET = xor
SOURCE = xor.c

PREFIX = /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/share/man/man1

# Default target
all: $(TARGET)

# Build the binary
$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) -o $(TARGET) $(SOURCE)

# Install the binary
install: $(TARGET)
	install -d $(BINDIR)
	install -m 755 $(TARGET) $(BINDIR)/$(TARGET)

# Uninstall the binary
uninstall:
	rm -f $(BINDIR)/$(TARGET)

# Clean build artifacts
clean:
	rm -f $(TARGET)

# Run tests
test: $(TARGET)
	@echo "Running basic functionality test..."
	@echo "test" > test_file1.tmp
	@echo "data" > test_file2.tmp
	@./$(TARGET) test_file1.tmp test_file2.tmp > key.tmp
	@./$(TARGET) key.tmp test_file2.tmp > recovered.tmp
	@if cmp -s test_file1.tmp recovered.tmp; then \
		echo "✓ Basic test passed"; \
	else \
		echo "✗ Basic test failed"; \
		exit 1; \
	fi
	@rm -f test_file1.tmp test_file2.tmp key.tmp recovered.tmp
	@echo "All tests passed!"

# Development targets
debug: CFLAGS += -g -DDEBUG
debug: $(TARGET)

# Static analysis
lint:
	@which clang-tidy >/dev/null 2>&1 && clang-tidy $(SOURCE) -- $(CFLAGS) || echo "clang-tidy not found, skipping"

# Package for distribution
dist: clean
	@echo "Creating distribution package..."
	@mkdir -p xor-$(shell grep VERSION xor.c | head -1 | cut -d'"' -f2)
	@cp xor.c Makefile README.md LICENSE xor-$(shell grep VERSION xor.c | head -1 | cut -d'"' -f2)/
	@tar -czf xor-$(shell grep VERSION xor.c | head -1 | cut -d'"' -f2).tar.gz xor-$(shell grep VERSION xor.c | head -1 | cut -d'"' -f2)
	@rm -rf xor-$(shell grep VERSION xor.c | head -1 | cut -d'"' -f2)
	@echo "Created xor-$(shell grep VERSION xor.c | head -1 | cut -d'"' -f2).tar.gz"

# Help target
help:
	@echo "Available targets:"
	@echo "  all      - Build the xor binary (default)"
	@echo "  install  - Install to $(PREFIX)/bin"
	@echo "  uninstall- Remove from $(PREFIX)/bin"
	@echo "  clean    - Remove build artifacts"
	@echo "  test     - Run basic functionality tests"
	@echo "  debug    - Build with debug symbols"
	@echo "  lint     - Run static analysis (requires clang-tidy)"
	@echo "  dist     - Create distribution package"
	@echo "  help     - Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  CC       - C compiler (default: gcc)"
	@echo "  PREFIX   - Installation prefix (default: /usr/local)"
	@echo "  CFLAGS   - Compiler flags"

.PHONY: all install uninstall clean test debug lint dist help