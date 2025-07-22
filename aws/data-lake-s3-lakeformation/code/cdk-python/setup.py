"""
AWS CDK Python Setup Configuration for Data Lake Architecture.

This setup.py file configures the Python package for the CDK application
that implements a comprehensive data lake architecture using S3 and Lake Formation.
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read the README file if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Python application for Data Lake Architecture"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    requirements.append(line)
    
    return requirements

# Package metadata
PACKAGE_NAME = "data-lake-cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK Python application for Data Lake Architecture with S3 and Lake Formation"
AUTHOR = "Data Lake Team"
AUTHOR_EMAIL = "datalake-team@example.com"
URL = "https://github.com/example/data-lake-cdk"
LICENSE = "MIT"

# Python version requirement
PYTHON_REQUIRES = ">=3.8,<4.0"

# Classifiers for PyPI
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Operating System :: OS Independent",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: Database",
    "Topic :: System :: Archiving",
    "Topic :: System :: Systems Administration",
    "Typing :: Typed",
]

# Keywords for PyPI
KEYWORDS = [
    "aws",
    "cdk",
    "data-lake",
    "s3",
    "lake-formation",
    "glue",
    "analytics",
    "governance",
    "security",
    "infrastructure",
    "cloud",
    "python"
]

# Entry points
ENTRY_POINTS = {
    "console_scripts": [
        "data-lake-deploy=app:main",
    ],
}

# Package configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    license=LICENSE,
    packages=find_packages(
        exclude=["tests", "tests.*", "*.tests", "*.tests.*"]
    ),
    include_package_data=True,
    python_requires=PYTHON_REQUIRES,
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "isort>=5.12.0",
            "autopep8>=2.0.0",
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
            "sphinx-autodoc-typehints>=1.24.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "pytest-mock>=3.11.0",
            "moto>=4.2.0",
            "boto3-stubs[essential]",
        ],
    },
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    entry_points=ENTRY_POINTS,
    zip_safe=False,
    project_urls={
        "Documentation": f"{URL}/docs",
        "Source": URL,
        "Tracker": f"{URL}/issues",
    },
)

# Additional package information
__version__ = VERSION
__author__ = AUTHOR
__email__ = AUTHOR_EMAIL
__license__ = LICENSE
__copyright__ = f"Copyright 2024, {AUTHOR}"

# Package metadata accessible at runtime
__all__ = [
    "__version__",
    "__author__",
    "__email__",
    "__license__",
    "__copyright__",
]