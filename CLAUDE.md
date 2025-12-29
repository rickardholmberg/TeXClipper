# Development Guide for TeXClipper

This document outlines coding standards and best practices for TeXClipper development.

## Code Quality Standards

### Testing Requirements
- **Always add tests** for new functionality
- Run full test suite before committing: `xcodebuild test -scheme TeXClipper -destination 'platform=macOS'`
- All tests must pass in CI/CD pipeline before merging
- Current test coverage: ClipboardManager (10 tests), MathRenderer (14 tests)
- Test async operations properly using `async/await` syntax

### Security

**Critical:** This app processes user input and executes JavaScript. Follow these rules:

1. **Input Sanitization**
   - Never interpolate user input directly into JavaScript strings
   - Use `JSONEncoder` for passing data to JavaScript (see [MathRenderer.swift:191-196](TeXClipper/Services/MathRenderer.swift#L191-L196))
   - Validate and sanitize all clipboard data before processing

2. **WebKit Configuration**
   - Never enable `allowFileAccessFromFileURLs` in production
   - Developer extras (`developerExtrasEnabled`) must be `#if DEBUG` only
   - Keep WebView configuration minimal and secure

3. **Common Vulnerabilities to Avoid**
   - JavaScript injection (XSS)
   - Command injection
   - Path traversal
   - Unsafe deserialization

### Code Style

#### Swift Best Practices
- Use Swift concurrency (`async/await`) for asynchronous operations
- Prefer `MainActor` annotations for UI-related code
- Use weak references (`[weak self]`) in closures to prevent retain cycles
- Follow Swift naming conventions (camelCase for methods/properties)

#### Architecture
- **Strategy Pattern**: Use for extensible functionality (see LaTeX extraction strategies)
- **Single Responsibility**: Keep methods focused and under ~50 lines
- **DRY Principle**: Extract common patterns into helper methods
- Avoid over-engineering - only add abstraction when needed

#### Error Handling
- Use Swift's `Result` type or `throws` for recoverable errors
- Provide meaningful error messages for debugging
- Log errors appropriately (currently using `print()`)

### Refactoring Guidelines

When refactoring:
1. **Read before writing** - Always use the Read tool before modifying files
2. **Small iterations** - Break large refactorings into smaller, testable chunks
3. **Preserve behavior** - Ensure tests pass after each refactoring step
4. **Update tests** - Adjust tests if refactoring changes test internals
5. **No scope creep** - Focus on the specific refactoring goal

Common refactoring patterns used in this project:
- Helper methods with closure parameters (e.g., `withClipboardRestore`)
- Strategy pattern for extensibility
- Method extraction for clarity
- Enum-based type switching

### Documentation

**Always keep documentation in sync** when making changes:

#### Files to Update
1. **README.md** - Main user-facing documentation
   - Update features, installation, usage instructions
   - Keep keyboard shortcuts current
   - Update requirements (macOS version, etc.)

2. **QUICKSTART.md** - Quick start guide
   - Sync keyboard shortcuts with README
   - Update any UI references (menu items, settings)

3. **.github/workflows/release.yml** - Release notes template
   - Update release notes in "Create GitHub Release" step
   - Keep keyboard shortcuts and features synchronized
   - Update installation instructions if changed

4. **CLAUDE.md** (this file) - Development guide
   - Document new patterns or best practices
   - Update file organization if structure changes
   - Add new troubleshooting tips as discovered

#### When to Update Documentation
- **New features**: Document in README, update QUICKSTART if user-facing
- **UI changes**: Update screenshots, menu descriptions, settings references
- **Keyboard shortcuts**: Update README, QUICKSTART, release.yml template
- **Breaking changes**: Document migration path in README and release notes
- **Security fixes**: Consider adding to CLAUDE.md security section
- **Build/deploy changes**: Update CI/CD and build instructions

### Git Workflow

#### Commits
- Write clear, descriptive commit messages
- Include `🤖 Generated with Claude Code` footer when applicable
- Follow format: `<type>: <description>` (e.g., `fix: JavaScript injection vulnerability`)

#### Branches
- Use feature branches for new work
- Keep branches focused on single features/fixes
- Name branches descriptively (e.g., `fix/security-js-injection`)

#### Pull Requests
- Include test results in PR description
- Document breaking changes clearly
- Link related issues
- **Update relevant documentation** before merging

### CI/CD Pipeline

**GitHub Actions** (`.github/workflows/release.yml`):
- Runs on push to `main` and on tags
- Executes full build and test suite
- Creates signed releases for tags
- Uploads artifacts for non-tag builds

**Build Requirements**:
- macOS 14.0+ deployment target
- Xcode with Swift 5.9+
- MathJax 3.2.2 (bundled via `setup-mathjax.sh`)

**Version Management**:
- Version auto-generated from `git describe --tags --dirty`
- Update via Git tags, not manual version files
- Format: `v0.0.5-5-g495b000` (semantic version + commits + hash)

### Dependencies

**External**:
- MathJax 3.2.2 (Apache 2.0) - bundled, not npm installed
- macOS frameworks: WebKit, PDFKit, Carbon (for hotkeys)

**Internal Architecture**:
- `MathRenderer`: WebKit-based LaTeX→SVG→PDF rendering
- `ClipboardManager`: Clipboard operations and content transformation
- `ShortcutManager`: Global keyboard shortcut registration

### File Organization

```
TeXClipper/
├── Services/          # Core business logic
│   ├── MathRenderer.swift
│   ├── ClipboardManager.swift
│   └── ShortcutManager.swift
├── TeXClipperApp.swift    # App entry point
├── ContentView.swift      # Settings UI
├── Resources/             # MathJax bundle
└── Assets.xcassets/

TeXClipperTests/       # Unit tests
```

### Common Issues & Solutions

**WebView JavaScript Errors**:
- "WKErrorDomain Code=5" is expected for async JS - documented in code
- Check MathJax bundle is present via `setup-mathjax.sh`

**Test Failures**:
- Ensure MathJax is downloaded before running tests
- WebView operations require main thread (`@MainActor`)
- Allow sufficient sleep time for clipboard operations (0.2-0.3s)

**Build Issues**:
- Run `xcodebuild clean` if build cache is stale
- Verify code signing settings for distribution builds
- Check entitlements file for sandboxing requirements

### Performance Considerations

- MathJax rendering: ~1-2ms per expression (cached)
- PDF generation: ~100-200ms (includes WebKit render)
- Clipboard operations: 200-300ms delays for system synchronization
- Keep rendering synchronous but use async/await for user-facing operations

## Quick Reference

```bash
# Run tests
xcodebuild test -scheme TeXClipper -destination 'platform=macOS'

# Clean build
xcodebuild clean
xcodebuild -scheme TeXClipper -configuration Release

# Download MathJax (required before first build)
./setup-mathjax.sh

# Create release
git tag v0.1.0
git push origin v0.1.0  # Triggers GitHub Actions release
```

## Resources

- [MathJax Documentation](https://docs.mathjax.org/)
- [Apple WebKit Documentation](https://developer.apple.com/documentation/webkit)
- [Swift Concurrency Guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
