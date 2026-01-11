#!/usr/bin/env python3
"""
Migrate image assets from a flat directory to an Xcode Asset Catalog (.xcassets).

This script converts PNG/JPG images into properly structured .imageset directories
with Contents.json manifests. It supports @2x and @3x scale variants when present.

Usage:
    python migrate_assets.py [source_dir] [dest_dir]

Environment variables:
    ASSET_SOURCE_DIR: Override source directory
    ASSET_DEST_DIR: Override destination directory
"""

import os
import json
import shutil
import sys
from pathlib import Path


def get_project_root() -> Path:
    """Get the project root directory (where this script lives)."""
    return Path(__file__).resolve().parent


def get_default_paths() -> tuple[Path, Path]:
    """Get default source and destination paths relative to project root."""
    root = get_project_root()
    source = root / "Sources" / "ClaudeUsagePro" / "Assets"
    dest = root / "Sources" / "ClaudeUsagePro" / "Assets.xcassets"
    return source, dest


def safe_rmtree(path: Path, expected_parent: Path) -> bool:
    """
    Safely remove a directory tree with validation.

    Args:
        path: The directory to remove
        expected_parent: The expected parent directory (safety check)

    Returns:
        True if removal succeeded or directory didn't exist, False on error
    """
    if not path.exists():
        return True

    # Safety checks
    path_str = str(path.resolve())

    # Never delete root or empty paths
    if not path_str or path_str in ("/", os.path.sep):
        print(f"ERROR: Refusing to delete root/empty path: {path}")
        return False

    # Ensure path is inside expected parent
    try:
        expected_str = str(expected_parent.resolve())
        if os.path.commonpath([expected_str, path_str]) != expected_str:
            print(f"ERROR: Path '{path}' is not inside expected parent '{expected_parent}'")
            return False
    except ValueError:
        print(f"ERROR: Path validation failed for '{path}'")
        return False

    # Perform removal
    try:
        shutil.rmtree(path)
        return True
    except OSError as e:
        print(f"ERROR: Failed to remove '{path}': {e}")
        return False


def create_imageset(
    source_dir: Path,
    dest_dir: Path,
    base_name: str,
    ext: str,
    scales: list[str]
) -> bool:
    """
    Create an imageset directory with Contents.json and copy image files.

    Args:
        source_dir: Source directory containing images
        dest_dir: Destination .xcassets directory
        base_name: Base name of the image (without extension or scale suffix)
        ext: File extension (e.g., ".png", ".jpg")
        scales: List of scales to check ("1x", "2x", "3x")

    Returns:
        True if successful, False on error
    """
    imageset_dir = dest_dir / f"{base_name}.imageset"

    try:
        os.makedirs(imageset_dir, exist_ok=True)
    except OSError as e:
        print(f"ERROR: Failed to create directory '{imageset_dir}': {e}")
        return False

    images_array = []

    for scale in scales:
        # Determine the filename for this scale
        if scale == "1x":
            variant_name = f"{base_name}{ext}"
        else:
            # @2x, @3x suffixes
            variant_name = f"{base_name}@{scale[0]}x{ext}"

        source_file = source_dir / variant_name

        image_entry = {
            "idiom": "universal",
            "scale": scale
        }

        if source_file.exists():
            try:
                shutil.copy2(source_file, imageset_dir / variant_name)
                image_entry["filename"] = variant_name
            except (OSError, IOError) as e:
                print(f"WARNING: Failed to copy '{source_file}': {e}")
                # Entry without filename indicates missing asset

        images_array.append(image_entry)

    # Write Contents.json
    contents = {
        "images": images_array,
        "info": {
            "author": "xcode",
            "version": 1
        }
    }

    try:
        contents_path = imageset_dir / "Contents.json"
        with open(contents_path, "w") as f:
            json.dump(contents, f, indent=2)
    except (OSError, IOError) as e:
        print(f"ERROR: Failed to write Contents.json for '{base_name}': {e}")
        return False

    return True


def migrate_assets(source_dir: Path, dest_dir: Path) -> bool:
    """
    Migrate all image assets from source to destination .xcassets catalog.

    Args:
        source_dir: Source directory containing flat image files
        dest_dir: Destination .xcassets directory

    Returns:
        True if all migrations succeeded, False if any failed
    """
    # Validate source directory
    if not source_dir.exists():
        print(f"ERROR: Source directory does not exist: {source_dir}")
        return False

    if not source_dir.is_dir():
        print(f"ERROR: Source path is not a directory: {source_dir}")
        return False

    # Safely remove existing destination
    expected_parent = get_project_root() / "Sources"
    if not safe_rmtree(dest_dir, expected_parent):
        return False

    # Create destination directory
    try:
        os.makedirs(dest_dir, exist_ok=True)
    except OSError as e:
        print(f"ERROR: Failed to create destination directory: {e}")
        return False

    # Create root Contents.json
    try:
        with open(dest_dir / "Contents.json", "w") as f:
            json.dump({
                "info": {
                    "author": "xcode",
                    "version": 1
                }
            }, f, indent=2)
    except (OSError, IOError) as e:
        print(f"ERROR: Failed to create root Contents.json: {e}")
        return False

    # Find all image files (excluding scale variants)
    image_extensions = {".png", ".jpg", ".jpeg"}
    scales = ["1x", "2x", "3x"]

    try:
        files = [f for f in os.listdir(source_dir)
                 if Path(f).suffix.lower() in image_extensions]
    except OSError as e:
        print(f"ERROR: Failed to list source directory: {e}")
        return False

    # Group files by base name (excluding @2x/@3x variants from primary list)
    base_names = set()
    for filename in files:
        path = Path(filename)
        stem = path.stem
        ext = path.suffix

        # Remove scale suffix if present (@2x, @3x)
        for scale_suffix in ["@2x", "@3x"]:
            if stem.endswith(scale_suffix):
                stem = stem[:-len(scale_suffix)]
                break

        base_names.add((stem, ext))

    # Process each unique image
    all_success = True
    for base_name, ext in sorted(base_names):
        success = create_imageset(source_dir, dest_dir, base_name, ext, scales)
        if not success:
            all_success = False
            print(f"WARNING: Failed to create imageset for '{base_name}{ext}'")

    return all_success


def main():
    """Main entry point."""
    # Get paths from arguments, environment, or defaults
    default_source, default_dest = get_default_paths()

    source_dir = Path(os.environ.get("ASSET_SOURCE_DIR", "")) or default_source
    dest_dir = Path(os.environ.get("ASSET_DEST_DIR", "")) or default_dest

    # Command line arguments override everything
    if len(sys.argv) >= 2:
        source_dir = Path(sys.argv[1])
    if len(sys.argv) >= 3:
        dest_dir = Path(sys.argv[2])

    print(f"Source: {source_dir}")
    print(f"Destination: {dest_dir}")

    success = migrate_assets(source_dir, dest_dir)

    if success:
        print("Migration complete")
        sys.exit(0)
    else:
        print("Migration completed with errors")
        sys.exit(1)


if __name__ == "__main__":
    main()
