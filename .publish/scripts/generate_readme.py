#!/usr/bin/env python3
"""
CLI script to generate README.md from recipe metadata.

This script provides a command-line interface for generating the README.md
file from recipe metadata. It can be run locally or as part of CI/CD pipelines.

Usage:
    python generate_readme.py [options]
    
Examples:
    python generate_readme.py                      # Generate with default settings
    python generate_readme.py --output myreadme.md # Custom output file
    python generate_readme.py --verbose            # Verbose output
    python generate_readme.py --report             # Generate detailed report
"""

import os
import sys
import json
import logging
import argparse
from pathlib import Path
from typing import Optional

# Add the scripts directory to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from readme_generator import ReadmeGenerator


def setup_logging(verbose: bool = False) -> None:
    """Setup logging configuration."""
    level = logging.DEBUG if verbose else logging.INFO
    format_str = '%(asctime)s - %(name)s - %(levelname)s - %(message)s' if verbose else '%(levelname)s: %(message)s'
    
    logging.basicConfig(
        level=level,
        format=format_str,
        handlers=[
            logging.StreamHandler(sys.stdout)
        ]
    )


def main():
    """Main CLI function."""
    parser = argparse.ArgumentParser(
        description='Generate README.md from cloud recipe metadata',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                           Generate README.md with default settings
  %(prog)s --output docs/README.md   Generate to custom location
  %(prog)s --verbose                 Enable verbose logging
  %(prog)s --report --output report.json  Generate detailed JSON report
  %(prog)s --config myconfig.json    Use custom configuration
  %(prog)s --root /path/to/recipes   Use custom root directory
        """
    )
    
    parser.add_argument(
        '--config', '-c',
        type=str,
        default='../data/config.json',
        help='Path to configuration file (default: ../data/config.json)'
    )
    
    parser.add_argument(
        '--output', '-o',
        type=str,
        help='Output file path (overrides config setting)'
    )
    
    parser.add_argument(
        '--root', '-r',
        type=str,
        default='../..',
        help='Root directory to search for recipes (default: repository root)'
    )
    
    parser.add_argument(
        '--report',
        action='store_true',
        help='Generate detailed JSON report instead of README'
    )
    
    parser.add_argument(
        '--validate-only',
        action='store_true',
        help='Only validate recipes without generating README'
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
    
    parser.add_argument(
        '--check-config',
        action='store_true',
        help='Check configuration and exit'
    )
    
    args = parser.parse_args()
    
    # Setup logging
    if args.quiet:
        setup_logging(False)
        logging.getLogger().setLevel(logging.ERROR)
    else:
        setup_logging(args.verbose)
    
    logger = logging.getLogger(__name__)
    
    try:
        # Check if configuration file exists
        if not os.path.exists(args.config):
            logger.error(f"Configuration file not found: {args.config}")
            sys.exit(1)
        
        # Initialize generator
        logger.info(f"Initializing README generator with config: {args.config}")
        generator = ReadmeGenerator(args.config)
        
        # Check configuration if requested
        if args.check_config:
            logger.info("Configuration check:")
            config = generator.config
            logger.info(f"  Output file: {config.get('output_file', 'README.md')}")
            logger.info(f"  Template: {config.get('template', 'built-in')}")
            logger.info(f"  Providers: {', '.join(config.get('providers', []))}")
            logger.info(f"  Required fields: {', '.join(config.get('required_frontmatter_fields', []))}")
            logger.info("✅ Configuration is valid")
            return
        
        # Load and process recipes
        logger.info(f"Processing recipes from root directory: {args.root}")
        generator.load_and_process_recipes(args.root)
        
        # Validate-only mode
        if args.validate_only:
            report = generator.get_generation_report()
            validation = report['validation_results']
            
            logger.info("Validation Results:")
            logger.info(f"  Total recipes: {validation['total_recipes']}")
            logger.info(f"  Properly categorized: {validation['recipes_with_categories']}")
            logger.info(f"  Fallback categorized: {validation['recipes_without_proper_categories']}")
            logger.info(f"  Empty categories: {len(validation['empty_categories'])}")
            
            if validation['validation_warnings']:
                logger.warning("Validation warnings:")
                for warning in validation['validation_warnings']:
                    logger.warning(f"  {warning}")
            
            logger.info("✅ Validation completed")
            return
        
        # Generate report mode
        if args.report:
            logger.info("Generating detailed report...")
            report = generator.get_generation_report()
            
            output_file = args.output or 'generation_report.json'
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(report, f, indent=2, default=str)
            
            logger.info(f"📊 Report generated: {output_file}")
            
            # Also print summary to console
            if not args.quiet:
                print("\n" + "="*50)
                print("GENERATION REPORT SUMMARY")
                print("="*50)
                print(f"Total recipes processed: {report['total_recipes_processed']}")
                print(f"Categories used: {len(report['categories_used'])}")
                print(f"Template: {report['template_used']}")
                print(f"Timestamp: {report['generation_timestamp']}")
                
                validation = report['validation_results']
                print(f"\nValidation:")
                print(f"  Properly categorized: {validation['recipes_with_categories']}")
                print(f"  Fallback categorized: {validation['recipes_without_proper_categories']}")
                print(f"  Empty categories: {len(validation['empty_categories'])}")
                
                if validation['validation_warnings']:
                    print(f"\nWarnings: {len(validation['validation_warnings'])}")
                
                print(f"\n✅ Report saved to: {output_file}")
            
            return
        
        # Generate README
        output_file = args.output
        logger.info(f"Generating README{'to ' + output_file if output_file else ''}...")
        
        content = generator.generate_readme(output_file)
        
        # Get final output path
        final_output = output_file or generator.config.get('output_file', 'README.md')
        
        # Generate summary statistics
        report = generator.get_generation_report()
        
        if not args.quiet:
            print("\n" + "="*50)
            print("README GENERATION COMPLETED")
            print("="*50)
            print(f"📄 Output file: {final_output}")
            print(f"📊 Total recipes: {report['total_recipes_processed']}")
            print(f"📁 Categories: {len(report['categories_used'])}")
            print(f"🎨 Template: {report['template_used']}")
            
            # File size and line count
            if os.path.exists(final_output):
                file_size = os.path.getsize(final_output)
                with open(final_output, 'r', encoding='utf-8') as f:
                    line_count = sum(1 for _ in f)
                print(f"📏 File size: {file_size:,} bytes ({line_count:,} lines)")
            
            validation = report['validation_results']
            if validation['validation_warnings']:
                print(f"⚠️  Warnings: {len(validation['validation_warnings'])}")
            
            print("\n✅ README.md generation successful!")
        
        logger.info("README generation completed successfully")
        
    except KeyboardInterrupt:
        logger.error("Operation cancelled by user")
        sys.exit(130)
    except Exception as e:
        logger.error(f"README generation failed: {e}")
        if args.verbose:
            logger.exception("Full error details:")
        sys.exit(1)


if __name__ == '__main__':
    main()