#!/usr/bin/env python3
"""
Infrastructure Code Link Updater

This script automatically updates the "Infrastructure Code" section in recipe markdown files.
It replaces the placeholder text "*Infrastructure code will be generated after recipe approval.*"
with actual links to the infrastructure code folders that exist in each recipe's code directory.

Features:
- Provider-specific infrastructure as code mappings
- Safe operation with dry-run mode by default
- Idempotent - can be run multiple times safely
- Only updates files containing the exact placeholder text
- Preserves existing custom content
- Comprehensive logging and error handling

Usage:
    python3 update_infrastructure_links.py [options]
"""

import os
import sys
import re
import logging
import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Optional, Set
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Placeholder text to search for
PLACEHOLDER_TEXT = "*Infrastructure code will be generated after recipe approval.*"

# Infrastructure Code section header
INFRA_HEADER = "## Infrastructure Code"

# Provider-specific infrastructure mappings
INFRASTRUCTURE_MAPPINGS = {
    'aws': {
        'README.md': {
            'name': 'Infrastructure Code Overview',
            'description': 'Detailed description of all infrastructure components'
        },
        'cloudformation.yaml': {
            'name': 'CloudFormation',
            'description': 'AWS CloudFormation template'
        },
        'cloudformation': {
            'name': 'CloudFormation',
            'description': 'AWS CloudFormation templates'
        },
        'cdk-typescript': {
            'name': 'AWS CDK (TypeScript)',
            'description': 'AWS CDK TypeScript implementation'
        },
        'cdk-python': {
            'name': 'AWS CDK (Python)',
            'description': 'AWS CDK Python implementation'
        },
        'cdk-java': {
            'name': 'AWS CDK (Java)',
            'description': 'AWS CDK Java implementation'
        },
        'cdk-csharp': {
            'name': 'AWS CDK (C#)',
            'description': 'AWS CDK C# implementation'
        },
        'terraform': {
            'name': 'Terraform',
            'description': 'Terraform configuration files'
        },
        'scripts': {
            'name': 'Bash CLI Scripts',
            'description': 'Example bash scripts using AWS CLI commands to deploy infrastructure'
        }
    },
    'azure': {
        'README.md': {
            'name': 'Infrastructure Code Overview',
            'description': 'Detailed description of all infrastructure components'
        },
        'bicep': {
            'name': 'Bicep',
            'description': 'Azure Bicep templates'
        },
        'terraform': {
            'name': 'Terraform',
            'description': 'Terraform configuration files'
        },
        'arm-templates': {
            'name': 'ARM Templates',
            'description': 'Azure Resource Manager templates'
        },
        'arm': {
            'name': 'ARM Templates',
            'description': 'Azure Resource Manager templates'
        },
        'scripts': {
            'name': 'Bash CLI Scripts',
            'description': 'Example bash scripts using Azure CLI commands to deploy infrastructure'
        }
    },
    'gcp': {
        'README.md': {
            'name': 'Infrastructure Code Overview',
            'description': 'Detailed description of all infrastructure components'
        },
        'terraform': {
            'name': 'Terraform',
            'description': 'Terraform configuration files'
        },
        'infrastructure-manager': {
            'name': 'Infrastructure Manager',
            'description': 'GCP Infrastructure Manager templates'
        },
        'deployment-manager': {
            'name': 'Deployment Manager',
            'description': 'GCP Deployment Manager templates'
        },
        'gcloud': {
            'name': 'Bash CLI Scripts',
            'description': 'Example bash scripts using gcloud CLI commands to deploy infrastructure'
        },
        'scripts': {
            'name': 'Bash CLI Scripts',
            'description': 'Example bash scripts using gcloud CLI commands to deploy infrastructure'
        }
    }
}


