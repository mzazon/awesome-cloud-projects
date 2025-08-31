#!/usr/bin/env python3
"""
Recipe Synchronization Script

This script synchronizes recipes from a source repository to the destination repository.
It performs one-way sync from the recipes repository to awesome-cloud-projects repository.

Source: /Users/mzazon/Dev/GitHub/recipes/{aws,azure,gcp}/
Destination: /Users/mzazon/Dev/GitHub/awesome-cloud-projects/{aws,azure,gcp}/

Features:
- One-way synchronization with timestamp comparison
- Dry-run mode for safe previewing
- Selective provider syncing
- Detailed logging and progress reporting
- Backup creation before overwriting
- Statistics and summary reporting

Usage:
    python3 sync_recipes.py [options]
"""

import os
import sys
import shutil
import logging
import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Set, Optional
from datetime import datetime
import hashlib

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)


class RecipeSync:
    """Main class for synchronizing recipes between repositories."""
    
    def __init__(self, 
                 source_base: str = "/Users/mzazon/Dev/GitHub/recipes",
                 dest_base: str = "/Users/mzazon/Dev/GitHub/awesome-cloud-projects",
                 providers: List[str] = None):
        """
        Initialize the recipe synchronizer.
        
        Args:
            source_base: Base path to source repository
            dest_base: Base path to destination repository  
            providers: List of providers to sync (aws, azure, gcp)
        """
        self.source_base = Path(source_base)
        self.dest_base = Path(dest_base)
        self.providers = providers or ['aws', 'azure', 'gcp']
        
        # Statistics tracking
        self.stats = {
            'new_recipes': 0,
            'updated_recipes': 0,
            'skipped_recipes': 0,
            'errors': 0,
            'total_size': 0
        }
        
        self.operations = []  # Track all operations for reporting
        
    def validate_paths(self) -> bool:
        """Validate that source and destination paths exist."""
        if not self.source_base.exists():
            logger.error(f"Source base directory does not exist: {self.source_base}")
            return False
            
        if not self.dest_base.exists():
            logger.error(f"Destination base directory does not exist: {self.dest_base}")
            return False
            
        for provider in self.providers:
            source_dir = self.source_base / provider
            dest_dir = self.dest_base / provider
            
            if not source_dir.exists():
                logger.warning(f"Source {provider} directory does not exist: {source_dir}")
                continue
                
            if not dest_dir.exists():
                logger.info(f"Creating destination {provider} directory: {dest_dir}")
                dest_dir.mkdir(parents=True, exist_ok=True)
                
        return True
    
    def get_recipe_folders(self, provider: str) -> Set[str]:
        """Get all recipe folder names for a provider."""
        source_dir = self.source_base / provider
        if not source_dir.exists():
            return set()
            
        folders = set()
        for item in source_dir.iterdir():
            if item.is_dir() and not item.name.startswith('.'):
                folders.add(item.name)
        return folders
    
    def get_folder_info(self, folder_path: Path) -> Dict:
        """Get information about a folder (size, modification time, etc.)."""
        if not folder_path.exists():
            return {'exists': False}
            
        info = {'exists': True}
        
        # Get modification time (latest file in the folder)
        latest_mtime = 0
        total_size = 0
        file_count = 0
        
        try:
            for root, dirs, files in os.walk(folder_path):
                for file in files:
                    file_path = Path(root) / file
                    try:
                        stat = file_path.stat()
                        latest_mtime = max(latest_mtime, stat.st_mtime)
                        total_size += stat.st_size
                        file_count += 1
                    except (OSError, IOError):
                        continue
                        
            info.update({
                'mtime': latest_mtime,
                'size': total_size,
                'file_count': file_count,
                'mtime_str': datetime.fromtimestamp(latest_mtime).strftime('%Y-%m-%d %H:%M:%S') if latest_mtime > 0 else 'unknown'
            })
            
        except (OSError, IOError) as e:
            logger.warning(f"Error accessing folder {folder_path}: {e}")
            info.update({'mtime': 0, 'size': 0, 'file_count': 0, 'mtime_str': 'error'})
            
        return info
    
    def should_sync_folder(self, source_info: Dict, dest_info: Dict, force: bool = False) -> Tuple[bool, str]:
        """
        Determine if a folder should be synced.
        
        Returns:
            (should_sync: bool, reason: str)
        """
        if not source_info['exists']:
            return False, "source does not exist"
            
        if not dest_info['exists']:
            return True, "new recipe"
            
        if force:
            return True, "forced update"
            
        # Compare modification times
        source_mtime = source_info.get('mtime', 0)
        dest_mtime = dest_info.get('mtime', 0)
        
        if source_mtime > dest_mtime:
            time_diff = source_mtime - dest_mtime
            if time_diff > 1:  # More than 1 second difference to account for filesystem precision
                return True, f"source is newer (source: {source_info['mtime_str']}, dest: {dest_info['mtime_str']})"
                
        return False, f"destination is up to date (source: {source_info['mtime_str']}, dest: {dest_info['mtime_str']})"
    
    def copy_folder(self, source_path: Path, dest_path: Path, backup: bool = False) -> bool:
        """
        Copy a folder from source to destination.
        
        Args:
            source_path: Source folder path
            dest_path: Destination folder path
            backup: Whether to create backup before overwriting
            
        Returns:
            bool: Success status
        """
        try:
            # Create backup if requested and destination exists
            if backup and dest_path.exists():
                backup_path = dest_path.parent / f"{dest_path.name}.backup.{int(datetime.now().timestamp())}"
                logger.info(f"Creating backup: {backup_path}")
                shutil.copytree(dest_path, backup_path)
            
            # Remove destination if it exists
            if dest_path.exists():
                shutil.rmtree(dest_path)
                
            # Copy source to destination
            shutil.copytree(source_path, dest_path)
            logger.debug(f"Successfully copied {source_path} -> {dest_path}")
            return True
            
        except Exception as e:
            logger.error(f"Error copying {source_path} -> {dest_path}: {e}")
            return False
    
    def analyze_sync(self, providers: List[str] = None) -> Dict:
        """Analyze what would be synced without performing actual sync."""
        if providers is None:
            providers = self.providers
            
        analysis = {
            'new_recipes': [],
            'updated_recipes': [],
            'up_to_date_recipes': [],
            'errors': [],
            'total_folders': 0,
            'total_size_to_copy': 0
        }
        
        for provider in providers:
            logger.info(f"Analyzing {provider} recipes...")
            
            source_dir = self.source_base / provider
            dest_dir = self.dest_base / provider
            
            if not source_dir.exists():
                logger.warning(f"Skipping {provider} - source directory does not exist")
                continue
                
            recipe_folders = self.get_recipe_folders(provider)
            analysis['total_folders'] += len(recipe_folders)
            
            for folder_name in sorted(recipe_folders):
                source_folder = source_dir / folder_name
                dest_folder = dest_dir / folder_name
                
                source_info = self.get_folder_info(source_folder)
                dest_info = self.get_folder_info(dest_folder)
                
                should_sync, reason = self.should_sync_folder(source_info, dest_info)
                
                folder_info = {
                    'provider': provider,
                    'name': folder_name,
                    'source_path': str(source_folder),
                    'dest_path': str(dest_folder),
                    'reason': reason,
                    'size': source_info.get('size', 0),
                    'file_count': source_info.get('file_count', 0),
                    'source_mtime': source_info.get('mtime_str', 'unknown'),
                    'dest_mtime': dest_info.get('mtime_str', 'unknown') if dest_info['exists'] else 'not exists'
                }
                
                if should_sync:
                    if not dest_info['exists']:
                        analysis['new_recipes'].append(folder_info)
                    else:
                        analysis['updated_recipes'].append(folder_info)
                    analysis['total_size_to_copy'] += source_info.get('size', 0)
                else:
                    analysis['up_to_date_recipes'].append(folder_info)
        
        return analysis
    
    def sync_recipes(self, providers: List[str] = None, dry_run: bool = True, 
                    force: bool = False, backup: bool = False, 
                    exclude_patterns: List[str] = None) -> Dict:
        """
        Perform the actual synchronization.
        
        Args:
            providers: List of providers to sync
            dry_run: If True, only analyze without copying
            force: Force overwrite without timestamp check
            backup: Create backups before overwriting
            exclude_patterns: Patterns to exclude (not implemented yet)
            
        Returns:
            Dict: Sync results and statistics
        """
        if providers is None:
            providers = self.providers
            
        logger.info(f"Starting {'DRY RUN' if dry_run else 'LIVE'} sync for providers: {', '.join(providers)}")
        
        # Reset statistics
        self.stats = {
            'new_recipes': 0,
            'updated_recipes': 0,
            'skipped_recipes': 0,
            'errors': 0,
            'total_size': 0
        }
        self.operations = []
        
        # First analyze what needs to be synced
        analysis = self.analyze_sync(providers)
        
        if dry_run:
            logger.info("DRY RUN - No files will be copied")
            return {
                'analysis': analysis,
                'operations': [],
                'stats': self.stats,
                'dry_run': True
            }
        
        # Perform actual sync
        logger.info("Performing live sync...")
        
        # Process new recipes
        for recipe in analysis['new_recipes']:
            source_path = Path(recipe['source_path'])
            dest_path = Path(recipe['dest_path'])
            
            logger.info(f"Copying new recipe: {recipe['provider']}/{recipe['name']}")
            
            if self.copy_folder(source_path, dest_path, backup):
                self.stats['new_recipes'] += 1
                self.stats['total_size'] += recipe['size']
                self.operations.append({
                    'type': 'new',
                    'recipe': recipe,
                    'status': 'success'
                })
            else:
                self.stats['errors'] += 1
                self.operations.append({
                    'type': 'new',
                    'recipe': recipe,
                    'status': 'error'
                })
        
        # Process updated recipes
        for recipe in analysis['updated_recipes']:
            source_path = Path(recipe['source_path'])
            dest_path = Path(recipe['dest_path'])
            
            logger.info(f"Updating recipe: {recipe['provider']}/{recipe['name']} ({recipe['reason']})")
            
            if self.copy_folder(source_path, dest_path, backup):
                self.stats['updated_recipes'] += 1
                self.stats['total_size'] += recipe['size']
                self.operations.append({
                    'type': 'update',
                    'recipe': recipe,
                    'status': 'success'
                })
            else:
                self.stats['errors'] += 1
                self.operations.append({
                    'type': 'update',
                    'recipe': recipe,
                    'status': 'error'
                })
        
        # Count skipped recipes
        self.stats['skipped_recipes'] = len(analysis['up_to_date_recipes'])
        
        return {
            'analysis': analysis,
            'operations': self.operations,
            'stats': self.stats,
            'dry_run': False
        }
    
    def print_summary_report(self, results: Dict):
        """Print a detailed summary report of the sync operation."""
        analysis = results['analysis']
        stats = results['stats']
        dry_run = results['dry_run']
        
        print("\n" + "="*80)
        print("RECIPE SYNCHRONIZATION REPORT")
        print("="*80)
        
        print(f"Mode: {'DRY RUN (Preview Only)' if dry_run else 'LIVE SYNC'}")
        print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        # Summary statistics
        new_count = len(analysis['new_recipes'])
        update_count = len(analysis['updated_recipes'])
        skip_count = len(analysis['up_to_date_recipes'])
        total_folders = analysis['total_folders']
        
        print("SUMMARY:")
        print(f"  Total recipes analyzed: {total_folders}")
        print(f"  New recipes: {new_count}")
        print(f"  Updated recipes: {update_count}")
        print(f"  Up-to-date recipes: {skip_count}")
        print(f"  Total size to copy: {self._format_bytes(analysis['total_size_to_copy'])}")
        
        if not dry_run:
            print(f"  Actual copies performed: {stats['new_recipes'] + stats['updated_recipes']}")
            print(f"  Errors encountered: {stats['errors']}")
            print(f"  Total size copied: {self._format_bytes(stats['total_size'])}")
        
        # Detail sections
        if new_count > 0:
            print(f"\nNEW RECIPES ({new_count}):")
            for recipe in analysis['new_recipes'][:10]:  # Show first 10
                print(f"  📁 {recipe['provider']}/{recipe['name']} "
                      f"({self._format_bytes(recipe['size'])}, {recipe['file_count']} files)")
            if new_count > 10:
                print(f"  ... and {new_count - 10} more")
        
        if update_count > 0:
            print(f"\nUPDATED RECIPES ({update_count}):")
            for recipe in analysis['updated_recipes'][:10]:  # Show first 10
                print(f"  🔄 {recipe['provider']}/{recipe['name']} "
                      f"({self._format_bytes(recipe['size'])}) - {recipe['reason']}")
            if update_count > 10:
                print(f"  ... and {update_count - 10} more")
        
        if not dry_run and stats['errors'] > 0:
            print(f"\nERRORS ({stats['errors']}):")
            error_ops = [op for op in results['operations'] if op['status'] == 'error']
            for op in error_ops[:5]:  # Show first 5 errors
                recipe = op['recipe']
                print(f"  ❌ {recipe['provider']}/{recipe['name']}")
            if len(error_ops) > 5:
                print(f"  ... and {len(error_ops) - 5} more errors")
        
        print("\n" + "="*80)
        
        if dry_run and (new_count > 0 or update_count > 0):
            print("To perform the actual sync, run the command without --dry-run")
        elif not dry_run:
            print("Sync completed!")
    
    def _format_bytes(self, bytes_count: int) -> str:
        """Format bytes into human readable format."""
        for unit in ['B', 'KB', 'MB', 'GB']:
            if bytes_count < 1024.0:
                return f"{bytes_count:.1f} {unit}"
            bytes_count /= 1024.0
        return f"{bytes_count:.1f} TB"


