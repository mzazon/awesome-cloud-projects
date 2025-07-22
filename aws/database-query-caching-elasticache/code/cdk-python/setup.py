"""
Setup configuration for Database Query Caching with ElastiCache CDK Application

This setup.py file configures the Python package for the CDK application that
implements database query caching using Amazon ElastiCache Redis, RDS MySQL,
and supporting AWS infrastructure services.

The package follows Python packaging best practices and includes all necessary
metadata for distribution and dependency management.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "CDK Python application for Database Query Caching with ElastiCache"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
requirements = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith("#"):
                # Remove inline comments and version specifiers for basic deps
                requirement = line.split("#")[0].strip()
                if requirement:
                    requirements.append(requirement)

setuptools.setup(
    name="database-query-caching-elasticache",
    version="1.0.0",
    
    author="AWS CDK Generator",
    author_email="engineering@example.com",
    
    description="CDK Python application for database query caching with ElastiCache Redis",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/example/database-caching-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/example/database-caching-cdk/issues",
        "Documentation": "https://github.com/example/database-caching-cdk/wiki",
        "Source Code": "https://github.com/example/database-caching-cdk",
    },
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Database :: Database Engines/Servers",
    ],
    
    # Package configuration
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=requirements,
    
    # Extra dependencies for different use cases
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
    },
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "database-caching-deploy=app:main",
        ],
    },
    
    # Include additional files in the package
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "elasticache",
        "redis",
        "database",
        "caching",
        "rds",
        "mysql",
        "performance",
        "optimization",
        "infrastructure",
        "cloud",
    ],
    
    # Licensing
    license="Apache License 2.0",
    
    # Metadata
    zip_safe=False,
)