"""
Setup script for Aurora Database Migration CDK Python application.

This package provides Infrastructure as Code (IaC) for migrating on-premises 
databases to Amazon Aurora with minimal downtime using AWS DMS.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else __doc__

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
requirements = []
if requirements_path.exists():
    requirements = [
        line.strip()
        for line in requirements_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="aurora-migration-cdk",
    version="1.0.0",
    description="CDK Python application for Aurora database migration with minimal downtime",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Cloud Solutions",
    author_email="solutions@amazon.com",
    url="https://github.com/aws-samples/aurora-migration-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/dms/",
        "Source": "https://github.com/aws-samples/aurora-migration-cdk",
        "Bug Reports": "https://github.com/aws-samples/aurora-migration-cdk/issues",
    },
    packages=setuptools.find_packages(where="."),
    package_dir={"": "."},
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Database",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    python_requires=">=3.9",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "black>=24.0.0",
            "mypy>=1.11.0",
            "flake8>=7.0.0",
            "pre-commit>=3.5.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "aurora-migration-deploy=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "aurora",
        "database",
        "migration",
        "dms",
        "infrastructure",
        "cloud",
        "minimal-downtime",
    ],
    include_package_data=True,
    zip_safe=False,
)