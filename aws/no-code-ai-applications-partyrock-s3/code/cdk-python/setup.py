"""
Setup configuration for PartyRock S3 CDK Python application.

This setup.py file defines the package configuration for the CDK Python application
that creates infrastructure for hosting PartyRock AI applications using Amazon S3
and CloudFront. It includes all necessary dependencies and metadata.

The application creates:
- S3 bucket with static website hosting
- CloudFront distribution for global content delivery
- Proper security configurations and HTTPS enforcement
- Sample HTML content showcasing PartyRock integration

Author: AWS Recipes CDK Generator
Version: 1.0
License: MIT
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "CDK Python application for hosting PartyRock AI applications with S3 and CloudFront"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith("#"):
                # Remove inline comments and version constraints for setup.py
                package = line.split("#")[0].strip()
                if package:
                    install_requires.append(package)

setuptools.setup(
    # Package metadata
    name="partyrock-s3-cdk",
    version="1.0.0",
    author="AWS Recipes CDK Generator",
    author_email="aws-recipes@example.com",
    description="CDK Python application for hosting PartyRock AI applications",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/recipes",
    
    # Package configuration
    packages=setuptools.find_packages(),
    py_modules=["app"],
    
    # Dependencies
    install_requires=install_requires,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package classifiers for PyPI (if publishing)
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Framework :: AWS CDK",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    
    # Keywords for searchability
    keywords=[
        "aws", "cdk", "cloud", "infrastructure", "s3", "cloudfront", 
        "static-website", "partyrock", "ai", "artificial-intelligence",
        "no-code", "generative-ai", "bedrock", "hosting", "cdn"
    ],
    
    # Additional metadata
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/recipes",
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "AWS PartyRock": "https://partyrock.aws/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # Entry points for console scripts (if needed)
    entry_points={
        "console_scripts": [
            # "partyrock-deploy=app:main",  # Uncomment if adding CLI functionality
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    
    # Specify additional files to include
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Exclude development and test files from the package
    exclude_package_data={
        "": ["*.pyc", "__pycache__", "*.pyo", "*.pyd", ".git*", "test_*", "*_test.py"],
    },
    
    # Zip safety (CDK applications should be zip safe)
    zip_safe=True,
    
    # Additional options for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
)