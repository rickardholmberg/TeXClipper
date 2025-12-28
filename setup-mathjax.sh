#!/bin/bash

# Script to download and setup MathJax library files

set -e

MATHJAX_VERSION="3.2.2"
DOWNLOAD_URL="https://registry.npmjs.org/mathjax/-/mathjax-${MATHJAX_VERSION}.tgz"
TEMP_DIR=$(mktemp -d)
RESOURCES_DIR="TeXClipper/Resources"

echo "Downloading MathJax v${MATHJAX_VERSION}..."
curl -L -o "${TEMP_DIR}/mathjax.tgz" "${DOWNLOAD_URL}"

echo "Extracting..."
tar -xzf "${TEMP_DIR}/mathjax.tgz" -C "${TEMP_DIR}"

echo "Copying files to ${RESOURCES_DIR}..."
mkdir -p "${RESOURCES_DIR}"

# Copy the MathJax core files needed for SVG rendering
cp "${TEMP_DIR}/package/es5/tex-svg.js" "${RESOURCES_DIR}/mathjax-tex-svg.js"

echo "Cleaning up..."
rm -rf "${TEMP_DIR}"

echo "✓ MathJax setup complete!"
echo ""
echo "Files installed:"
echo "  - ${RESOURCES_DIR}/mathjax-tex-svg.js"
echo ""
echo "You can now build the project in Xcode."
