#!/usr/bin/env python3
"""
README Generator - Generates README.md from recipe metadata using Jinja2 templates.

This module provides functionality to:
- Parse all recipes using RecipeParser
- Categorize recipes using TaxonomyMapper
- Generate statistics and organize content
- Render README.md using Jinja2 templates
"""

import os
import json
import logging
from datetime import datetime
from typing import Dict, List, Any, Optional
from pathlib import Path
from collections import defaultdict

try:
    from jinja2 import Environment, FileSystemLoader, Template
except ImportError:
    raise ImportError("jinja2 is required. Install it with: pip install jinja2")

from recipe_parser import RecipeParser
from taxonomy_mapper import TaxonomyMapper

logger = logging.getLogger(__name__)


class ReadmeGenerator:
    """Generates README.md from recipe metadata using Jinja2 templates."""
    
    def __init__(self, config_path: str = '../data/config.json'):
        """Initialize the README generator with configuration."""
        self.config = self._load_config(config_path)
        self.parser = RecipeParser(config_path)
        self.mapper = TaxonomyMapper()
        self.recipes: List[Dict[str, Any]] = []
        self.categorized_recipes: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        self.statistics: Dict[str, Any] = {}
        
    def _load_config(self, config_path: str) -> Dict[str, Any]:
        """Load configuration from JSON file."""
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load config from {config_path}: {e}")
            raise
    
    def load_and_process_recipes(self, root_directory: str = '.') -> None:
        """Load all recipes and process them for README generation."""
        logger.info("Loading and processing recipes...")
        
        # Parse all recipes
        raw_recipes = self.parser.parse_all_recipes(root_directory)
        
        # Convert to dictionary format and categorize
        self.recipes = []
        for recipe in raw_recipes:
            recipe_dict = recipe.to_dict()
            
            # Use taxonomy mapper to get proper category
            recipe_dict['category'] = self.mapper.categorize_recipe(recipe_dict)
            
            # Add additional computed fields
            recipe_dict['relative_path'] = os.path.relpath(recipe.file_path, root_directory)
            recipe_dict['github_url'] = self._generate_github_url(recipe_dict['relative_path'])
            recipe_dict['difficulty_name'] = self._get_difficulty_name(recipe_dict['difficulty'])
            recipe_dict['provider_display'] = self._get_provider_display_name(recipe_dict['provider'])
            
            self.recipes.append(recipe_dict)
        
        # Organize recipes by category
        self._organize_by_categories()
        
        # Generate statistics
        self._generate_statistics()
        
        logger.info(f"Processed {len(self.recipes)} recipes in {len(self.categorized_recipes)} categories")
    
    def _organize_by_categories(self) -> None:
        """Organize recipes by their categories."""
        self.categorized_recipes = defaultdict(list)
        
        for recipe in self.recipes:
            category = recipe['category']
            self.categorized_recipes[category].append(recipe)
        
        # Sort recipes within each category
        sort_key = self.config['generation_settings'].get('sort_projects_by', 'title')
        for category in self.categorized_recipes:
            self.categorized_recipes[category].sort(
                key=lambda x: x.get(sort_key, '').lower()
            )
    
    def _generate_statistics(self) -> None:
        """Generate comprehensive statistics for the README."""
        provider_counts = defaultdict(int)
        difficulty_counts = defaultdict(int)
        category_counts = defaultdict(int)
        service_usage = defaultdict(int)
        
        for recipe in self.recipes:
            provider_counts[recipe['provider']] += 1
            difficulty_counts[recipe['difficulty']] += 1
            category_counts[recipe['category']] += 1
            
            # Count service usage
            for service in recipe['services']:
                service_usage[service.lower().strip()] += 1
        
        # Calculate additional metrics
        total_recipes = len(self.recipes)
        avg_difficulty = sum(r['difficulty'] for r in self.recipes) / total_recipes if total_recipes > 0 else 0
        
        # Top services (limit to top 10)
        top_services = sorted(service_usage.items(), key=lambda x: x[1], reverse=True)[:10]
        
        self.statistics = {
            'total_recipes': total_recipes,
            'provider_counts': dict(provider_counts),
            'difficulty_counts': dict(difficulty_counts),
            'category_counts': dict(category_counts),
            'top_services': top_services,
            'average_difficulty': round(avg_difficulty, 1),
            'generation_timestamp': datetime.now().isoformat(),
            'categories_with_recipes': len(self.categorized_recipes),
            'total_categories_available': len(self.mapper.get_all_categories())
        }
    
    def _generate_github_url(self, relative_path: str) -> str:
        """Generate GitHub URL for a recipe file."""
        # This would typically use the actual repository URL
        # For now, using a placeholder that can be configured
        base_url = "https://github.com/YOUR_USERNAME/awesome-cloud-projects/blob/main"
        return f"{base_url}/{relative_path}"
    
    def _get_difficulty_name(self, difficulty: int) -> str:
        """Get the display name for a difficulty level."""
        difficulty_map = {
            100: "Beginner",
            200: "Intermediate", 
            300: "Advanced",
            400: "Expert"
        }
        return difficulty_map.get(difficulty, "Unknown")
    
    def _get_provider_display_name(self, provider: str) -> str:
        """Get the display name for a provider."""
        provider_map = {
            'aws': 'AWS',
            'azure': 'Microsoft Azure',
            'gcp': 'Google Cloud Platform'
        }
        return provider_map.get(provider, provider.upper())
    
    def generate_readme(self, output_path: Optional[str] = None) -> str:
        """Generate the README content using Jinja2 templates."""
        if not output_path:
            output_path = self.config.get('output_file', 'README.md')
        
        template_path = self.config.get('template', 'templates/README.jinja2')
        
        # Check if template file exists
        if not os.path.exists(template_path):
            logger.warning(f"Template file {template_path} not found. Using built-in template.")
            return self._generate_with_builtin_template()
        
        # Load and render template
        try:
            template_dir = os.path.dirname(template_path)
            template_name = os.path.basename(template_path)
            
            env = Environment(
                loader=FileSystemLoader(template_dir),
                trim_blocks=True,
                lstrip_blocks=True
            )
            
            template = env.get_template(template_name)
            
            # Prepare template context
            context = self._prepare_template_context()
            
            # Render template
            content = template.render(**context)
            
            # Write to file
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            logger.info(f"Generated README.md at {output_path}")
            return content
            
        except Exception as e:
            logger.error(f"Error generating README with template: {e}")
            logger.info("Falling back to built-in template")
            return self._generate_with_builtin_template()
    
    def _prepare_template_context(self) -> Dict[str, Any]:
        """Prepare the context data for template rendering."""
        # Get all categories with their info
        all_categories = self.mapper.get_all_categories()
        
        # Filter to only categories that have recipes
        categories_with_recipes = []
        for category_info in all_categories:
            category_name = category_info['name']
            if category_name in self.categorized_recipes:
                category_info['recipes'] = self.categorized_recipes[category_name]
                category_info['count'] = len(self.categorized_recipes[category_name])
                categories_with_recipes.append(category_info)
        
        return {
            'categories': categories_with_recipes,
            'statistics': self.statistics,
            'config': self.config,
            'generation_settings': self.config.get('generation_settings', {}),
            'timestamp': datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC'),
            'total_recipes': self.statistics['total_recipes'],
            'provider_counts': self.statistics['provider_counts']
        }
    
    def _generate_with_builtin_template(self) -> str:
        """Generate README using a built-in template as fallback."""
        logger.info("Using built-in template for README generation")
        
        content_parts = []
        
        # Header
        content_parts.append("""# 🌟 Awesome Cloud Projects

A curated collection of cloud architecture recipes, tutorials, and real-world solutions across AWS, Azure, and Google Cloud Platform.

[![Awesome](https://awesome.re/badge.svg)](https://awesome.re)
[![GitHub stars](https://img.shields.io/github/stars/YOUR_USERNAME/awesome-cloud-projects.svg?style=social&label=Star)](https://github.com/YOUR_USERNAME/awesome-cloud-projects)
[![GitHub forks](https://img.shields.io/github/forks/YOUR_USERNAME/awesome-cloud-projects.svg?style=social&label=Fork)](https://github.com/YOUR_USERNAME/awesome-cloud-projects/fork)

""")
        
        # Statistics
        stats = self.statistics
        content_parts.append(f"""## 📊 Project Statistics

- **Total Projects**: {stats['total_recipes']}+
- **AWS Projects**: {stats['provider_counts'].get('aws', 0)}
- **Azure Projects**: {stats['provider_counts'].get('azure', 0)}
- **GCP Projects**: {stats['provider_counts'].get('gcp', 0)}
- **Categories**: {stats['categories_with_recipes']}
- **Average Difficulty**: {stats['average_difficulty']}/4

""")
        
        # Table of Contents
        content_parts.append("## 📚 Table of Contents\n\n")
        for category_info in self.mapper.get_all_categories():
            category_name = category_info['name']
            if category_name in self.categorized_recipes:
                count = len(self.categorized_recipes[category_name])
                emoji = category_info.get('emoji', '📁')
                anchor = category_name.lower().replace(' ', '-').replace('&', '')
                content_parts.append(f"- [{emoji} {category_name}](#{anchor}) ({count} projects)\n")
        
        content_parts.append("\n")
        
        # Categories and recipes
        for category_info in self.mapper.get_all_categories():
            category_name = category_info['name']
            if category_name not in self.categorized_recipes:
                continue
                
            recipes = self.categorized_recipes[category_name]
            emoji = category_info.get('emoji', '📁')
            description = category_info.get('description', '')
            
            content_parts.append(f"## {emoji} {category_name}\n\n")
            if description:
                content_parts.append(f"*{description}*\n\n")
            
            # Recipe list
            for recipe in recipes:
                title = recipe['title']
                relative_path = recipe['relative_path']
                difficulty = recipe['difficulty_name']
                provider = recipe['provider_display']
                services = ', '.join(recipe['services'][:3])  # Limit to first 3 services
                estimated_time = recipe['estimated_time']
                
                # Difficulty badge color
                difficulty_colors = {
                    'Beginner': 'brightgreen',
                    'Intermediate': 'yellow', 
                    'Advanced': 'orange',
                    'Expert': 'red'
                }
                color = difficulty_colors.get(difficulty, 'lightgrey')
                
                content_parts.append(
                    f"- **[{title}]({relative_path})** - "
                    f"![{difficulty}](https://img.shields.io/badge/{difficulty}-{color}) "
                    f"![{provider}](https://img.shields.io/badge/{provider}-blue) "
                    f"*{services}* ({estimated_time})\n"
                )
            
            content_parts.append("\n")
        
        # Footer
        content_parts.append(f"""---

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) for details on how to submit recipes, improvements, and suggestions.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⭐ Show Your Support

If this repository helps you build amazing cloud solutions, please give it a star ⭐

---

*Last updated: {datetime.now().strftime('%Y-%m-%d')}*
*Generated automatically from {stats['total_recipes']} cloud recipes*
""")
        
        content = ''.join(content_parts)
        
        # Write to file
        output_path = self.config.get('output_file', 'README.md')
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        logger.info(f"Generated README.md using built-in template at {output_path}")
        return content
    
    def get_generation_report(self) -> Dict[str, Any]:
        """Generate a comprehensive report about the README generation process."""
        parsing_report = self.parser.get_parsing_report()
        
        return {
            'generation_timestamp': datetime.now().isoformat(),
            'total_recipes_processed': len(self.recipes),
            'categories_used': list(self.categorized_recipes.keys()),
            'statistics': self.statistics,
            'parsing_report': parsing_report,
            'template_used': self.config.get('template', 'built-in'),
            'output_file': self.config.get('output_file', 'README.md'),
            'generation_settings': self.config.get('generation_settings', {}),
            'validation_results': self._validate_generation()
        }
    
    def _validate_generation(self) -> Dict[str, Any]:
        """Validate the generation results."""
        validation_results = {
            'total_recipes': len(self.recipes),
            'recipes_with_categories': sum(1 for r in self.recipes if r['category'] != 'Specialized Solutions'),
            'recipes_without_proper_categories': sum(1 for r in self.recipes if r['category'] == 'Specialized Solutions'),
            'empty_categories': [],
            'categories_with_most_recipes': [],
            'validation_warnings': []
        }
        
        # Find empty categories
        all_categories = [cat['name'] for cat in self.mapper.get_all_categories()]
        for category in all_categories:
            if category not in self.categorized_recipes or len(self.categorized_recipes[category]) == 0:
                validation_results['empty_categories'].append(category)
        
        # Find categories with most recipes
        category_counts = [(cat, len(recipes)) for cat, recipes in self.categorized_recipes.items()]
        validation_results['categories_with_most_recipes'] = sorted(category_counts, key=lambda x: x[1], reverse=True)[:5]
        
        # Add warnings for potential issues
        if validation_results['recipes_without_proper_categories'] > len(self.recipes) * 0.1:  # More than 10%
            validation_results['validation_warnings'].append(
                f"High number of recipes ({validation_results['recipes_without_proper_categories']}) "
                "falling back to 'Specialized Solutions' category"
            )
        
        return validation_results


def main():
    """Main function for testing the README generator."""
    import logging
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    
    generator = ReadmeGenerator()
    
    # Load and process recipes
    generator.load_and_process_recipes('.')
    
    # Generate README
    content = generator.generate_readme()
    
    # Generate report
    report = generator.get_generation_report()
    
    # Print summary
    print("\n" + "="*50)
    print("README GENERATION SUMMARY")
    print("="*50)
    print(f"Total recipes processed: {report['total_recipes_processed']}")
    print(f"Categories used: {len(report['categories_used'])}")
    print(f"Template: {report['template_used']}")
    print(f"Output file: {report['output_file']}")
    print(f"Generation timestamp: {report['generation_timestamp']}")
    
    # Validation summary
    validation = report['validation_results']
    print(f"\nValidation Results:")
    print(f"  Properly categorized: {validation['recipes_with_categories']}")
    print(f"  Fallback categorized: {validation['recipes_without_proper_categories']}")
    print(f"  Empty categories: {len(validation['empty_categories'])}")
    
    if validation['validation_warnings']:
        print(f"\nWarnings:")
        for warning in validation['validation_warnings']:
            print(f"  ⚠️  {warning}")
    
    print("\n✅ README.md generation completed!")


if __name__ == '__main__':
    main()