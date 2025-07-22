"""
Setup configuration for the Oracle to PostgreSQL Database Migration CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and package information.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "AWS CDK application for Oracle to PostgreSQL database migration using DMS and Aurora PostgreSQL"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.117.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
    ]

setuptools.setup(
    name="database-migration-oracle-postgresql",
    version="1.0.0",
    
    # Package metadata
    author="Migration Team",
    author_email="migration-team@example.com",
    description="AWS CDK application for Oracle to PostgreSQL database migration",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/database-migration-oracle-postgresql",
    
    # Package discovery
    packages=setuptools.find_packages(),
    
    # Dependencies
    install_requires=requirements,
    
    # Python version compatibility
    python_requires=">=3.8",
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Database",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    
    # Keywords for discovery
    keywords=[
        "aws",
        "cdk",
        "database",
        "migration",
        "oracle",
        "postgresql",
        "dms",
        "aurora",
        "cloud",
        "infrastructure",
    ],
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "migrate-db=app:main",
        ],
    },
    
    # Package data
    include_package_data=True,
    
    # Zip safety
    zip_safe=False,
    
    # Additional options
    project_urls={
        "Bug Reports": "https://github.com/your-org/database-migration-oracle-postgresql/issues",
        "Source": "https://github.com/your-org/database-migration-oracle-postgresql",
        "Documentation": "https://github.com/your-org/database-migration-oracle-postgresql/blob/main/README.md",
    },
)