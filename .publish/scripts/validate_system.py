#!/usr/bin/env python3
"""
System Validation Script - Comprehensive validation of the README generation system.

This script performs comprehensive validation of:
- System dependencies and configuration
- Recipe file structure and metadata
- Taxonomy mapping correctness
- Template rendering capabilities
- GitHub Actions workflow validation

Usage:
    python validate_system.py [options]
"""

import os
import sys
import json
import yaml
import logging
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional
import argparse

# Add scripts directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    import frontmatter
    from jinja2 import Environment, FileSystemLoader
    from recipe_parser import RecipeParser, Recipe
    from taxonomy_mapper import TaxonomyMapper
    from readme_generator import ReadmeGenerator
except ImportError as e:
    print(f"❌ Import error: {e}")
    print("Please install required dependencies: pip install -r requirements.txt")
    sys.exit(1)

logger = logging.getLogger(__name__)


class SystemValidator:
    """Comprehensive system validation for the README generation system."""
    
    def __init__(self, config_path: str = '../data/config.json'):
        """Initialize the system validator."""
        self.config_path = config_path
        self.validation_results = {
            'dependencies': {'status': 'pending', 'issues': []},
            'configuration': {'status': 'pending', 'issues': []},
            'file_structure': {'status': 'pending', 'issues': []},
            'recipes': {'status': 'pending', 'issues': []},
            'taxonomy': {'status': 'pending', 'issues': []},
            'templates': {'status': 'pending', 'issues': []},
            'generation': {'status': 'pending', 'issues': []},
            'github_actions': {'status': 'pending', 'issues': []}
        }
        self.errors = []
        self.warnings = []
    
    def validate_dependencies(self) -> bool:
        """Validate that all required dependencies are available."""
        logger.info("Validating system dependencies...")
        issues = []
        
        # Check Python version
        python_version = sys.version_info
        if python_version < (3, 7):
            issues.append(f"Python 3.7+ required, found {python_version.major}.{python_version.minor}")
        
        # Check required modules
        required_modules = [
            'frontmatter', 'jinja2', 'yaml', 'pathlib', 
            'concurrent.futures', 'typing'
        ]
        
        for module in required_modules:
            try:
                __import__(module)
                logger.debug(f"✅ Module '{module}' available")
            except ImportError:
                issues.append(f"Required module '{module}' not available")
        
        # Check requirements.txt
        req_file = Path('scripts/requirements.txt')
        if not req_file.exists():
            issues.append("requirements.txt not found in scripts directory")
        else:
            logger.debug("✅ requirements.txt found")
        
        self.validation_results['dependencies'] = {
            'status': 'passed' if not issues else 'failed',
            'issues': issues
        }
        
        return not issues
    
    def validate_configuration(self) -> bool:
        """Validate configuration files and settings."""
        logger.info("Validating configuration files...")
        issues = []
        
        # Check main config file
        if not os.path.exists(self.config_path):
            issues.append(f"Configuration file not found: {self.config_path}")
            self.validation_results['configuration'] = {
                'status': 'failed',
                'issues': issues
            }
            return False
        
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
            
            # Validate required config fields
            required_fields = [
                'providers', 'recipe_directories', 'required_frontmatter_fields'
            ]
            
            for field in required_fields:
                if field not in config:
                    issues.append(f"Missing required config field: {field}")
            
            # Validate provider directories
            for provider, directory in config.get('recipe_directories', {}).items():
                if not os.path.exists(directory):
                    issues.append(f"Provider directory not found: {directory} for {provider}")
            
            # Check taxonomy file
            taxonomy_file = '../data/taxonomy.json'
            if not os.path.exists(taxonomy_file):
                issues.append(f"Taxonomy file not found: {taxonomy_file}")
            else:
                try:
                    with open(taxonomy_file, 'r', encoding='utf-8') as f:
                        taxonomy = json.load(f)
                    
                    if 'categories' not in taxonomy:
                        issues.append("Taxonomy file missing 'categories' section")
                    
                    logger.debug("✅ Taxonomy file valid")
                except json.JSONDecodeError as e:
                    issues.append(f"Invalid JSON in taxonomy file: {e}")
                except Exception as e:
                    issues.append(f"Error reading taxonomy file: {e}")
            
            logger.debug("✅ Configuration files valid")
            
        except json.JSONDecodeError as e:
            issues.append(f"Invalid JSON in config file: {e}")
        except Exception as e:
            issues.append(f"Error reading config file: {e}")
        
        self.validation_results['configuration'] = {
            'status': 'passed' if not issues else 'failed',
            'issues': issues
        }
        
        return not issues
    
    def validate_file_structure(self) -> bool:
        """Validate the expected file and directory structure."""
        logger.info("Validating file structure...")
        issues = []
        
        # Required directories (relative to repository root)
        required_dirs = [
            '../data', '../templates', '../../aws', '../../azure', '../../gcp'
        ]
        
        for directory in required_dirs:
            if not os.path.exists(directory):
                issues.append(f"Required directory missing: {directory}")
        
        # Required files
        required_files = [
            'recipe_parser.py',
            'taxonomy_mapper.py', 
            'readme_generator.py',
            'requirements.txt',
            '../data/config.json',
            '../data/taxonomy.json',
            '../templates/README.jinja2'
        ]
        
        for file_path in required_files:
            if not os.path.exists(file_path):
                issues.append(f"Required file missing: {file_path}")
        
        self.validation_results['file_structure'] = {
            'status': 'passed' if not issues else 'failed',
            'issues': issues
        }
        
        return not issues
    
    def validate_recipes(self, root_directory: str = '..') -> bool:
        """Validate recipe files and their metadata."""
        logger.info("Validating recipe files...")
        issues = []
        
        try:
            parser = RecipeParser(self.config_path)
            recipe_files = parser.discover_recipe_files(root_directory)
            
            if not recipe_files:
                issues.append("No recipe files discovered")
                self.validation_results['recipes'] = {
                    'status': 'failed',
                    'issues': issues
                }
                return False
            
            logger.info(f"Found {len(recipe_files)} recipe files")
            
            # Parse recipes and collect validation issues
            valid_recipes = 0
            invalid_recipes = 0
            
            for file_path in recipe_files[:50]:  # Limit validation to 50 files for performance
                try:
                    recipe = parser.parse_recipe_file(file_path)
                    if recipe:
                        valid_recipes += 1
                        
                        # Validate recipe metadata completeness
                        if not recipe.title.strip():
                            issues.append(f"Empty title in {file_path}")
                        
                        if not recipe.id.strip():
                            issues.append(f"Empty ID in {file_path}")
                        
                        if not recipe.services:
                            issues.append(f"No services listed in {file_path}")
                        
                        if recipe.difficulty not in [100, 200, 300, 400]:
                            issues.append(f"Invalid difficulty level in {file_path}: {recipe.difficulty}")
                        
                    else:
                        invalid_recipes += 1
                        
                except Exception as e:
                    invalid_recipes += 1
                    issues.append(f"Error parsing {file_path}: {e}")
            
            logger.info(f"Validation complete: {valid_recipes} valid, {invalid_recipes} invalid")
            
            # Add parser errors to validation issues
            for error in parser.errors:
                issues.append(f"Parser error: {error}")
            
            # Add warnings as info
            for warning in parser.warnings:
                self.warnings.append(f"Parser warning: {warning}")
            
        except Exception as e:
            issues.append(f"Recipe validation failed: {e}")
        
        self.validation_results['recipes'] = {
            'status': 'passed' if not issues else 'failed',
            'issues': issues
        }
        
        return not issues
    
    def validate_taxonomy(self) -> bool:
        """Validate taxonomy mapping functionality."""
        logger.info("Validating taxonomy mapping...")
        issues = []
        
        try:
            mapper = TaxonomyMapper()
            
            # Test category mappings
            test_cases = [
                ('compute', 'Compute & Infrastructure'),
                ('storage', 'Storage & Data Management'),
                ('database', 'Databases & Analytics'),
                ('networking', 'Networking & Content Delivery'),
                ('unknown-category', 'Specialized Solutions')  # Fallback test
            ]
            
            for input_category, expected_output in test_cases:
                result = mapper.normalize_category_name(input_category)
                if result != expected_output:
                    issues.append(f"Category mapping failed: '{input_category}' -> '{result}', expected '{expected_output}'")
            
            # Test recipe categorization
            test_recipe = {
                'title': 'Test Serverless Application',
                'category': 'compute',
                'services': ['lambda', 's3', 'api-gateway'],
                'provider': 'aws'
            }
            
            category = mapper.categorize_recipe(test_recipe)
            if category != 'Compute & Infrastructure':
                issues.append(f"Recipe categorization failed: got '{category}', expected 'Compute & Infrastructure'")
            
            # Test all categories exist
            all_categories = mapper.get_all_categories()
            if len(all_categories) < 10:  # We expect at least 10 categories
                issues.append(f"Too few categories found: {len(all_categories)}")
            
            logger.debug(f"✅ Found {len(all_categories)} categories")
            
        except Exception as e:
            issues.append(f"Taxonomy validation failed: {e}")
        
        self.validation_results['taxonomy'] = {
            'status': 'passed' if not issues else 'failed',
            'issues': issues
        }
        
        return not issues
    
    def validate_templates(self) -> bool:
        """Validate Jinja2 templates and rendering."""
        logger.info("Validating templates...")
        issues = []
        
        # Check template files exist
        template_files = ['../templates/README.jinja2', '../templates/category_section.jinja2']
        
        for template_file in template_files:
            if not os.path.exists(template_file):
                issues.append(f"Template file missing: {template_file}")
                continue
            
            try:
                # Try to load and parse template
                with open(template_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                # Basic syntax validation using Jinja2
                env = Environment(loader=FileSystemLoader('../templates'))
                template = env.from_string(content)
                
                logger.debug(f"✅ Template valid: {template_file}")
                
            except Exception as e:
                issues.append(f"Template syntax error in {template_file}: {e}")
        
        # Test template rendering with mock data
        try:
            mock_context = {
                'categories': [{
                    'name': 'Test Category',
                    'emoji': '🧪',
                    'description': 'Test description',
                    'recipes': [{
                        'title': 'Test Recipe',
                        'relative_path': 'test/recipe.md',
                        'difficulty_name': 'Beginner',
                        'provider_display': 'AWS',
                        'provider': 'aws',
                        'services': ['lambda', 's3'],
                        'estimated_time': '30 minutes'
                    }],
                    'count': 1
                }],
                'statistics': {
                    'total_recipes': 1,
                    'provider_counts': {'aws': 1},
                    'categories_with_recipes': 1,
                    'average_difficulty': 1.0,
                    'top_services': [('lambda', 1)]
                },
                'config': {},
                'generation_settings': {},
                'timestamp': '2024-01-01 00:00:00 UTC',
                'total_recipes': 1
            }
            
            env = Environment(loader=FileSystemLoader('templates'))
            template = env.get_template('README.jinja2')
            rendered = template.render(**mock_context)
            
            if len(rendered) < 100:  # Sanity check
                issues.append("Template rendering produced unexpectedly short output")
            
            logger.debug("✅ Template rendering test passed")
            
        except Exception as e:
            issues.append(f"Template rendering test failed: {e}")
        
        self.validation_results['templates'] = {
            'status': 'passed' if not issues else 'failed',
            'issues': issues
        }
        
        return not issues
    
    def validate_generation(self, root_directory: str = '.') -> bool:
        """Validate the complete README generation process."""
        logger.info("Validating README generation process...")
        issues = []
        
        try:
            # Test the full generation process
            generator = ReadmeGenerator(self.config_path)
            generator.load_and_process_recipes(root_directory)
            
            # Check that recipes were loaded
            if len(generator.recipes) == 0:
                issues.append("No recipes were loaded for generation")
                self.validation_results['generation'] = {
                    'status': 'failed',
                    'issues': issues
                }
                return False
            
            # Test statistics generation
            if not generator.statistics:
                issues.append("Statistics were not generated")
            
            # Test categorization
            if not generator.categorized_recipes:
                issues.append("Recipes were not categorized")
            
            # Test report generation
            report = generator.get_generation_report()
            if not report or 'total_recipes_processed' not in report:
                issues.append("Generation report is invalid")
            
            logger.info(f"✅ Generated report for {len(generator.recipes)} recipes")
            
        except Exception as e:
            issues.append(f"Generation process failed: {e}")
        
        self.validation_results['generation'] = {
            'status': 'passed' if not issues else 'failed',
            'issues': issues
        }
        
        return not issues
    
    def validate_github_actions(self) -> bool:
        """Validate GitHub Actions workflow configuration."""
        logger.info("Validating GitHub Actions workflow...")
        issues = []
        
        workflow_file = '.github/workflows/update-readme.yml'
        
        if not os.path.exists(workflow_file):
            issues.append(f"GitHub Actions workflow file missing: {workflow_file}")
            self.validation_results['github_actions'] = {
                'status': 'failed',
                'issues': issues
            }
            return False
        
        try:
            with open(workflow_file, 'r', encoding='utf-8') as f:
                workflow_content = f.read()
            
            # Parse YAML
            workflow = yaml.safe_load(workflow_content)
            
            # Check required sections
            required_sections = ['name', 'on', 'jobs']
            for section in required_sections:
                if section not in workflow:
                    issues.append(f"Missing required section in workflow: {section}")
            
            # Check for required jobs
            jobs = workflow.get('jobs', {})
            expected_jobs = ['detect-changes', 'update-readme']
            for job in expected_jobs:
                if job not in jobs:
                    issues.append(f"Missing required job in workflow: {job}")
            
            # Check for Python setup
            update_readme_job = jobs.get('update-readme', {})
            steps = update_readme_job.get('steps', [])
            
            has_python_setup = any('setup-python' in str(step) for step in steps)
            if not has_python_setup:
                issues.append("Workflow missing Python setup step")
            
            has_install_deps = any('pip install' in str(step) for step in steps)
            if not has_install_deps:
                issues.append("Workflow missing dependency installation step")
            
            logger.debug("✅ GitHub Actions workflow structure valid")
            
        except yaml.YAMLError as e:
            issues.append(f"Invalid YAML in workflow file: {e}")
        except Exception as e:
            issues.append(f"Error reading workflow file: {e}")
        
        self.validation_results['github_actions'] = {
            'status': 'passed' if not issues else 'failed',
            'issues': issues
        }
        
        return not issues
    
    def run_all_validations(self, root_directory: str = '.') -> Dict[str, Any]:
        """Run all validation checks and return comprehensive results."""
        logger.info("Running comprehensive system validation...")
        
        validation_functions = [
            self.validate_dependencies,
            self.validate_configuration,
            self.validate_file_structure,
            lambda: self.validate_recipes(root_directory),
            self.validate_taxonomy,
            self.validate_templates,
            lambda: self.validate_generation(root_directory),
            self.validate_github_actions
        ]
        
        passed = 0
        failed = 0
        
        for validation_func in validation_functions:
            try:
                if validation_func():
                    passed += 1
                else:
                    failed += 1
            except Exception as e:
                failed += 1
                self.errors.append(f"Validation function failed: {e}")
        
        # Generate overall summary
        overall_status = 'passed' if failed == 0 else 'failed'
        
        return {
            'overall_status': overall_status,
            'passed_validations': passed,
            'failed_validations': failed,
            'total_validations': passed + failed,
            'validation_results': self.validation_results,
            'errors': self.errors,
            'warnings': self.warnings,
            'timestamp': json.dumps(None)  # Will be serialized properly
        }


def main():
    """Main CLI function."""
    parser = argparse.ArgumentParser(
        description='Validate the README generation system',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--config', '-c',
        type=str,
        default='../data/config.json',
        help='Path to configuration file'
    )
    
    parser.add_argument(
        '--root', '-r',
        type=str,
        default='.',
        help='Root directory for recipe validation'
    )
    
    parser.add_argument(
        '--output', '-o',
        type=str,
        help='Output validation report to JSON file'
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
    
    # Setup logging
    if args.quiet:
        logging.basicConfig(level=logging.ERROR, format='%(levelname)s: %(message)s')
    elif args.verbose:
        logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(levelname)s - %(message)s')
    else:
        logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
    
    try:
        # Run validation
        validator = SystemValidator(args.config)
        results = validator.run_all_validations(args.root)
        
        # Output results
        if args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                json.dump(results, f, indent=2, default=str)
            logger.info(f"Validation report saved to: {args.output}")
        
        # Print summary
        if not args.quiet:
            print("\n" + "="*60)
            print("SYSTEM VALIDATION RESULTS")
            print("="*60)
            print(f"Overall Status: {'✅ PASSED' if results['overall_status'] == 'passed' else '❌ FAILED'}")
            print(f"Passed: {results['passed_validations']}/{results['total_validations']}")
            print(f"Failed: {results['failed_validations']}/{results['total_validations']}")
            
            # Show detailed results
            print(f"\nDetailed Results:")
            for category, result in results['validation_results'].items():
                status = "✅" if result['status'] == 'passed' else "❌" 
                print(f"  {status} {category.replace('_', ' ').title()}")
                
                if result['issues']:
                    for issue in result['issues']:
                        print(f"      • {issue}")
            
            if results['warnings']:
                print(f"\nWarnings ({len(results['warnings'])}):")
                for warning in results['warnings']:
                    print(f"  ⚠️  {warning}")
            
            if results['errors']:
                print(f"\nErrors ({len(results['errors'])}):")
                for error in results['errors']:
                    print(f"  ❌ {error}")
        
        # Exit with appropriate code
        sys.exit(0 if results['overall_status'] == 'passed' else 1)
        
    except KeyboardInterrupt:
        logger.error("Validation cancelled by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"Validation failed: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()