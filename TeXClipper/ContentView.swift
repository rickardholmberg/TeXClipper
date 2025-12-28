import SwiftUI

struct ContentView: View {
    @State private var testLatex = "\\int_0^\\infty \\frac{1}{1+\\zeta}\\mathrm{d}\\zeta"
    @State private var renderResult = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            Text("TeXClipper Settings")
                .font(.title)
                .padding(.top)

            GroupBox(label: Text("Shortcuts")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Render LaTeX (display mode):")
                        Spacer()
                        Text("⌘⌥K")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }

                    HStack {
                        Text("Render LaTeX (inline mode):")
                        Spacer()
                        Text("⌘⌥I")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }

                    HStack {
                        Text("Revert to LaTeX:")
                        Spacer()
                        Text("⌘⌥⇧K")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .padding()
            }

            GroupBox(label: Text("Test Renderer")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter LaTeX:")
                    TextEditor(text: $testLatex)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 60)
                        .border(Color.gray.opacity(0.3))

                    Button(action: testRender) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 100)
                        } else {
                            Text("Test Render")
                                .frame(width: 100)
                        }
                    }
                    .disabled(isLoading)

                    if !renderResult.isEmpty {
                        Text("Result:")
                        TextEditor(text: .constant(renderResult))
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 100)
                            .border(Color.gray.opacity(0.3))
                    }
                }
                .padding()
            }

            Spacer()

            Text("The app runs in the menu bar. Use shortcuts to convert LaTeX selections.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom)
        }
        .padding()
        .frame(width: 500, height: 500)
    }

    private func testRender() {
        isLoading = true
        Task {
            do {
                let renderer = MathRenderer.shared
                let svg = try await renderer.renderToSVGDirect(latex: testLatex, displayMode: true)
                await MainActor.run {
                    renderResult = String(svg.prefix(500)) + (svg.count > 500 ? "..." : "")
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    renderResult = "Error: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
