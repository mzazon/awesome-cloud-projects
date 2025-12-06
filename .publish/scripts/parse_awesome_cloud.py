#!/usr/bin/env python3
"""
Awesome Cloud Projects - README Parser

This script is specifically designed for the mzazon/awesome-cloud-projects repository.
It parses the README.md file which uses this format:

Categories:
    ## 🖥️ Compute & Infrastructure (287 projects)

Project entries (one of these formats):
    - [Project Name](folder-link) - Services: Service1, Service2 • ⏱️ XX minutes
    - [Project Name](folder-link) - Services: Service1, Service2, Service3 • ⏱️ XX minutes

The projects link to folders within the repo:
    https://github.com/mzazon/awesome-cloud-projects/tree/main/aws/project-name

Usage:
    python parse_awesome_cloud.py README.md --output data/projects.json
    python parse_awesome_cloud.py README.md --repo-url https://github.com/mzazon/awesome-cloud-projects
"""

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse, urljoin


# Category emoji to readable name mapping
CATEGORY_EMOJI_MAP = {
    '🖥️': 'Compute & Infrastructure',
    '🗄️': 'Storage & Data Management',
    '🛢️': 'Databases & Analytics',
    '🌐': 'Networking & Content Delivery',
    '🔐': 'Security & Identity',
    '🤖': 'AI & Machine Learning',
    '🛠️': 'Application Development & Deployment',
    '📊': 'Monitoring & Management',
    '🔗': 'Integration & Messaging',
    '📱': 'IoT & Edge Computing',
    '🎬': 'Media & Content',
    '🏢': 'Specialized Solutions',
}


def slugify(text: str) -> str:
    """Convert text to a URL-friendly slug."""
    text = text.lower()
    text = re.sub(r'[^a-z0-9\s-]', '', text)
    text = re.sub(r'[\s_]+', '-', text)
    text = re.sub(r'-+', '-', text)
    return text.strip('-')


def detect_provider_from_path(url: str) -> str:
    """Detect cloud provider from the project folder path."""
    url_lower = url.lower()
    
    if '/aws/' in url_lower or url_lower.startswith('aws/'):
        return 'aws'
    elif '/azure/' in url_lower or url_lower.startswith('azure/'):
        return 'azure'
    elif '/gcp/' in url_lower or url_lower.startswith('gcp/'):
        return 'gcp'
    elif '/multi/' in url_lower or url_lower.startswith('multi/'):
        return 'multi'
    
    # Check by service names in URL
    aws_indicators = ['lambda', 'ec2', 's3', 'dynamodb', 'cloudformation', 'sagemaker', 'eks', 'ecs', 'cloudwatch', 'sns', 'sqs']
    azure_indicators = ['azure', 'cosmos', 'aks', 'blob', 'functions']
    gcp_indicators = ['cloud-run', 'bigquery', 'pubsub', 'gke', 'firestore', 'cloud-functions']
    
    for indicator in aws_indicators:
        if indicator in url_lower:
            return 'aws'
    for indicator in azure_indicators:
        if indicator in url_lower:
            return 'azure'
    for indicator in gcp_indicators:
        if indicator in url_lower:
            return 'gcp'
    
    return 'multi'