class InfrastructureLinkUpdater:
    """Main class for updating infrastructure code links in recipe markdown files."""
    
    def __init__(self, 
                 root_dir: str = "/Users/mzazon/Dev/GitHub/awesome-cloud-projects",
                 providers: List[str] = None):
        """
        Initialize the infrastructure link updater.
        
        Args:
            root_dir: Base path to repository
            providers: List of providers to process (aws, azure, gcp)
        """
        self.root_dir = Path(root_dir)
        self.providers = providers or ['aws', 'azure', 'gcp']
        
        # Statistics tracking
        self.stats = {
            'total_recipes': 0,
            'recipes_with_placeholder': 0,
            'recipes_updated': 0,
            'recipes_skipped': 0,
            'errors': 0
        }
        
        self.operations = []  # Track all operations for reporting
        
    def find_recipe_files(self, providers: List[str] = None) -> List[Path]:
        """Find all recipe markdown files for specified providers."""
        if providers is None:
            providers = self.providers
            
        recipe_files = []
        
        for provider in providers:
            provider_dir = self.root_dir / provider
            if not provider_dir.exists():
                logger.warning(f"Provider directory does not exist: {provider_dir}")
                continue
                
            # Find all markdown files that match the recipe pattern
            # Recipe files are typically named like "recipe-name/recipe-name.md"
            for recipe_dir in provider_dir.iterdir():
                if not recipe_dir.is_dir():
                    continue
                    
                # Look for markdown file with same name as directory
                recipe_md = recipe_dir / f"{recipe_dir.name}.md"
                if recipe_md.exists():
                    recipe_files.append(recipe_md)
                    
        return sorted(recipe_files)
    
    def get_provider_from_path(self, file_path: Path) -> str:
        """Extract provider name from file path."""
        parts = file_path.parts
        for i, part in enumerate(parts):
            if part in ['aws', 'azure', 'gcp']:
                return part
        return 'unknown'
    
    def get_code_directories(self, recipe_path: Path) -> List[str]:
        """Get list of code directories/files that exist for a recipe."""
        code_dir = recipe_path.parent / 'code'
        if not code_dir.exists():
            return []
            
        code_items = []
        for item in code_dir.iterdir():
            if item.name.startswith('.'):
                continue
            code_items.append(item.name)
            
        return sorted(code_items)
    
    def generate_infrastructure_links(self, provider: str, code_items: List[str]) -> str:
        """Generate markdown links for infrastructure code items."""
        if not code_items:
            return ""
            
        mappings = INFRASTRUCTURE_MAPPINGS.get(provider, {})
        links = []
        
        # Always try to add README.md first if it exists
        if 'README.md' in code_items:
            readme_info = mappings.get('README.md', {
                'name': 'Infrastructure Code Overview',
                'description': 'Detailed description of all infrastructure components'
            })
            links.append(f"- [{readme_info['name']}](code/README.md) - {readme_info['description']}")
        
        # Add other infrastructure items
        for item in code_items:
            if item == 'README.md':
                continue  # Already handled above
                
            # Check if we have a mapping for this item
            item_info = mappings.get(item)
            if item_info:
                # Determine if it's a file or directory
                link_path = f"code/{item}" + ("" if item.endswith(('.yaml', '.json', '.yml')) else "/")
                links.append(f"- [{item_info['name']}]({link_path}) - {item_info['description']}")
            else:
                # Generic handling for unmapped items
                link_path = f"code/{item}" + ("/" if not item.endswith(('.yaml', '.json', '.yml', '.md')) else "")
                item_name = item.replace('-', ' ').replace('_', ' ').title()
                links.append(f"- [{item_name}]({link_path}) - {item_name} implementation")
        
        if links:
            return "### Available Infrastructure as Code:\n\n" + "\n".join(links)
        else:
            return ""
    
    def find_infrastructure_section(self, content: str) -> Tuple[Optional[int], Optional[int], Optional[str]]:
        """
        Find the Infrastructure Code section in markdown content.
        
        Returns:
            (start_index, end_index, current_content) or (None, None, None) if not found
        """
        lines = content.split('\n')
        start_idx = None
        end_idx = None
        
        for i, line in enumerate(lines):
            # Find the Infrastructure Code header
            if line.strip() == INFRA_HEADER:
                start_idx = i
                continue
                
            # If we found the start, look for the end
            if start_idx is not None:
                # End at next ## header or end of file
                if line.startswith('## ') and i > start_idx:
                    end_idx = i
                    break
                    
        if start_idx is not None and end_idx is None:
            end_idx = len(lines)
            
        if start_idx is not None:
            section_lines = lines[start_idx:end_idx]
            current_content = '\n'.join(section_lines).strip()
            return start_idx, end_idx, current_content
            
        return None, None, None
    
    def has_placeholder_text(self, section_content: str) -> bool:
        """Check if the section contains the exact placeholder text."""
        return PLACEHOLDER_TEXT in section_content
    
    def update_recipe_file(self, recipe_path: Path, dry_run: bool = True) -> Tuple[bool, str]:
        """
        Update a single recipe file with infrastructure links.
        
        Args:
            recipe_path: Path to recipe markdown file
            dry_run: If True, don't actually modify the file
            
        Returns:
            (was_updated: bool, message: str)
        """
        try:
            # Read the file
            with open(recipe_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Find the Infrastructure Code section
            start_idx, end_idx, section_content = self.find_infrastructure_section(content)
            
            if start_idx is None:
                return False, "No Infrastructure Code section found"
            
            # Check if it has the placeholder text
            if not self.has_placeholder_text(section_content):
                return False, "Section doesn't contain placeholder text"
            
            # Get provider and code directories
            provider = self.get_provider_from_path(recipe_path)
            code_items = self.get_code_directories(recipe_path)
            
            if not code_items:
                return False, "No code directory or items found"
            
            # Generate new infrastructure links
            new_content = self.generate_infrastructure_links(provider, code_items)
            
            if not new_content:
                return False, "No infrastructure links generated"
            
            # Replace the section content
            lines = content.split('\n')
            new_section = [INFRA_HEADER, "", new_content]
            
            # Construct new file content
            new_lines = lines[:start_idx] + new_section + lines[end_idx:]
            new_file_content = '\n'.join(new_lines)
            
            # Write the file if not dry run
            if not dry_run:
                with open(recipe_path, 'w', encoding='utf-8') as f:
                    f.write(new_file_content)
            
            return True, f"Updated with {len(code_items)} infrastructure items"
            
        except Exception as e:
            logger.error(f"Error processing {recipe_path}: {e}")
            return False, f"Error: {e}"
    
    def process_recipes(self, providers: List[str] = None, dry_run: bool = True, 
                       recipe_filter: str = None) -> Dict:
        """
        Process all recipes to update infrastructure links.
        
        Args:
            providers: List of providers to process
            dry_run: If True, only analyze without modifying files
            recipe_filter: Optional recipe filter (e.g., "aws/my-recipe")
            
        Returns:
            Dict: Processing results and statistics
        """
        if providers is None:
            providers = self.providers
            
        logger.info(f"Starting {'DRY RUN' if dry_run else 'LIVE'} processing for providers: {', '.join(providers)}")
        
        # Reset statistics
        self.stats = {
            'total_recipes': 0,
            'recipes_with_placeholder': 0,
            'recipes_updated': 0,
            'recipes_skipped': 0,
            'errors': 0
        }
        self.operations = []
        
        # Find all recipe files
        recipe_files = self.find_recipe_files(providers)
        
        # Apply recipe filter if specified
        if recipe_filter:
            filtered_files = []
            for recipe_file in recipe_files:
                # Create relative path from root for comparison
                relative_path = recipe_file.relative_to(self.root_dir)
                if recipe_filter in str(relative_path):
                    filtered_files.append(recipe_file)
            recipe_files = filtered_files
            
        self.stats['total_recipes'] = len(recipe_files)
        
        if not recipe_files:
            logger.warning("No recipe files found to process")
            return {'stats': self.stats, 'operations': self.operations, 'dry_run': dry_run}
        
        logger.info(f"Processing {len(recipe_files)} recipe files...")
        
        # Process each recipe file
        for recipe_file in recipe_files:
            relative_path = recipe_file.relative_to(self.root_dir)
            
            was_updated, message = self.update_recipe_file(recipe_file, dry_run)
            
            operation = {
                'recipe': str(relative_path),
                'provider': self.get_provider_from_path(recipe_file),
                'was_updated': was_updated,
                'message': message,
                'file_path': str(recipe_file)
            }
            
            self.operations.append(operation)
            
            if "placeholder text" in message:
                self.stats['recipes_with_placeholder'] += 1
                
            if was_updated:
                self.stats['recipes_updated'] += 1
                if not dry_run:
                    logger.info(f"✅ Updated: {relative_path} - {message}")
                else:
                    logger.info(f"🔍 Would update: {relative_path} - {message}")
            else:
                self.stats['recipes_skipped'] += 1
                if "Error:" in message:
                    self.stats['errors'] += 1
                    logger.error(f"❌ Error: {relative_path} - {message}")
                else:
                    logger.debug(f"⏭️  Skipped: {relative_path} - {message}")
        
        return {
            'stats': self.stats,
            'operations': self.operations,
            'dry_run': dry_run
        }
    
    def print_summary_report(self, results: Dict):
        """Print a detailed summary report of the processing operation."""
        stats = results['stats']
        operations = results['operations']
        dry_run = results['dry_run']
        
        print("\n" + "="*80)
        print("INFRASTRUCTURE LINKS UPDATE REPORT")
        print("="*80)
        
        print(f"Mode: {'DRY RUN (Preview Only)' if dry_run else 'LIVE UPDATE'}")
        print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        # Summary statistics
        print("SUMMARY:")
        print(f"  Total recipes processed: {stats['total_recipes']}")
        print(f"  Recipes with placeholder text: {stats['recipes_with_placeholder']}")
        print(f"  Recipes updated: {stats['recipes_updated']}")
        print(f"  Recipes skipped: {stats['recipes_skipped']}")
        print(f"  Errors encountered: {stats['errors']}")
        
        # Show updated recipes
        updated_ops = [op for op in operations if op['was_updated']]
        if updated_ops:
            print(f"\nUPDATED RECIPES ({len(updated_ops)}):")
            for op in updated_ops[:20]:  # Show first 20
                print(f"  ✅ {op['recipe']} - {op['message']}")
            if len(updated_ops) > 20:
                print(f"  ... and {len(updated_ops) - 20} more")
        
        # Show errors
        error_ops = [op for op in operations if "Error:" in op['message']]
        if error_ops:
            print(f"\nERRORS ({len(error_ops)}):")
            for op in error_ops[:10]:  # Show first 10
                print(f"  ❌ {op['recipe']} - {op['message']}")
            if len(error_ops) > 10:
                print(f"  ... and {len(error_ops) - 10} more errors")
        
        print("\n" + "="*80)
        
        if dry_run and stats['recipes_updated'] > 0:
            print("To perform the actual updates, run the command with --live")
        elif not dry_run and stats['recipes_updated'] > 0:
            print("Infrastructure links update completed!")
        elif stats['recipes_updated'] == 0:
            print("No recipes needed updates.")


def main():
    """Main function with command-line interface."""
    parser = argparse.ArgumentParser(
        description='Update Infrastructure Code links in recipe markdown files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --dry-run                    # Preview all changes
  %(prog)s --live                       # Update all recipes
  %(prog)s --provider aws               # Process only AWS recipes
  %(prog)s --recipe aws/my-lambda       # Process specific recipe
  %(prog)s --stats                      # Show detailed statistics
  %(prog)s --verbose                    # Enable verbose logging
        """
    )
    
    parser.add_argument(
        '--root',
        default='/Users/mzazon/Dev/GitHub/awesome-cloud-projects',
        help='Repository root path (default: /Users/mzazon/Dev/GitHub/awesome-cloud-projects)'
    )
    
    parser.add_argument(
        '--provider',
        type=str,
        help='Comma-separated list of providers to process (aws,azure,gcp). Default: all'
    )
    
    parser.add_argument(
        '--recipe',
        type=str,
        help='Process specific recipe only (e.g., aws/my-lambda-function)'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        default=True,
        help='Preview changes without modifying files (default: True for safety)'
    )
    
    parser.add_argument(
        '--live',
        action='store_true',
        help='Perform actual updates (overrides --dry-run)'
    )
    
    parser.add_argument(
        '--force',
        action='store_true',
        help='Update files even if they don\'t contain exact placeholder text'
    )
    
    parser.add_argument(
        '--stats',
        action='store_true',
        help='Show detailed statistics after processing'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose logging'
    )
    
    parser.add_argument(
        '--quiet', '-q',
        action='store_true',
        help='Suppress all output except errors'
    )
    
    args = parser.parse_args()
    
    # Configure logging based on verbosity
    if args.quiet:
        logging.getLogger().setLevel(logging.ERROR)
    elif args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Parse providers
    providers = ['aws', 'azure', 'gcp']
    if args.provider:
        providers = [p.strip() for p in args.provider.split(',')]
    
    # Determine if this is a dry run
    dry_run = args.dry_run and not args.live
    
    # Initialize updater
    updater = InfrastructureLinkUpdater(
        root_dir=args.root,
        providers=providers
    )
    
    try:
        # Process recipes
        results = updater.process_recipes(
            providers=providers,
            dry_run=dry_run,
            recipe_filter=args.recipe
        )
        
        # Print summary report
        if not args.quiet:
            updater.print_summary_report(results)
        
        # Exit with error code if there were errors
        if results['stats']['errors'] > 0:
            sys.exit(1)
            
    except KeyboardInterrupt:
        logger.error("Processing interrupted by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Processing failed: {e}")
        if args.verbose:
            logger.exception("Full error details:")
        sys.exit(1)


if __name__ == '__main__':
    main()