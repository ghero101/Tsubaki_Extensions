#!/bin/bash
# =============================================================================
# Tsubaki Extensions Build Script (Linux/macOS)
# =============================================================================
# This script:
#   1. Reads manifest.json from each extension to get version info
#   2. Updates index.json with current versions and download URLs
#   3. Creates versioned zip files (e.g., flamecomics-rhai_1-1-5.zip)
#   4. Creates _latest.zip copies for convenience
#   5. Organizes everything in dist/{extension-name}/ folders
# =============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory (works even if script is sourced)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$SCRIPT_DIR/sources"
DIST_DIR="$SCRIPT_DIR/dist"
INDEX_FILE="$SCRIPT_DIR/index.json"

# GitHub raw URL base for download URLs
GITHUB_RAW_BASE="https://raw.githubusercontent.com/ghero101/Tsubaki_Extensions/master"

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}                    Tsubaki Extensions Build Script                          ${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Check for required tools
check_requirements() {
    local missing=()

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v zip &> /dev/null; then
        missing+=("zip")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required tools: ${missing[*]}${NC}"
        echo "Please install them:"
        echo "  Ubuntu/Debian: sudo apt install ${missing[*]}"
        echo "  Arch Linux:    sudo pacman -S ${missing[*]}"
        echo "  macOS:         brew install ${missing[*]}"
        exit 1
    fi
}

# Read version from manifest.json
get_manifest_value() {
    local manifest_file="$1"
    local key="$2"
    jq -r ".$key // empty" "$manifest_file" 2>/dev/null
}

# Convert version to filename format (1.5.2 -> 1-5-2)
version_to_filename() {
    echo "$1" | tr '.' '-'
}

# Build a single extension
build_extension() {
    local ext_dir="$1"
    local ext_name=$(basename "$ext_dir")
    local manifest_file="$ext_dir/manifest.json"

    # Check if manifest exists
    if [ ! -f "$manifest_file" ]; then
        echo -e "${YELLOW}  Skipping $ext_name (no manifest.json)${NC}"
        return 0
    fi

    # Read manifest values
    local ext_id=$(get_manifest_value "$manifest_file" "id")
    local version=$(get_manifest_value "$manifest_file" "version")
    local name=$(get_manifest_value "$manifest_file" "name")

    if [ -z "$version" ]; then
        echo -e "${YELLOW}  Skipping $ext_name (no version in manifest)${NC}"
        return 0
    fi

    local version_filename=$(version_to_filename "$version")
    local ext_dist_dir="$DIST_DIR/$ext_name"
    local zip_filename="${ext_name}_${version_filename}.zip"
    local zip_path="$ext_dist_dir/$zip_filename"
    local latest_path="$ext_dist_dir/${ext_name}_latest.zip"

    echo -e "${GREEN}  Building: $name ($ext_name) v$version${NC}"

    # Create extension dist directory
    mkdir -p "$ext_dist_dir"

    # Check if this version already exists
    if [ -f "$zip_path" ]; then
        echo -e "${YELLOW}    Version $version already exists, rebuilding...${NC}"
    fi

    # Create the zip file
    # We need to include the folder structure in the zip
    (cd "$SOURCES_DIR" && zip -rq "$zip_path" "$ext_name")

    # Create/update latest.zip
    cp "$zip_path" "$latest_path"

    # Get file size
    local size=$(du -h "$zip_path" | cut -f1)
    echo -e "    Created: $zip_filename ($size)"

    # Return values for index update (stored in global array)
    BUILT_EXTENSIONS+=("$ext_id|$ext_name|$version|$zip_filename")
}

# Update index.json with all built extensions
update_index() {
    echo ""
    echo -e "${BLUE}Updating index.json...${NC}"

    if [ ! -f "$INDEX_FILE" ]; then
        echo -e "${RED}Error: index.json not found${NC}"
        return 1
    fi

    # Create a temporary file for the updated index
    local temp_index=$(mktemp)
    cp "$INDEX_FILE" "$temp_index"

    local updated_count=0
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    for ext_info in "${BUILT_EXTENSIONS[@]}"; do
        IFS='|' read -r ext_id ext_name version zip_filename <<< "$ext_info"

        local download_url="$GITHUB_RAW_BASE/dist/$ext_name/$zip_filename"
        local manifest_url="$GITHUB_RAW_BASE/sources/$ext_name/manifest.json"

        # Update the addon entry in index.json
        # This uses jq to find the addon by id and update its fields
        local updated=$(jq --arg id "$ext_id" \
                          --arg version "$version" \
                          --arg download_url "$download_url" \
                          --arg manifest_url "$manifest_url" \
                          --arg timestamp "$timestamp" '
            .addons = [.addons[] |
                if .id == $id then
                    .version = $version |
                    .latest_version = $version |
                    .download_url = $download_url |
                    .manifest_url = $manifest_url |
                    .versions[$version] = {
                        "download_url": $download_url,
                        "released_at": $timestamp,
                        "changelog": "Updated"
                    }
                else
                    .
                end
            ]
        ' "$temp_index")

        if [ $? -eq 0 ]; then
            echo "$updated" > "$temp_index"
            ((updated_count++))
        fi
    done

    # Update index version and timestamp
    local current_version=$(jq '.version // 0' "$temp_index")
    local new_version=$((current_version + 1))

    jq --arg timestamp "$timestamp" \
       --argjson version "$new_version" '
        .version = $version |
        .updated_at = $timestamp
    ' "$temp_index" > "$INDEX_FILE"

    rm "$temp_index"

    echo -e "${GREEN}  Updated $updated_count extensions in index.json (version $new_version)${NC}"
}

# Clean old zip files (keep only current version and latest)
clean_old_versions() {
    local ext_name="$1"
    local current_zip="$2"
    local ext_dist_dir="$DIST_DIR/$ext_name"

    # Find and remove old versioned zips (not latest, not current)
    find "$ext_dist_dir" -name "${ext_name}_*.zip" ! -name "$current_zip" ! -name "${ext_name}_latest.zip" -type f 2>/dev/null | while read old_zip; do
        echo -e "${YELLOW}    Removing old version: $(basename "$old_zip")${NC}"
        rm "$old_zip"
    done
}

# Main build process
main() {
    check_requirements

    echo -e "${BLUE}Sources directory: $SOURCES_DIR${NC}"
    echo -e "${BLUE}Dist directory: $DIST_DIR${NC}"
    echo ""

    # Create dist directory if it doesn't exist
    mkdir -p "$DIST_DIR"

    # Array to store built extension info
    declare -a BUILT_EXTENSIONS=()

    echo -e "${BLUE}Building extensions...${NC}"

    # Process each extension directory
    for ext_dir in "$SOURCES_DIR"/*/; do
        if [ -d "$ext_dir" ]; then
            build_extension "$ext_dir"
        fi
    done

    # Update index.json
    update_index

    echo ""
    echo -e "${BLUE}==============================================================================${NC}"
    echo -e "${GREEN}Build complete!${NC}"
    echo ""
    echo -e "Built ${#BUILT_EXTENSIONS[@]} extensions"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Review changes: git status"
    echo "  2. Commit: git add -A && git commit -m 'Update extensions'"
    echo "  3. Push: git push"
    echo -e "${BLUE}==============================================================================${NC}"
}

# Run with optional arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --clean        Clean dist directory before building"
        echo "  --single NAME  Build only a single extension"
        echo ""
        exit 0
        ;;
    --clean)
        echo -e "${YELLOW}Cleaning dist directory...${NC}"
        rm -rf "$DIST_DIR"/*
        shift
        main
        ;;
    --single)
        if [ -z "${2:-}" ]; then
            echo -e "${RED}Error: --single requires an extension name${NC}"
            exit 1
        fi
        check_requirements
        mkdir -p "$DIST_DIR"
        declare -a BUILT_EXTENSIONS=()
        if [ -d "$SOURCES_DIR/$2" ]; then
            build_extension "$SOURCES_DIR/$2"
            update_index
        else
            echo -e "${RED}Error: Extension '$2' not found${NC}"
            exit 1
        fi
        ;;
    *)
        main
        ;;
esac
