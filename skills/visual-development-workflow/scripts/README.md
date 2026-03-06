# Scripts

This folder contains helper scripts for visual development workflow.

## compare_screenshots.py

Python script for programmatic screenshot comparison using image similarity metrics.

**Purpose:** Automate visual regression testing by comparing screenshots against design mocks.

**Installation:**
```bash
pip install pillow numpy scikit-image
```

**Usage:**
```bash
# Basic comparison
python compare_screenshots.py design_mock.png current_screenshot.png

# With custom threshold
python compare_screenshots.py design_mock.png current_screenshot.png --threshold 0.90

# Generate difference map
python compare_screenshots.py design_mock.png current_screenshot.png --diff-output differences.png
```

**How it works:**
- Loads both images and resizes if needed to match dimensions
- Converts to grayscale for comparison
- Calculates Structural Similarity Index (SSIM)
- Returns similarity score between 0 (completely different) and 1 (identical)
- Optionally generates a difference map highlighting changes

**Interpreting Results:**
- Score ≥ 0.95: Very similar, likely acceptable
- Score 0.85-0.95: Similar but with noticeable differences
- Score < 0.85: Significant differences, review needed

**Integration with Skill:**
Claude can use this script during iteration to quantify visual similarity and track improvement over iterations.
