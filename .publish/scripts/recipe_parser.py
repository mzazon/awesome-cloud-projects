#!/usr/bin/env python3
"""
Recipe Parser - Extracts and parses YAML frontmatter from recipe markdown files.

This module provides functionality to:
- Discover recipe files across provider directories
- Parse YAML frontmatter from markdown files
- Validate recipe structure and metadata
- Handle CSV mapping files for recipe renaming
"""

import os
import json
import csv
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
import frontmatter
import yaml

logger = logging.getLogger(__name__)


class Recipe:
    """Represents a single cloud recipe with metadata and content."""
    
    def __init__(self, file_path: str, frontmatter_data: Dict[str, Any], content: str):
        self.file_path = file_path
        self.metadata = frontmatter_data
        self.content = content
        self.provider = self._determine_provider()
        self.folder_name = self._extract_folder_name()
        
    def _determine_provider(self) -> str:
        """Determine the cloud provider based on file path."""
        path_parts = Path(self.file_path).parts
        for part in path_parts:
            if part in ['aws', 'azure', 'gcp']:
                return part
        return 'unknown'
    
    def _extract_folder_name(self) -> str:
        """Extract the folder name from the file path."""
        return Path(self.file_path).parent.name
    
    @property
    def title(self) -> str:
        """Get the recipe title."""
        return self.metadata.get('title', 'Untitled Recipe')
    
    @property
    def id(self) -> str:
        """Get the recipe ID."""
        return self.metadata.get('id', '')
    
    @property
    def category(self) -> str:
        """Get the recipe category."""
        return self.metadata.get('category', 'unknown')
    
    @property
    def difficulty(self) -> int:
        """Get the recipe difficulty level."""
        return self.metadata.get('difficulty', 100)
    
    @property
    def services(self) -> List[str]:
        """Get the list of services used in the recipe."""
        services = self.metadata.get('services', '')
        if isinstance(services, str):
            return [s.strip() for s in services.split(',') if s.strip()]
        return services if isinstance(services, list) else []
    
    @property
    def estimated_time(self) -> str:
        """Get the estimated time for the recipe."""
        return self.metadata.get('estimated-time', 'Unknown')
    
    @property
    def tags(self) -> List[str]:
        """Get the recipe tags."""
        tags = self.metadata.get('tags', '')
        if isinstance(tags, str):
            return [t.strip() for t in tags.split(',') if t.strip()]
        return tags if isinstance(tags, list) else []
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert recipe to dictionary representation."""
        return {
            'file_path': self.file_path,
            'provider': self.provider,
            'folder_name': self.folder_name,
            'title': self.title,
            'id': self.id,
            'category': self.category,
            'difficulty': self.difficulty,
            'services': self.services,
            'estimated_time': self.estimated_time,
            'tags': self.tags,
            'metadata': self.metadata
        }


class RecipeParser:
    """Main parser class for discovering and parsing cloud recipes."""
    
    def __init__(self, config_path: str = 'data/config.json'):
        """Initialize the recipe parser with configuration."""
        self.config = self._load_config(config_path)
        self.recipes: List[Recipe] = []
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.csv_mappings: Dict[str, Dict[str, Dict[str, str]]] = {}
        
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load configuration from JSON file."""
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config from {config_path}: {e}")
            # Return default config
            return {
                'providers': ['aws', 'azure', 'gcp'],
                'recipe_directories': {'aws': 'aws', 'azure': 'azure', 'gcp': 'gcp'},
                'required_frontmatter_fields': ['title', 'category'],
                'csv_mapping_files': {}
            }
    
    def _load_csv_mappings(self) -> None:
        """Load CSV mapping files for recipe renaming."""
        self.csv_mappings = {}
        for provider, csv_file in self.config.get('csv_mapping_files', {}).items():
            try:
                if os.path.exists(csv_file):
                    with open(csv_file, 'r', encoding='utf-8') as f:
                        reader = csv.DictReader(f)
                        mappings = {}
                        for row in reader:
                            old_folder = row.get('existing_folder_name', '')
                            new_folder = row.get('new_folder_name', '')
                            old_title = row.get('existing_recipe_title', '')
                            new_title = row.get('new_recipe_title', '')
                            if old_folder and new_folder:
                                mappings[old_folder] = {
                                    'folder': new_folder,
                                    'title': new_title if new_title else old_title
                                }
                        self.csv_mappings[provider] = mappings
                        logger.info(f"Loaded {len(mappings)} mappings for {provider}")
                else:
                    logger.warning(f"CSV mapping file not found: {csv_file}")
            except Exception as e:
                logger.error(f"Failed to load CSV mappings for {provider}: {e}")
                self.errors.append(f"Failed to load CSV mappings for {provider}: {e}")
    
    def discover_recipe_files(self, root_directory: str = '.') -> List[str]:
        """Discover all recipe markdown files in provider directories."""
        recipe_files = []
        root_path = Path(root_directory)
        
        for provider in self.config['providers']:
            provider_dir = root_path / self.config['recipe_directories'][provider]
            if not provider_dir.exists():
                self.warnings.append(f"Provider directory not found: {provider_dir}")
                continue
                
            # Find all .md files in subdirectories
            for md_file in provider_dir.rglob('*.md'):
                # Skip README files and other non-recipe files
                if md_file.name.lower() in ['readme.md', 'contributing.md', 'license.md']:
                    continue
                recipe_files.append(str(md_file))
                
        logger.info(f"Discovered {len(recipe_files)} potential recipe files")
        return recipe_files
    
    def parse_recipe_file(self, file_path: str) -> Optional[Recipe]:
        """Parse a single recipe file and return a Recipe object."""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                post = frontmatter.load(f)
                
            # Check if file has frontmatter
            if not post.metadata:
                self.warnings.append(f"No frontmatter found in {file_path}")
                return None
                
            # Validate required fields
            missing_fields = []
            for field in self.config['required_frontmatter_fields']:
                if field not in post.metadata:
                    missing_fields.append(field)
                    
            if missing_fields:
                self.errors.append(f"Missing required fields in {file_path}: {missing_fields}")
                return None
            
            recipe = Recipe(file_path, post.metadata, post.content)
            
            # Apply CSV mappings if available
            self._apply_csv_mapping(recipe)
            
            return recipe
            
        except yaml.YAMLError as e:
            self.errors.append(f"YAML parsing error in {file_path}: {e}")
            return None
        except Exception as e:
            self.errors.append(f"Error parsing {file_path}: {e}")
            return None
    
    def _apply_csv_mapping(self, recipe: Recipe) -> None:
        """Apply CSV mapping to update recipe title and folder name."""
        provider_mappings = self.csv_mappings.get(recipe.provider, {})
        folder_mapping = provider_mappings.get(recipe.folder_name)
        
        if folder_mapping:
            # Update title if mapping exists
            if folder_mapping.get('title'):
                recipe.metadata['title'] = folder_mapping['title']
            logger.debug(f"Applied mapping for {recipe.provider}/{recipe.folder_name}")
    
    def parse_recipes_parallel(self, file_paths: List[str], max_workers: int = 4) -> List[Recipe]:
        """Parse multiple recipe files in parallel."""
        recipes = []
        
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit all parsing tasks
            future_to_path = {
                executor.submit(self.parse_recipe_file, path): path 
                for path in file_paths
            }
            
            # Collect results
            for future in as_completed(future_to_path):
                path = future_to_path[future]
                try:
                    recipe = future.result()
                    if recipe:
                        recipes.append(recipe)
                except Exception as e:
                    self.errors.append(f"Error processing {path}: {e}")
        
        return recipes
    
    def parse_all_recipes(self, root_directory: str = '.') -> List[Recipe]:
        """Discover and parse all recipe files."""
        logger.info("Starting recipe discovery and parsing...")
        
        # Load CSV mappings
        self._load_csv_mappings()
        
        # Discover recipe files
        recipe_files = self.discover_recipe_files(root_directory)
        
        if not recipe_files:
            self.warnings.append("No recipe files discovered")
            return []
        
        # Parse recipes in parallel
        self.recipes = self.parse_recipes_parallel(recipe_files)
        
        logger.info(f"Successfully parsed {len(self.recipes)} recipes")
        logger.info(f"Encountered {len(self.errors)} errors and {len(self.warnings)} warnings")
        
        return self.recipes
    
    def get_recipes_by_provider(self, provider: str) -> List[Recipe]:
        """Get all recipes for a specific provider."""
        return [r for r in self.recipes if r.provider == provider]
    
    def get_recipes_by_category(self, category: str) -> List[Recipe]:
        """Get all recipes for a specific category."""
        return [r for r in self.recipes if r.category == category]
    
    def get_parsing_report(self) -> Dict[str, Any]:
        """Generate a comprehensive parsing report."""
        provider_counts = {}
        category_counts = {}
        difficulty_counts = {}
        
        for recipe in self.recipes:
            # Count by provider
            provider_counts[recipe.provider] = provider_counts.get(recipe.provider, 0) + 1
            
            # Count by category
            category_counts[recipe.category] = category_counts.get(recipe.category, 0) + 1
            
            # Count by difficulty
            difficulty_counts[recipe.difficulty] = difficulty_counts.get(recipe.difficulty, 0) + 1
        
        return {
            'total_recipes': len(self.recipes),
            'provider_breakdown': provider_counts,
            'category_breakdown': category_counts,
            'difficulty_breakdown': difficulty_counts,
            'errors': self.errors,
            'warnings': self.warnings,
            'csv_mappings_loaded': len(self.csv_mappings)
        }


def main():
    """Main function for testing the recipe parser."""
    import logging
    logging.basicConfig(level=logging.INFO)
    
    parser = RecipeParser()
    recipes = parser.parse_all_recipes()
    
    report = parser.get_parsing_report()
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()