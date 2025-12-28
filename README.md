# TeXClipper

A macOS menu bar app that renders LaTeX math expressions to vector graphics with reversible rendering.

## Features

- **Vector Graphics Output**: Renders LaTeX to PDF/SVG (not rasterized images)
- **System-wide Keyboard Shortcuts**: Works in any application
- **Reversible Rendering**: Extract original LaTeX from rendered math
- **Display & Inline Modes**: Support for both math display styles
- **MathJax Rendering**: High-quality typesetting using MathJax 3.2.2

## Keyboard Shortcuts

- **⌘⌥K** - Render selected LaTeX in display mode
- **⌘⌥I** - Render selected LaTeX in inline mode
- **⌘⌥⇧K** - Revert rendered math back to LaTeX source

## Installation

### From Release

1. Download `TeXClipper.zip` from the [latest release](https://github.com/yourusername/TeXClipper/releases)
2. Unzip the file
3. Remove the quarantine attribute (required for unsigned apps on macOS 15+):
   ```bash
   xattr -d -r com.apple.quarantine TeXClipper.app
   ```
4. Move `TeXClipper.app` to `/Applications`
5. Launch the app and grant Accessibility permissions when prompted in System Settings

### Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/TeXClipper.git
cd TeXClipper

# Download MathJax
./setup-mathjax.sh

# Build with Xcode
xcodebuild -scheme TeXClipper -configuration Release

# Or open in Xcode
open TeXClipper.xcodeproj
```

## Usage

### Rendering LaTeX

1. Select LaTeX code in any text editor (e.g., `\int_0^\infty \frac{1}{1+x} dx`)
2. Press **⌘⌥K** for display mode or **⌘⌥I** for inline mode
3. The rendered math is copied to your clipboard as a PDF
4. Paste it into any application (TextEdit, Pages, Keynote, etc.)

### Reverting to LaTeX

1. Select the rendered math image in your document
2. Press **⌘⌥⇧K**
3. The original LaTeX code is copied to your clipboard
4. Paste it back as editable text

## How It Works

- **Rendering**: Uses MathJax 3.2.2 to render LaTeX to SVG, then converts to PDF using WebKit
- **Metadata Storage**: LaTeX source is embedded in PDF annotations for reversibility
- **Clipboard Integration**: Seamlessly integrates with macOS clipboard and RTFD formats
- **Global Shortcuts**: Uses Carbon Events API for system-wide keyboard shortcuts

## Requirements

- macOS 13.0 or later
- Accessibility permissions (for global keyboard shortcuts)

## Technical Details

### Core Components

- **MathRenderer.swift**: WebKit-based MathJax renderer
  - Renders LaTeX to SVG using MathJax 3.2.2
  - Converts SVG to PDF with embedded annotations
  - Extracts LaTeX from PDF annotations and SVG metadata
- **ClipboardManager.swift**: Handles clipboard operations
  - Simulates keyboard shortcuts for copy/paste
  - Processes PDF, SVG, and RTFD clipboard formats
  - Embeds and extracts LaTeX metadata
- **ShortcutManager.swift**: Global keyboard shortcut handler using Carbon Events

### Metadata Embedding

LaTeX is embedded in multiple formats for maximum compatibility:

1. **PDF Annotations**: Added to PDF files for extraction from rich text documents
2. **SVG Metadata**: JSON metadata tag in SVG with original LaTeX
3. **RTFD Support**: Extracts LaTeX from attachments in rich text format

### Permissions Required

- **Sandbox**: Enabled with limited entitlements
- **Automation**: For Apple Events (clipboard access)
- **Accessibility**: For global shortcuts and system events (must be granted manually)

## Development

Built with:
- SwiftUI for the UI
- WebKit for MathJax rendering and PDF generation
- PDFKit for metadata embedding/extraction
- Carbon Events for global shortcuts
- MathJax 3.2.2 with fontCache: 'none' for pure vector output

## Troubleshooting

### App won't open / "damaged" error
- This happens when the quarantine attribute is set on unsigned apps
- Solution: `xattr -d -r com.apple.quarantine /Applications/TeXClipper.app`
- Alternatively, right-click the app and select "Open" to bypass Gatekeeper

### Shortcuts not working
- Check Accessibility permissions in System Settings > Privacy & Security
- Ensure the app is running (check menu bar for icon)

### Rendering issues
- Verify MathJax was downloaded: run `./setup-mathjax.sh`
- Check console output for JavaScript errors

### Clipboard/paste issues
- Grant Automation permissions when prompted
- Some apps may not support programmatic paste
- Try copying manually after using the shortcuts

## License

MIT License - see LICENSE file for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- [MathJax](https://www.mathjax.org/) for excellent math rendering
- Inspired by LaTeX equation editors and clipboard utilities
