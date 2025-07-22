#!/usr/bin/env python3
"""
Taxonomy Mapper - Maps recipes to the standardized 12-category taxonomy.

This module provides functionality to:
- Load taxonomy configuration
- Categorize recipes based on metadata
- Handle fallback logic for unknown categories
- Validate category assignments
"""

import json
import logging
from typing import Dict, List, Any, Optional, Set
from pathlib import Path

logger = logging.getLogger(__name__)


class TaxonomyMapper:
    """Maps recipes to standardized categories based on taxonomy configuration."""
    
    def __init__(self, taxonomy_path: str = 'data/taxonomy.json'):
        """Initialize the taxonomy mapper."""
        self.taxonomy = self._load_taxonomy(taxonomy_path)
        self.category_mappings = self._build_category_mappings()
        self.service_mappings = self._build_service_mappings()
        self.keyword_mappings = self._build_keyword_mappings()
        
    def _load_taxonomy(self, taxonomy_path: str) -> Dict[str, Any]:
        """Load taxonomy configuration from JSON file."""
        try:
            with open(taxonomy_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load taxonomy from {taxonomy_path}: {e}")
            raise
    
    def _build_category_mappings(self) -> Dict[str, str]:
        """Build mappings from category keys to display names."""
        mappings = {}
        for category_key, category_data in self.taxonomy['categories'].items():
            mappings[category_key] = category_data['name']
            # Also map variations of the category name
            name_variations = [
                category_key,
                category_key.replace('-', '_'),
                category_key.replace('-', ''),
                category_data['name'].lower().replace(' ', '-'),
                category_data['name'].lower().replace(' ', '_'),
                category_data['name'].lower().replace(' ', ''),
            ]
            for variation in name_variations:
                mappings[variation] = category_data['name']
                
        return mappings
    
    def _build_service_mappings(self) -> Dict[str, Dict[str, str]]:
        """Build mappings from services to categories by provider."""
        mappings = {}
        for provider in ['aws', 'azure', 'gcp']:
            mappings[provider] = {}
            for category_key, category_data in self.taxonomy['categories'].items():
                services = category_data.get('services', {}).get(provider, [])
                for service in services:
                    mappings[provider][service.lower()] = category_key
                    # Add variations
                    service_variations = [
                        service.replace('-', '_'),
                        service.replace('_', '-'),
                        service.replace('-', ''),
                        service.replace('_', '')
                    ]
                    for variation in service_variations:
                        mappings[provider][variation.lower()] = category_key
        return mappings
    
    def _build_keyword_mappings(self) -> Dict[str, str]:
        """Build mappings from keywords to categories."""
        mappings = {}
        for category_key, category_data in self.taxonomy['categories'].items():
            keywords = category_data.get('keywords', [])
            for keyword in keywords:
                mappings[keyword.lower()] = category_key
        return mappings
    
    def normalize_category_name(self, category: str) -> str:
        """Normalize a category name to match taxonomy standards."""
        if not category:
            return 'specialized-solutions'  # default fallback
            
        # Clean the category name
        cleaned = category.lower().strip()
        
        # Direct mapping lookup
        if cleaned in self.category_mappings:
            return self.category_mappings[cleaned]
        
        # Try common variations
        variations = [
            cleaned.replace(' ', '-'),
            cleaned.replace(' ', '_'),
            cleaned.replace('_', '-'),
            cleaned.replace('-', '_'),
            cleaned.replace(' ', ''),
            cleaned.replace('-', ''),
            cleaned.replace('_', '')
        ]
        
        for variation in variations:
            if variation in self.category_mappings:
                return self.category_mappings[variation]
        
        # Keyword-based mapping
        category_key = self._map_by_keywords(cleaned)
        if category_key:
            return self.taxonomy['categories'][category_key]['name']
            
        # Default fallback
        logger.warning(f"Could not normalize category: {category}")
        return 'Specialized Solutions'
    
    def categorize_recipe(self, recipe_data: Dict[str, Any]) -> str:
        """Categorize a recipe based on its metadata."""
        # Primary: Use explicit category from frontmatter
        explicit_category = recipe_data.get('category', '').strip()
        if explicit_category:
            normalized = self.normalize_category_name(explicit_category)
            if normalized != 'Specialized Solutions':  # Valid mapping found
                return normalized
        
        # Secondary: Use services to determine category
        services = recipe_data.get('services', [])
        provider = recipe_data.get('provider', 'aws')
        
        if services:
            category_key = self._categorize_by_services(services, provider)
            if category_key:
                return self.taxonomy['categories'][category_key]['name']
        
        # Tertiary: Use title/content keywords
        title = recipe_data.get('title', '').lower()
        tags = recipe_data.get('tags', [])
        
        category_key = self._categorize_by_keywords(title, tags)
        if category_key:
            return self.taxonomy['categories'][category_key]['name']
        
        # Final fallback
        logger.warning(f"Could not categorize recipe: {recipe_data.get('title', 'Unknown')}")
        return 'Specialized Solutions'
    
    def _categorize_by_services(self, services: List[str], provider: str) -> Optional[str]:
        """Categorize based on services used."""
        if not services or provider not in self.service_mappings:
            return None
            
        provider_mappings = self.service_mappings[provider]
        category_scores = {}
        
        for service in services:
            service_clean = service.lower().strip()
            if service_clean in provider_mappings:
                category = provider_mappings[service_clean]
                category_scores[category] = category_scores.get(category, 0) + 1
        
        if category_scores:
            # Return the category with the highest score
            return max(category_scores, key=category_scores.get)
        
        return None
    
    def _categorize_by_keywords(self, title: str, tags: List[str]) -> Optional[str]:
        """Categorize based on keywords in title and tags."""
        text_to_analyze = title.lower()
        if tags:
            text_to_analyze += ' ' + ' '.join(str(tag).lower() for tag in tags)
        
        return self._map_by_keywords(text_to_analyze)
    
    def _map_by_keywords(self, text: str) -> Optional[str]:
        """Map text to category based on keyword matching."""
        category_scores = {}
        
        for keyword, category_key in self.keyword_mappings.items():
            if keyword in text:
                category_scores[category_key] = category_scores.get(category_key, 0) + 1
        
        if category_scores:
            return max(category_scores, key=category_scores.get)
        
        return None
    
    def get_category_info(self, category_name: str) -> Dict[str, Any]:
        """Get detailed information about a category."""
        for category_key, category_data in self.taxonomy['categories'].items():
            if category_data['name'] == category_name:
                return {
                    'key': category_key,
                    'name': category_data['name'],
                    'emoji': category_data.get('emoji', '📁'),
                    'description': category_data.get('description', ''),
                    'keywords': category_data.get('keywords', []),
                    'services': category_data.get('services', {})
                }
        return {}
    
    def get_all_categories(self) -> List[Dict[str, Any]]:
        """Get all categories with their information."""
        categories = []
        for category_key, category_data in self.taxonomy['categories'].items():
            categories.append({
                'key': category_key,
                'name': category_data['name'],
                'emoji': category_data.get('emoji', '📁'),
                'description': category_data.get('description', ''),
                'order': self._get_category_order(category_key)
            })
        
        # Sort by the standard order
        return sorted(categories, key=lambda x: x['order'])
    
    def _get_category_order(self, category_key: str) -> int:
        """Get the display order for a category."""
        order_map = {
            'compute-infrastructure': 1,
            'storage-data-management': 2,
            'databases-analytics': 3,
            'networking-content-delivery': 4,
            'security-identity': 5,
            'ai-machine-learning': 6,
            'application-development-deployment': 7,
            'monitoring-management': 8,
            'integration-messaging': 9,
            'iot-edge-computing': 10,
            'media-content': 11,
            'specialized-solutions': 12
        }
        return order_map.get(category_key, 999)
    
    def validate_recipe_categories(self, recipes: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Validate and report on recipe categorization."""
        validation_report = {
            'total_recipes': len(recipes),
            'categorized_recipes': 0,
            'uncategorized_recipes': 0,
            'category_distribution': {},
            'validation_warnings': [],
            'category_mapping_suggestions': {}
        }
        
        for recipe in recipes:
            category = self.categorize_recipe(recipe)
            
            if category == 'Specialized Solutions' and recipe.get('category'):
                validation_report['uncategorized_recipes'] += 1
                validation_report['validation_warnings'].append(
                    f"Could not categorize recipe '{recipe.get('title', 'Unknown')}' "
                    f"with category '{recipe.get('category', 'Unknown')}'"
                )
            else:
                validation_report['categorized_recipes'] += 1
            
            # Count category distribution
            validation_report['category_distribution'][category] = (
                validation_report['category_distribution'].get(category, 0) + 1
            )
        
        return validation_report


def main():
    """Main function for testing the taxonomy mapper."""
    import logging
    logging.basicConfig(level=logging.INFO)
    
    mapper = TaxonomyMapper()
    
    # Test recipe
    test_recipe = {
        'title': 'Serverless Web Applications with Lambda',
        'category': 'compute',
        'services': ['lambda', 's3', 'api-gateway'],
        'provider': 'aws',
        'tags': ['serverless', 'web', 'api']
    }
    
    category = mapper.categorize_recipe(test_recipe)
    print(f"Recipe categorized as: {category}")
    
    # Show all categories
    categories = mapper.get_all_categories()
    print(f"\nTotal categories: {len(categories)}")
    for cat in categories:
        print(f"  {cat['emoji']} {cat['name']}")


if __name__ == '__main__':
    main()