def detect_provider_from_services(services: list[str]) -> str:
    """Detect cloud provider from the list of services."""
    services_lower = ' '.join(services).lower()
    
    aws_services = ['lambda', 'ec2', 's3', 'dynamodb', 'cloudformation', 'sagemaker', 'eks', 'ecs', 
                    'cloudwatch', 'sns', 'sqs', 'api gateway', 'route 53', 'cloudfront', 'kinesis',
                    'redshift', 'rds', 'aurora', 'elasticache', 'step functions', 'eventbridge',
                    'iam', 'cognito', 'secrets manager', 'kms', 'waf', 'shield', 'guardduty',
                    'athena', 'glue', 'emr', 'quicksight', 'lex', 'polly', 'rekognition',
                    'comprehend', 'textract', 'transcribe', 'translate', 'personalize',
                    'app runner', 'fargate', 'batch', 'outposts', 'wavelength', 'local zones',
                    'elastic beanstalk', 'lightsail', 'amplify', 'appsync', 'device farm',
                    'codepipeline', 'codebuild', 'codecommit', 'codedeploy', 'codestar',
                    'x-ray', 'systems manager', 'config', 'cloudtrail', 'organizations',
                    'control tower', 'service catalog', 'trusted advisor', 'health dashboard',
                    'auto scaling', 'elastic load balancing', 'vpc', 'direct connect',
                    'transit gateway', 'privatelink', 'global accelerator', 'app mesh',
                    'cloud map', 'efs', 'fsx', 'storage gateway', 'backup', 'datasync',
                    'snowball', 'snowmobile', 'transfer family', 'documentdb', 'neptune',
                    'qldb', 'timestream', 'keyspaces', 'managed blockchain', 'ground station',
                    'robomaker', 'iot core', 'iot greengrass', 'iot analytics', 'freertos',
                    'elemental', 'ivs', 'nimble studio', 'chime', 'connect', 'pinpoint',
                    'ses', 'workspaces', 'appstream', 'worklink', 'workdocs', 'honeycode']
    
    azure_services = ['azure', 'cosmos db', 'aks', 'blob storage', 'azure functions', 
                      'app service', 'logic apps', 'event grid', 'service bus', 'event hubs',
                      'key vault', 'active directory', 'ad', 'entra', 'defender', 'sentinel',
                      'synapse', 'data factory', 'databricks', 'hdinsight', 'stream analytics',
                      'cognitive services', 'machine learning', 'bot service', 'form recognizer',
                      'computer vision', 'face api', 'speech services', 'translator',
                      'container instances', 'container apps', 'batch', 'virtual machines',
                      'vmss', 'devops', 'repos', 'pipelines', 'artifacts', 'boards',
                      'monitor', 'log analytics', 'application insights', 'network watcher',
                      'virtual network', 'vnet', 'expressroute', 'vpn gateway', 'load balancer',
                      'traffic manager', 'front door', 'cdn', 'private link', 'firewall',
                      'ddos protection', 'storage account', 'disk storage', 'files', 'archive',
                      'sql database', 'sql managed instance', 'postgresql', 'mysql', 'mariadb',
                      'redis cache', 'table storage', 'queue storage', 'purview', 'media services',
                      'iot hub', 'iot central', 'digital twins', 'sphere', 'rtos', 'time series',
                      'signalr', 'notification hubs', 'communication services', 'power bi',
                      'power apps', 'power automate', 'bicep', 'arm template', 'resource manager']
    
    gcp_services = ['cloud run', 'cloud functions', 'cloud storage', 'bigquery', 'pub/sub', 'pubsub',
                    'gke', 'kubernetes engine', 'firestore', 'firebase', 'datastore', 'bigtable',
                    'spanner', 'cloud sql', 'memorystore', 'dataflow', 'dataproc', 'composer',
                    'vertex ai', 'automl', 'vision ai', 'natural language', 'translation',
                    'speech-to-text', 'text-to-speech', 'dialogflow', 'recommendations ai',
                    'compute engine', 'app engine', 'anthos', 'cloud build', 'artifact registry',
                    'container registry', 'cloud deploy', 'cloud monitoring', 'cloud logging',
                    'cloud trace', 'cloud profiler', 'error reporting', 'debugger',
                    'vpc', 'cloud nat', 'cloud dns', 'cloud cdn', 'cloud armor', 'cloud load balancing',
                    'cloud interconnect', 'network connectivity', 'traffic director', 'service directory',
                    'secret manager', 'cloud kms', 'iam', 'identity platform', 'beyondcorp',
                    'security command center', 'chronicle', 'recaptcha', 'web security scanner',
                    'filestore', 'persistent disk', 'transfer service', 'storage transfer',
                    'looker', 'data catalog', 'dataplex', 'analytics hub', 'healthcare api',
                    'life sciences', 'genomics', 'apigee', 'api gateway', 'endpoints', 'service extensions',
                    'eventarc', 'workflows', 'cloud scheduler', 'cloud tasks', 'iot core',
                    'media cdn', 'transcoder api', 'live stream api', 'video intelligence']
    
    aws_count = sum(1 for svc in aws_services if svc in services_lower)
    azure_count = sum(1 for svc in azure_services if svc in services_lower)
    gcp_count = sum(1 for svc in gcp_services if svc in services_lower)
    
    # If multiple providers detected, it's multi-cloud
    providers_detected = sum(1 for c in [aws_count, azure_count, gcp_count] if c > 0)
    if providers_detected > 1:
        return 'multi'
    
    if aws_count > azure_count and aws_count > gcp_count:
        return 'aws'
    elif azure_count > aws_count and azure_count > gcp_count:
        return 'azure'
    elif gcp_count > aws_count and gcp_count > azure_count:
        return 'gcp'
    
    return 'multi'


def estimate_difficulty(duration_minutes: int, services_count: int) -> str:
    """Estimate difficulty based on duration and number of services."""
    if duration_minutes <= 30 and services_count <= 2:
        return 'beginner'
    elif duration_minutes <= 90 or services_count <= 4:
        return 'intermediate'
    else:
        return 'advanced'


