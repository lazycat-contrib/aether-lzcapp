#!/bin/bash

# Aether LazyCat App Publisher Automation Script
# Version: 1.0.0
# Author: Claude Code

# Color constants
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File paths
MANIFEST_FILE="lzc-manifest.yml"
BUILD_CONFIG="lzc-build.yml"
LPK_OUTPUT_DIR="./"

# Print helpers
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check required tools
check_tools() {
    if ! command -v lzc-cli &> /dev/null; then
        print_error "lzc-cli is not installed. Please install it first."
        exit 1
    fi
}

# Check required files
check_files() {
    if [[ ! -f "$MANIFEST_FILE" ]]; then
        print_error "$MANIFEST_FILE not found!"
        exit 1
    fi
    if [[ ! -f "$BUILD_CONFIG" ]]; then
        print_error "$BUILD_CONFIG not found!"
        exit 1
    fi
    if [[ ! -f "icon.png" ]]; then
        print_warning "icon.png not found. Building might fail if lzc-build.yml references it."
    fi
}

# Get app information from manifest
get_app_info() {
    APP_NAME=$(grep "^name:" "$MANIFEST_FILE" | awk '{print $2}')
    APP_VERSION=$(grep "^version:" "$MANIFEST_FILE" | awk '{print $2}')
    APP_PACKAGE=$(grep "^package:" "$MANIFEST_FILE" | awk '{print $2}')
}

# Build the LPK package
build_app() {
    print_info "Building Aether app v$APP_VERSION..."
    LPK_NAME="${APP_PACKAGE}-v${APP_VERSION}.lpk"

    if lzc-cli project build -o "$LPK_NAME"; then
        print_success "Build successful: $LPK_NAME"
        return 0
    else
        print_error "Build failed!"
        return 1
    fi
}

# Copy images to LazyCat Registry and update manifest
copy_images() {
    print_info "Scanning for images in $MANIFEST_FILE..."

    # Extract images that are not already from registry.lazycat.cloud
    # We look for commented lines as well to find the original image if available
    # But for automation, we focus on the active image: line

    # Find all 'image:' lines that don't start with registry.lazycat.cloud
    # We use a temp file to store images to copy
    images=$(grep "image:" "$MANIFEST_FILE" | grep -v "registry.lazycat.cloud" | awk '{print $2}')

    if [[ -z "$images" ]]; then
        print_success "All images are already using LazyCat registry."
        return 0
    fi

    echo -e "${YELLOW}Found following images to copy:${NC}"
    echo "$images"
    echo -e "${YELLOW}Confirm copy to LazyCat registry? (y/n)${NC}"
    read -r confirm
    if [[ "$confirm" != "y" ]]; then
        print_info "Image copy skipped."
        return 0
    fi

    # Check login status
    if ! lzc-cli appstore my-images &> /dev/null; then
        print_error "Not logged into LazyCat App Store. Please run 'lzc-cli appstore login' first."
        return 1
    fi

    for img in $images; do
        print_info "Copying image: $img ..."
        result=$(lzc-cli appstore copy-image "$img" 2>&1)

        if echo "$result" | grep -q "^uploaded:"; then
            new_img=$(echo "$result" | grep "^uploaded:" | awk '{print $2}')
            print_success "Image copied: $new_img"

            # Update manifest: comment out old image and add new one
            print_info "Updating $MANIFEST_FILE ..."
            # Use a more robust sed to replace exactly the image line
            # We escape the image names for sed
            escaped_old=$(echo "$img" | sed 's/[^^$*.[\]{}()\/+?|]/\\&/g')
            escaped_new=$(echo "$new_img" | sed 's/[^^$*.[\]{}()\/+?|]/\\&/g')

            # Comment out original and add new one
            sed -i "s|image: $img|# $img\n    image: $new_img|" "$MANIFEST_FILE"
        else
            print_error "Failed to copy image $img"
            echo "$result"
        fi
    done
}

# Publish to App Store
publish_app() {
    LPK_NAME="${APP_PACKAGE}-v${APP_VERSION}.lpk"
    if [[ ! -f "$LPK_NAME" ]]; then
        print_error "LPK file not found: $LPK_NAME. Build it first."
        return 1
    fi

    print_info "Publishing $LPK_NAME to LazyCat App Store..."
    if lzc-cli appstore publish "$LPK_NAME"; then
        print_success "Publish request submitted successfully!"
    else
        print_error "Publish failed!"
    fi
}

# Show menu
show_menu() {
    get_app_info
    echo -e "${BLUE}=======================================${NC}"
    echo -e "${GREEN}  Aether LazyCat App Publisher${NC}"
    echo -e "  App: $APP_NAME ($APP_PACKAGE)"
    echo -e "  Version: $APP_VERSION"
    echo -e "${BLUE}=======================================${NC}"
    echo -e "1. 📦 构建应用 (Build LPK)"
    echo -e "2. 🔧 镜像复制并更新 (Copy Images & Update Manifest)"
    echo -e "3. 📤 发布到应用商店 (Publish to App Store)"
    echo -e "4. 🚀 一键构建+发布 (Build & Publish)"
    echo -e "5. 📋 查看应用信息 (Show Info)"
    echo -e "6. ❌ 退出 (Exit)"
    echo -n "请选择 [1-6]: "
}

# Main loop
check_tools
check_files

while true; do
    show_menu
    read -r choice
    case $choice in
        1) build_app ;;
        2) copy_images ;;
        3) publish_app ;;
        4)
            copy_images && \
            build_app && \
            publish_app
            ;;
        5)
            echo -e "${YELLOW}Manifest Details:${NC}"
            grep -E "^(name|version|package|description|author):" "$MANIFEST_FILE"
            echo -e "${YELLOW}Current Images:${NC}"
            grep "image:" "$MANIFEST_FILE"
            ;;
        6) exit 0 ;;
        *) print_error "Invalid choice!" ;;
    esac
    echo ""
done
