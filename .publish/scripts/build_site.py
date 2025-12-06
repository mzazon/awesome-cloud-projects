#!/usr/bin/env python3
"""
Cloud Projects Index - Static Site Generator

This script generates a static HTML site from project and learning path data.
It reads JSON data files and injects them into an HTML template.

Usage:
    python build_site.py [--output OUTPUT_DIR] [--data DATA_DIR]

Example:
    python build_site.py --output .publish/docs --data .publish/data
"""

import argparse
import json
import re
import sys
from pathlib import Path
from datetime import datetime


def load_json_file(filepath: Path) -> dict | list:
    """Load and parse a JSON file."""
    if not filepath.exists():
        print(f"Warning: {filepath} not found, using empty data")
        return [] if 'projects' in filepath.name or 'paths' in filepath.name else {}

    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error parsing {filepath}: {e}")
        sys.exit(1)


def validate_project(project: dict, index: int) -> list[str]:
    """Validate a project entry and return list of errors."""
    errors = []
    required_fields = ['id', 'name', 'description', 'url', 'provider', 'category']

    for field in required_fields:
        if field not in project:
            errors.append(f"Project {index}: missing required field '{field}'")

    if 'provider' in project:
        valid_providers = ['aws', 'azure', 'gcp', 'multi']
        if project['provider'] not in valid_providers:
            errors.append(f"Project {index}: invalid provider '{project['provider']}' (must be one of {valid_providers})")

    if 'difficulty' in project:
        valid_difficulties = ['beginner', 'intermediate', 'advanced']
        if project['difficulty'] not in valid_difficulties:
            errors.append(f"Project {index}: invalid difficulty '{project['difficulty']}' (must be one of {valid_difficulties})")

    return errors


def validate_learning_path(path: dict, index: int, project_ids: set) -> list[str]:
    """Validate a learning path entry and return list of errors."""
    errors = []
    required_fields = ['id', 'name', 'projectIds']

    for field in required_fields:
        if field not in path:
            errors.append(f"Learning path {index}: missing required field '{field}'")

    if 'projectIds' in path:
        for pid in path['projectIds']:
            if pid not in project_ids:
                errors.append(f"Learning path {index}: references unknown project '{pid}'")

    return errors


def build_site(data_dir: Path, output_dir: Path, template_path: Path):
    """Build the static site from data files."""

    print(f"📂 Loading data from {data_dir}")

    # Load project data
    projects_file = data_dir / 'projects.json'
    projects = load_json_file(projects_file)

    # Load learning paths
    paths_file = data_dir / 'learning-paths.json'
    learning_paths = load_json_file(paths_file)

    # Validate data
    print("🔍 Validating data...")
    all_errors = []

    project_ids = set()
    for i, project in enumerate(projects):
        errors = validate_project(project, i)
        all_errors.extend(errors)
        if 'id' in project:
            project_ids.add(project['id'])

    for i, path in enumerate(learning_paths):
        errors = validate_learning_path(path, i, project_ids)
        all_errors.extend(errors)

    if all_errors:
        print("\n❌ Validation errors found:")
        for error in all_errors:
            print(f"   - {error}")
        sys.exit(1)

    print(f"   ✓ {len(projects)} projects validated")
    print(f"   ✓ {len(learning_paths)} learning paths validated")

    # Load template
    print(f"📄 Loading template from {template_path}")
    if not template_path.exists():
        print(f"Error: Template file not found: {template_path}")
        sys.exit(1)

    with open(template_path, 'r', encoding='utf-8') as f:
        template = f.read()

    # Inject data into template
    print("🔧 Building site...")

    # Convert to JSON strings
    projects_json = json.dumps(projects, separators=(',', ':'))
    paths_json = json.dumps(learning_paths, separators=(',', ':'))

    # Replace placeholders
    html = template.replace('{{PROJECTS_DATA}}', projects_json)
    html = template.replace('{{PROJECTS_DATA}}', projects_json)
    html = html.replace('{{LEARNING_PATHS}}', paths_json)

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Write output file
    output_file = output_dir / 'index.html'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(html)

    print(f"✅ Site built successfully!")
    print(f"   📁 Output: {output_file}")
    print(f"   📊 {len(projects)} projects")
    print(f"   🎯 {len(learning_paths)} learning paths")

    # Generate stats
    provider_counts = {}
    category_counts = {}
    difficulty_counts = {}

    for project in projects:
        provider = project.get('provider', 'unknown')
        provider_counts[provider] = provider_counts.get(provider, 0) + 1

        category = project.get('category', 'uncategorized')
        category_counts[category] = category_counts.get(category, 0) + 1

        difficulty = project.get('difficulty', 'unspecified')
        difficulty_counts[difficulty] = difficulty_counts.get(difficulty, 0) + 1

    print("\n📈 Statistics:")
    print("   Providers:")
    for provider, count in sorted(provider_counts.items()):
        print(f"      {provider.upper()}: {count}")
    print(f"   Categories: {len(category_counts)}")
    print(f"   Difficulty levels: {len([d for d in difficulty_counts if d != 'unspecified'])}")


def main():
    parser = argparse.ArgumentParser(
        description='Build the Cloud Projects Index static site'
    )
    parser.add_argument(
        '--output', '-o',
        type=Path,
        default=Path('.publish/docs'),
        help='Output directory for the built site (default: .publish/docs)'
    )
    parser.add_argument(
        '--data', '-d',
        type=Path,
        default=Path('.publish/data'),
        help='Directory containing data files (default: .publish/data)'
    )
    parser.add_argument(
        '--template', '-t',
        type=Path,
        default=Path('.publish/templates/site/index.html'),
        help='Path to HTML template (default: .publish/templates/site/index.html)'
    )

    args = parser.parse_args()

    print("🚀 Cloud Projects Index Builder")
    print("=" * 40)

    build_site(args.data, args.output, args.template)


if __name__ == '__main__':
    main()