def parse_duration(text: str) -> Optional[int]:
    """Extract duration in minutes from text like '⏱️ 180 minutes'."""
    match = re.search(r'⏱️?\s*(\d+)\s*min', text)
    if match:
        return int(match.group(1))
    return None


def parse_services(text: str) -> list[str]:
    """Extract services from text like 'Services: API Gateway, Lambda, CloudWatch'."""
    match = re.search(r'Services?:\s*([^•⏱️]+)', text, re.IGNORECASE)
    if match:
        services_str = match.group(1).strip()
        # Split by comma and clean up
        services = [s.strip() for s in services_str.split(',')]
        return [s for s in services if s]
    return []


def parse_project_entry(line: str, current_category: str, repo_base_url: str, seen_ids: set) -> Optional[dict]:
    """
    Parse a project entry line.
    
    Expected formats:
    - [Project Name](url) - Services: Service1, Service2 • ⏱️ XX minutes
    - [Project Name](url) - Services: Service1, Service2, Service3 • ⏱️ XX minutes
    """
    
    # Pattern to match: - **[Name](url)** or - [Name](url) - rest of description
    pattern = r'^\s*[-*]\s*\*?\*?\[([^\]]+)\]\(([^)]+)\)\*?\*?\s*[-–—]?\s*(.*)$'
    match = re.match(pattern, line)
    
    if not match:
        return None
    
    name = match.group(1).strip()
    url = match.group(2).strip()
    description_part = match.group(3).strip()

    # Skip if no URL or it's an external link we don't want
    if not url:
        return None

    # Skip navigation links and category headers (anchors starting with #)
    if url.startswith('#'):
        return None

    # Skip "Back to Top" and similar navigation items
    if 'back to top' in name.lower() or name.startswith('🔝') or name.startswith('⬆'):
        return None
    
    # Build full URL if it's a relative path
    if url.startswith('http'):
        full_url = url
    elif url.startswith('./') or url.startswith('../') or not url.startswith('/'):
        # Relative URL - convert to full GitHub URL
        # Remove leading ./ if present
        clean_url = url.lstrip('./')
        full_url = f"{repo_base_url}/tree/main/{clean_url}"
    else:
        full_url = f"{repo_base_url}{url}"
    
    # Parse services
    services = parse_services(description_part)
    
    # Parse duration
    duration = parse_duration(description_part)
    
    # Detect provider (first from URL path, then from services)
    provider = detect_provider_from_path(url)
    if provider == 'multi':
        provider = detect_provider_from_services(services)
    
    # Generate unique ID
    base_id = slugify(name)
    project_id = base_id
    counter = 1
    while project_id in seen_ids:
        project_id = f"{base_id}-{counter}"
        counter += 1
    seen_ids.add(project_id)
    
    # Create description
    if services:
        description = f"Services: {', '.join(services)}"
    else:
        # Use the raw description without the duration
        description = re.sub(r'\s*•?\s*⏱️\s*\d+\s*min\w*', '', description_part).strip()
        if not description:
            description = f"A {provider.upper()} cloud project"
    
    # Estimate difficulty
    difficulty = None
    if duration and services:
        difficulty = estimate_difficulty(duration, len(services))
    elif duration:
        if duration <= 30:
            difficulty = 'beginner'
        elif duration <= 90:
            difficulty = 'intermediate'
        else:
            difficulty = 'advanced'
    
    project = {
        'id': project_id,
        'name': name,
        'description': description,
        'url': full_url,
        'provider': provider,
        'category': current_category,
        'services': services,
    }
    
    if duration:
        project['duration'] = duration
    
    if difficulty:
        project['difficulty'] = difficulty
    
    return project


def parse_readme(content: str, repo_base_url: str) -> list[dict]:
    """Parse the awesome-cloud-projects README and extract all projects."""
    projects = []
    seen_ids = set()
    current_category = 'General'

    lines = content.split('\n')

    i = 0
    while i < len(lines):
        line = lines[i]

        # Check for category headers
        # Format: ## 🖥️ Compute & Infrastructure (287 projects)
        # or: ## Category Name
        header_match = re.match(r'^#{1,3}\s*(.+)$', line)
        if header_match:
            header_text = header_match.group(1).strip()

            # Try to extract category name, removing count like "(287 projects)"
            category_text = re.sub(r'\s*\(\d+\s*projects?\)\s*', '', header_text).strip()

            # Skip certain headers
            skip_headers = ['contents', 'table of contents', 'toc', 'contributing',
                           'license', 'about', 'introduction', 'getting started',
                           'note', 'tip', 'total projects', 'quick stats']
            if any(skip in category_text.lower() for skip in skip_headers):
                i += 1
                continue

            # Check if it starts with an emoji and extract readable name
            for emoji, readable_name in CATEGORY_EMOJI_MAP.items():
                if category_text.startswith(emoji):
                    current_category = readable_name
                    break
            else:
                # No emoji match, use the text as-is (cleaned)
                current_category = category_text

            i += 1
            continue

        # Try to parse as a project entry
        # If the next line starts with <br>, combine them
        combined_line = line
        if i + 1 < len(lines) and lines[i + 1].strip().startswith('<br>'):
            # Combine current line with next line, removing <br> and extracting the services
            next_line = lines[i + 1].strip()
            # Remove <br> and *italics* markers
            services_part = next_line.replace('<br>', '').replace('*', '').strip()
            # Append to combined line
            combined_line = f"{line} - {services_part}"
            i += 1  # Skip the next line since we processed it

        project = parse_project_entry(combined_line, current_category, repo_base_url, seen_ids)
        if project:
            projects.append(project)

        i += 1

    return projects


