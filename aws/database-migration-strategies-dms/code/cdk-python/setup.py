"""
Setup script for AWS CDK Python application for Database Migration with DMS.

This setup.py file defines the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

import setuptools
from pathlib import Path

# Read the requirements from requirements.txt
def get_requirements():
    """Load requirements from requirements.txt file."""
    requirements_path = Path(__file__).parent / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, 'r', encoding='utf-8') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    requirements.append(line)
            return requirements
    return []

# Read the long description from README if it exists
def get_long_description():
    """Load long description from README file."""
    readme_path = Path(__file__).parent / "README.md"
    if readme_path.exists():
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "AWS CDK Python application for Database Migration with DMS"

setuptools.setup(
    name="database-migration-dms-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Database Migration Service (DMS) infrastructure",
    long_description=get_long_description(),
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    
    # Package configuration
    packages=setuptools.find_packages(),
    package_dir={"": "."},
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=get_requirements(),
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: JavaScript",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Topic :: Database",
        "Topic :: System :: Archiving :: Mirroring",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "database",
        "migration",
        "dms",
        "replication",
        "cdc",
        "change-data-capture",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS DMS Documentation": "https://docs.aws.amazon.com/dms/",
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "cdk-dms-deploy=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Development dependencies (extras)
    extras_require={
        "dev": [
            "pytest>=7.2.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "cdk-nag>=2.27.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
            "myst-parser>=0.18.0",
        ],
        "test": [
            "pytest>=7.2.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.26.0",
        ],
    },
    
    # Zip safe configuration
    zip_safe=False,
    
    # License information
    license="Apache-2.0",
    
    # Platform support
    platforms=["any"],
)