def main():
    """Main function with command-line interface."""
    parser = argparse.ArgumentParser(
        description='Synchronize recipes from source to destination repository',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --dry-run                    # Preview what would be synced
  %(prog)s                             # Perform actual sync
  %(prog)s --provider aws              # Sync only AWS recipes
  %(prog)s --provider aws,azure        # Sync AWS and Azure recipes
  %(prog)s --backup                    # Create backups before overwriting
  %(prog)s --stats-only                # Show statistics without syncing
  %(prog)s --verbose                   # Enable verbose logging
  %(prog)s --force                     # Force overwrite regardless of timestamps
        """
    )
    
    parser.add_argument(
        '--source',
        default='/Users/mzazon/Dev/GitHub/recipes',
        help='Source repository base path (default: /Users/mzazon/Dev/GitHub/recipes)'
    )
    
    parser.add_argument(
        '--dest', 
        default='/Users/mzazon/Dev/GitHub/awesome-cloud-projects',
        help='Destination repository base path (default: /Users/mzazon/Dev/GitHub/awesome-cloud-projects)'
    )
    
    parser.add_argument(
        '--provider',
        type=str,
        help='Comma-separated list of providers to sync (aws,azure,gcp). Default: all'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        default=True,
        help='Preview changes without copying files (default: True for safety)'
    )
    
    parser.add_argument(
        '--live',
        action='store_true',
        help='Perform actual sync (overrides --dry-run)'
    )
    
    parser.add_argument(
        '--force',
        action='store_true',
        help='Force overwrite without timestamp check'
    )
    
    parser.add_argument(
        '--backup',
        action='store_true',
        help='Create backup of existing recipes before overwriting'
    )
    
    parser.add_argument(
        '--stats-only',
        action='store_true',
        help='Show statistics only without performing sync'
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
    
    # Initialize syncer
    syncer = RecipeSync(
        source_base=args.source,
        dest_base=args.dest,
        providers=providers
    )
    
    # Validate paths
    if not syncer.validate_paths():
        sys.exit(1)
    
    try:
        if args.stats_only:
            # Just show analysis
            analysis = syncer.analyze_sync(providers)
            syncer.print_summary_report({
                'analysis': analysis,
                'operations': [],
                'stats': syncer.stats,
                'dry_run': True
            })
        else:
            # Perform sync (dry run or live)
            results = syncer.sync_recipes(
                providers=providers,
                dry_run=dry_run,
                force=args.force,
                backup=args.backup
            )
            
            syncer.print_summary_report(results)
            
            # Exit with error code if there were errors
            if results['stats']['errors'] > 0:
                sys.exit(1)
                
    except KeyboardInterrupt:
        logger.error("Sync interrupted by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Sync failed: {e}")
        if args.verbose:
            logger.exception("Full error details:")
        sys.exit(1)


if __name__ == '__main__':
    main()