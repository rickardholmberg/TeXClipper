# TeXClipper Tests

This directory contains unit tests for TeXClipper.

## Test Files

- **MathRendererTests.swift** - Tests for LaTeX rendering to SVG and PDF
- **ClipboardManagerTests.swift** - Tests for clipboard operations and metadata handling

## Adding Tests to Xcode

To add the test target to your Xcode project:

1. Open `TeXClipper.xcodeproj` in Xcode
2. Go to File → New → Target
3. Select "macOS" → "Unit Testing Bundle"
4. Name it "TeXClipperTests"
5. Add the test files from the `TeXClipperTests` directory to the test target
6. In the test target's Build Settings:
   - Set "Host Application" to TeXClipper
   - Ensure "Bundle Loader" points to the TeXClipper app
7. In the test target's Build Phases → Link Binary With Libraries:
   - Add the TeXClipper framework/target

## Running Tests

### In Xcode
- Press `⌘U` to run all tests
- Click the diamond icon next to individual tests to run them

### Command Line
```bash
xcodebuild test -scheme TeXClipper -destination 'platform=macOS'
```

## Test Coverage

The tests cover:

### MathRenderer Tests
- ✓ SVG rendering (display and inline modes)
- ✓ PDF rendering with vector graphics
- ✓ LaTeX metadata extraction from SVG
- ✓ LaTeX metadata embedding in PDF annotations
- ✓ Edge cases (empty input, special characters, newlines, backslashes)
- ✓ Round-trip conversion (LaTeX → SVG → LaTeX)
- ✓ Performance benchmarks

### ClipboardManager Tests
- ✓ PDF data validation
- ✓ PDF annotation with LaTeX metadata
- ✓ SVG metadata embedding
- ✓ LaTeX extraction from PDF and SVG
- ✓ Special character handling
- ✓ Complex multi-line LaTeX
- ✓ NSImage PNG representation
- ✓ Round-trip conversions

## Requirements

Tests require:
- macOS 13.0 or later
- MathJax file in Resources (run `./setup-mathjax.sh` first)
- Accessibility permissions may be requested during clipboard tests

## Notes

- Some tests use async/await and require the WebView to initialize
- Tests automatically wait for WebView initialization (1 second delay in setUp)
- The clipboard is cleared after each test to prevent test interference
- PDF and SVG validation ensures proper file format headers
