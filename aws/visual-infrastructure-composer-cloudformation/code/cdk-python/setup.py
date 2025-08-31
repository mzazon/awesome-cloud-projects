"""
Setup configuration for Visual Infrastructure Design CDK Python application.

This setup.py file configures the Python package for the CDK application that
demonstrates visual infrastructure design patterns using AWS Application Composer
and CloudFormation integration.
"""

import setuptools
from pathlib import Path

# Read the contents of README file for long description
this_directory = Path(__file__).parent
readme_path = this_directory / "README.md"

long_description = """
# Visual Infrastructure Design with Application Composer and CloudFormation - CDK Python

This CDK Python application demonstrates how to create infrastructure that mirrors
the visual design patterns available in AWS Application Composer. The application
creates a static website hosting solution using S3 with proper security configurations
and website hosting capabilities.

## Features

- S3 bucket configured for static website hosting
- Public access policy for website content
- Proper CORS configuration for web applications
- CloudFormation outputs for easy integration
- Comprehensive resource tagging
- Security best practices implementation

## Architecture

The application creates a simple but complete static website hosting infrastructure:
- S3 bucket with website configuration
- Bucket policy allowing public read access
- Index and error document configuration
- CORS rules for browser compatibility

## Usage

1. Install dependencies: `pip install -r requirements.txt`
2. Configure AWS credentials and region
3. Deploy: `cdk deploy`
4. Upload website content to the created S3 bucket
5. Access your website via the provided URL

## Cleanup

Run `cdk destroy` to remove all created resources.
"""

if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

setuptools.setup(
    name="visual-infrastructure-composer-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS Recipes Contributors",
    author_email="recipes@aws.example.com",
    description="CDK Python application for Visual Infrastructure Design with Application Composer",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # URLs
    url="https://github.com/aws-samples/recipes",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/recipes/issues",
        "Documentation": "https://github.com/aws-samples/recipes/tree/main/aws/visual-infrastructure-composer-cloudformation",
        "Source Code": "https://github.com/aws-samples/recipes/tree/main/aws/visual-infrastructure-composer-cloudformation/code/cdk-python",
    },
    
    # Package discovery
    packages=setuptools.find_packages(),
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "visual-infrastructure-composer=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: Software Development :: Code Generators",
        "Framework :: AWS CDK",
        "Typing :: Typed",
    ],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.160.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "python-dotenv>=1.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.3.0",
            "bandit>=1.7.5",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "typing": [
            "boto3-stubs[essential]>=1.26.0",
            "types-requests>=2.31.0",
        ]
    },
    
    # Package data
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "infrastructure-as-code",
        "static-website",
        "s3",
        "visual-design",
        "application-composer",
        "devops",
        "cloud",
    ],
    
    # Additional metadata
    platforms=["any"],
    license="MIT",
    
    # CDK-specific metadata
    cdkVersion="2.167.1",
    
    # Custom metadata for the recipe system
    options={
        "recipe_metadata": {
            "recipe_id": "a7f3d9c2",
            "recipe_title": "Visual Infrastructure Design with Application Composer and CloudFormation",
            "recipe_category": "devops",
            "recipe_difficulty": 100,
            "recipe_services": ["Application Composer", "CloudFormation", "S3"],
            "recipe_version": "1.1",
            "iac_tool": "CDK-Python",
            "iac_version": "1.0.0",
        }
    }
)