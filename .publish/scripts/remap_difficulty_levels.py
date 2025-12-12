#!/usr/bin/env python3
"""
Remap difficulty levels based on duration and project complexity.

New difficulty levels:
- Beginner (100-level): < 45 minutes
- Intermediate (200-level): 45-120 minutes
- Advanced (300-level): 120-180 minutes
- Expert (400-level): > 180 minutes
"""
import json
from pathlib import Path


def remap_difficulty(project):
    """Remap difficulty based on duration."""
    duration = project.get('duration', 60)  # Default to 60 if no duration

    if duration < 45:
        return 'beginner'
    elif duration < 120:
        return 'intermediate'
    elif duration < 180:
        return 'advanced'
    else:
        return 'expert'


def main():
    projects_file = Path('.publish/data/projects.json')

    # Load projects
    with open(projects_file, 'r') as f:
        projects = json.load(f)

    print(f"📊 Original distribution:")
    from collections import Counter
    original = Counter(p.get('difficulty', 'unknown') for p in projects)
    for diff, count in sorted(original.items()):
        print(f"  {diff}: {count}")

    # Remap difficulty
    for project in projects:
        old_difficulty = project.get('difficulty', 'unknown')
        new_difficulty = remap_difficulty(project)
        project['difficulty'] = new_difficulty

    print(f"\n📊 New distribution:")
    new_dist = Counter(p.get('difficulty') for p in projects)
    for diff, count in sorted(new_dist.items()):
        print(f"  {diff}: {count}")

    # Save
    with open(projects_file, 'w') as f:
        json.dump(projects, f, indent=2)

    print(f"\n✅ Updated {len(projects)} projects")
    print(f"📁 Saved to {projects_file}")


if __name__ == '__main__':
    main()
