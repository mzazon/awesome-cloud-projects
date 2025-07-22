"""
Setup script for Serverless API Patterns with Lambda Authorizers CDK Application

This setup script configures the Python package for the CDK application that
demonstrates serverless API security patterns using AWS API Gateway with
custom Lambda authorizers.

Usage:
    pip install -e .              # Install in development mode
    python setup.py build         # Build the package
    python setup.py test          # Run tests
    python setup.py sdist         # Create source distribution
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read README.md file for package description."""
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return "Serverless API Patterns with Lambda Authorizers CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements.txt file for dependencies."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            return [line.strip() for line in fh if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.160.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0"
        ]

# Package metadata
PACKAGE_NAME = "serverless-api-patterns-cdk"
VERSION = "1.0.0"
DESCRIPTION = "CDK application for serverless API patterns with Lambda authorizers"
AUTHOR = "AWS CDK Generator"
AUTHOR_EMAIL = "developer@example.com"
URL = "https://github.com/aws-samples/serverless-api-patterns"
LICENSE = "MIT"

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Package classifiers for PyPI
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
    "Environment :: Console",
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
    "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
    "Topic :: Security",
    "Topic :: Software Development :: Libraries :: Application Frameworks",
    "Topic :: System :: Systems Administration",
    "Framework :: AWS CDK",
    "Framework :: AWS CDK :: 2",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "api-gateway",
    "lambda",
    "authorizers",
    "serverless",
    "security",
    "authentication",
    "authorization",
    "infrastructure-as-code",
    "cloud",
    "microservices"
]

# Additional project URLs
PROJECT_URLS = {
    "Documentation": "https://docs.aws.amazon.com/cdk/",
    "Source": "https://github.com/aws-samples/serverless-api-patterns",
    "Bug Reports": "https://github.com/aws-samples/serverless-api-patterns/issues",
    "AWS CDK": "https://aws.amazon.com/cdk/",
    "API Gateway": "https://aws.amazon.com/api-gateway/",
    "AWS Lambda": "https://aws.amazon.com/lambda/",
}

# Development dependencies for testing and code quality
DEV_DEPENDENCIES = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "black>=23.0.0",
    "flake8>=6.0.0",
    "mypy>=1.0.0",
    "isort>=5.12.0",
    "bandit>=1.7.0",
    "safety>=3.0.0",
]

# Documentation dependencies
DOC_DEPENDENCIES = [
    "sphinx>=7.0.0",
    "sphinx-rtd-theme>=2.0.0",
    "myst-parser>=2.0.0",
]

# Optional dependencies for enhanced functionality
EXTRA_DEPENDENCIES = {
    "dev": DEV_DEPENDENCIES,
    "docs": DOC_DEPENDENCIES,
    "all": DEV_DEPENDENCIES + DOC_DEPENDENCIES,
}

# Entry points for command-line tools
ENTRY_POINTS = {
    "console_scripts": [
        "cdk-serverless-api=app:main",
    ],
}

setup(
    # Basic package information
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author and contact information
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    project_urls=PROJECT_URLS,
    
    # License and legal information
    license=LICENSE,
    
    # Package discovery and structure
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirements
    python_requires=PYTHON_REQUIRES,
    
    # Dependencies
    install_requires=read_requirements(),
    extras_require=EXTRA_DEPENDENCIES,
    
    # Package metadata for PyPI
    classifiers=CLASSIFIERS,
    keywords=KEYWORDS,
    
    # Entry points for command-line tools
    entry_points=ENTRY_POINTS,
    
    # Additional package data
    package_data={
        "": [
            "README.md",
            "LICENSE",
            "requirements.txt",
            "cdk.json",
            "*.yaml",
            "*.yml",
            "*.json",
            "*.md",
        ],
    },
    
    # Exclude certain files from the package
    exclude_package_data={
        "": [
            "*.pyc",
            "__pycache__",
            "*.pyo",
            "*.pyd",
            ".DS_Store",
            "*.so",
            ".git*",
            ".pytest_cache",
            ".mypy_cache",
            ".coverage",
            "htmlcov",
            "build",
            "dist",
            "*.egg-info",
        ],
    },
    
    # ZIP safe configuration
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
    
    # Test suite configuration
    test_suite="tests",
    tests_require=DEV_DEPENDENCIES,
    
    # Command options for setup.py commands
    options={
        "build_py": {
            "compile": True,
            "optimize": 2,
        },
        "bdist_wheel": {
            "universal": False,
        },
        "egg_info": {
            "tag_build": "",
            "tag_date": False,
        },
    },
)

# Additional setup configuration for development
if __name__ == "__main__":
    print(f"Setting up {PACKAGE_NAME} v{VERSION}")
    print(f"Python requirement: {PYTHON_REQUIRES}")
    print(f"Description: {DESCRIPTION}")
    print(f"Author: {AUTHOR}")
    print(f"License: {LICENSE}")
    print("=" * 60)
    
    # Check if running in development mode
    import sys
    if "develop" in sys.argv or "-e" in sys.argv:
        print("Installing in development mode...")
        print("This will create a symlink to the source code.")
        print("Changes to the source code will be immediately available.")
    
    if "test" in sys.argv:
        print("Running test suite...")
        print("Make sure all dependencies are installed:")
        print("pip install -e .[dev]")
    
    if "clean" in sys.argv:
        print("Cleaning build artifacts...")
        import shutil
        import glob
        
        # Clean common build artifacts
        artifacts = [
            "build",
            "dist", 
            "*.egg-info",
            "__pycache__",
            ".pytest_cache",
            ".mypy_cache",
            ".coverage",
            "htmlcov",
        ]
        
        for pattern in artifacts:
            for path in glob.glob(pattern):
                if os.path.isdir(path):
                    shutil.rmtree(path)
                    print(f"Removed directory: {path}")
                elif os.path.isfile(path):
                    os.remove(path)
                    print(f"Removed file: {path}")