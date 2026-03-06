#!/usr/bin/env python3
"""
Screenshot Comparison Script

This script can be used to programmatically compare screenshots against design mocks
using image similarity metrics. Useful for automated visual regression testing.

Requirements:
    pip install pillow numpy scikit-image

Usage:
    python compare_screenshots.py <reference_image> <test_image> [--threshold 0.95]
"""

import sys
import argparse
from pathlib import Path

try:
    from PIL import Image
    import numpy as np
    from skimage.metrics import structural_similarity as ssim
except ImportError:
    print("Error: Required packages not installed.")
    print("Please run: pip install pillow numpy scikit-image")
    sys.exit(1)


def load_and_resize(image_path, target_size=None):
    """Load image and optionally resize to match comparison target."""
    img = Image.open(image_path)

    if target_size and img.size != target_size:
        print(f"Resizing {image_path} from {img.size} to {target_size}")
        img = img.resize(target_size, Image.Resampling.LANCZOS)

    return img


def calculate_similarity(img1_path, img2_path):
    """Calculate structural similarity between two images."""
    # Load images
    img1 = load_and_resize(img1_path)
    img2 = load_and_resize(img2_path, target_size=img1.size)

    # Convert to grayscale for comparison
    img1_gray = img1.convert('L')
    img2_gray = img2.convert('L')

    # Convert to numpy arrays
    arr1 = np.array(img1_gray)
    arr2 = np.array(img2_gray)

    # Calculate SSIM
    similarity_score = ssim(arr1, arr2)

    return similarity_score


def highlight_differences(img1_path, img2_path, output_path):
    """Create an image highlighting differences between two screenshots."""
    img1 = load_and_resize(img1_path)
    img2 = load_and_resize(img2_path, target_size=img1.size)

    # Convert to RGB
    img1_rgb = img1.convert('RGB')
    img2_rgb = img2.convert('RGB')

    # Convert to numpy arrays
    arr1 = np.array(img1_rgb)
    arr2 = np.array(img2_rgb)

    # Calculate absolute difference
    diff = np.abs(arr1.astype(float) - arr2.astype(float))

    # Amplify differences for visibility
    diff_amplified = np.clip(diff * 3, 0, 255).astype(np.uint8)

    # Create output image
    diff_img = Image.fromarray(diff_amplified)
    diff_img.save(output_path)

    print(f"Difference map saved to: {output_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Compare two screenshots and calculate similarity"
    )
    parser.add_argument(
        "reference",
        type=Path,
        help="Path to reference/design mock image"
    )
    parser.add_argument(
        "test",
        type=Path,
        help="Path to test/implementation screenshot"
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.95,
        help="Similarity threshold (0-1, default: 0.95)"
    )
    parser.add_argument(
        "--diff-output",
        type=Path,
        help="Optional path to save difference map image"
    )

    args = parser.parse_args()

    # Validate inputs
    if not args.reference.exists():
        print(f"Error: Reference image not found: {args.reference}")
        sys.exit(1)

    if not args.test.exists():
        print(f"Error: Test image not found: {args.test}")
        sys.exit(1)

    # Calculate similarity
    print(f"Comparing images...")
    print(f"  Reference: {args.reference}")
    print(f"  Test: {args.test}")

    similarity = calculate_similarity(args.reference, args.test)

    print(f"\nSimilarity Score: {similarity:.4f}")
    print(f"Threshold: {args.threshold:.4f}")

    if similarity >= args.threshold:
        print("✓ PASS: Images are similar enough")
        exit_code = 0
    else:
        print("✗ FAIL: Images differ significantly")
        exit_code = 1

    # Generate difference map if requested
    if args.diff_output:
        highlight_differences(args.reference, args.test, args.diff_output)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