def main():
    parser = argparse.ArgumentParser(
        description='Parse awesome-cloud-projects README.md to JSON format'
    )
    parser.add_argument(
        'input',
        type=Path,
        help='Path to README.md file'
    )
    parser.add_argument(
        '--output', '-o',
        type=Path,
        default=Path('./data/projects.json'),
        help='Output JSON file path (default: ./data/projects.json)'
    )
    parser.add_argument(
        '--repo-url', '-r',
        type=str,
        default='https://github.com/mzazon/awesome-cloud-projects',
        help='Base URL of the GitHub repository'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Parse and validate without writing output'
    )
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed parsing information'
    )
    
    args = parser.parse_args()
    
    print("🚀 Awesome Cloud Projects Parser")
    print("=" * 50)
    
    # Read input file
    if not args.input.exists():
        print(f"❌ Error: File not found: {args.input}")
        sys.exit(1)
    
    print(f"📂 Reading: {args.input}")
    with open(args.input, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Parse content
    print(f"🔍 Parsing projects (repo: {args.repo_url})...")
    projects = parse_readme(content, args.repo_url.rstrip('/'))
    
    if not projects:
        print("⚠️  Warning: No projects found!")
        print("   Make sure your README uses the expected format:")
        print("   - [Project Name](folder-path) - Services: X, Y • ⏱️ XX minutes")
        sys.exit(1)
    
    # Show statistics
    print(f"\n✅ Found {len(projects)} projects")
    
    # Provider breakdown
    providers = {}
    for p in projects:
        prov = p.get('provider', 'unknown')
        providers[prov] = providers.get(prov, 0) + 1
    
    print(f"\n☁️  Providers:")
    for prov, count in sorted(providers.items()):
        print(f"   {prov.upper()}: {count}")
    
    # Category breakdown
    categories = {}
    for p in projects:
        cat = p.get('category', 'Unknown')
        categories[cat] = categories.get(cat, 0) + 1
    
    print(f"\n📁 Categories ({len(categories)}):")
    for cat, count in sorted(categories.items(), key=lambda x: -x[1]):
        print(f"   {cat}: {count}")
    
    # Difficulty breakdown
    difficulties = {}
    for p in projects:
        diff = p.get('difficulty', 'unspecified')
        difficulties[diff] = difficulties.get(diff, 0) + 1
    
    print(f"\n📊 Difficulty levels:")
    for diff, count in sorted(difficulties.items()):
        print(f"   {diff}: {count}")
    
    # Duration stats
    durations = [p['duration'] for p in projects if 'duration' in p]
    if durations:
        print(f"\n⏱️  Duration stats:")
        print(f"   Min: {min(durations)} minutes")
        print(f"   Max: {max(durations)} minutes")
        print(f"   Avg: {sum(durations) // len(durations)} minutes")
    
    if args.verbose:
        print(f"\n📋 Sample projects:")
        for p in projects[:5]:
            services_str = ', '.join(p.get('services', [])[:3])
            if len(p.get('services', [])) > 3:
                services_str += '...'
            print(f"   - {p['name']}")
            print(f"     Provider: {p['provider']}, Category: {p['category']}")
            print(f"     Services: {services_str}")
            print(f"     URL: {p['url']}")
            print()
    
    if args.dry_run:
        print("\n🔍 Dry run complete - no files written")
        return
    
    # Write output
    args.output.parent.mkdir(parents=True, exist_ok=True)
    
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(projects, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Saved to: {args.output}")
    print("\nNext steps:")
    print("   1. Review the generated JSON")
    print("   2. Optionally create learning-paths.json")
    print("   3. Run: python scripts/build.py")


if __name__ == '__main__':
    main()
