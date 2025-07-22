"""
Setup configuration for Amazon Q Developer Infrastructure Code Generation CDK Python application.

This setup.py file configures the Python package for the CDK application that creates
infrastructure for automated template processing using Amazon Q Developer and AWS
Infrastructure Composer.
"""

from setuptools import setup, find_packages

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for Amazon Q Developer Infrastructure Code Generation"

# Package metadata
PACKAGE_NAME = "q-developer-infrastructure-cdk"
VERSION = "1.0.0"
AUTHOR = "AWS Recipe Developer"
AUTHOR_EMAIL = "developer@example.com"
DESCRIPTION = "CDK Python application for Amazon Q Developer Infrastructure Code Generation"
REPOSITORY_URL = "https://github.com/aws-samples/recipes"

# Define dependencies
INSTALL_REQUIRES = [
    "aws-cdk-lib==2.164.1",
    "constructs>=10.0.0,<11.0.0",
    "boto3>=1.34.0",
    "jsonschema>=4.17.0",
]

# Development dependencies
EXTRAS_REQUIRE = {
    "dev": [
        "mypy>=1.5.1",
        "types-boto3>=1.0.2",
        "pytest>=7.4.0",
        "pytest-cov>=4.1.0",
        "moto>=4.2.0",
        "black>=23.7.0",
        "flake8>=6.0.0",
        "isort>=5.12.0",
        "sphinx>=7.1.0",
        "sphinx-rtd-theme>=1.3.0",
        "aws-cdk>=2.164.1",
        "cfn-lint>=0.83.0",
    ],
    "test": [
        "pytest>=7.4.0",
        "pytest-cov>=4.1.0",
        "moto>=4.2.0",
        "coverage>=7.2.0",
    ],
    "docs": [
        "sphinx>=7.1.0",
        "sphinx-rtd-theme>=1.3.0",
        "sphinx-autodoc-typehints>=1.23.0",
    ]
}

# Python version requirements
PYTHON_REQUIRES = ">=3.8"

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
    "Topic :: System :: Systems Administration",
    "Topic :: Utilities",
]

# Entry points for CLI commands
ENTRY_POINTS = {
    "console_scripts": [
        "q-developer-cdk=app:main",
    ],
}

setup(
    name=PACKAGE_NAME,
    version=VERSION,
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    description=DESCRIPTION,
    long_description=long_description,
    long_description_content_type="text/markdown",
    url=REPOSITORY_URL,
    project_urls={
        "Bug Reports": f"{REPOSITORY_URL}/issues",
        "Source": REPOSITORY_URL,
        "Documentation": f"{REPOSITORY_URL}/wiki",
    },
    packages=find_packages(exclude=["tests", "tests.*", "docs", "docs.*"]),
    classifiers=CLASSIFIERS,
    python_requires=PYTHON_REQUIRES,
    install_requires=INSTALL_REQUIRES,
    extras_require=EXTRAS_REQUIRE,
    entry_points=ENTRY_POINTS,
    include_package_data=True,
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "amazon-q-developer",
        "infrastructure-composer",
        "lambda",
        "s3",
        "cloudformation",
        "infrastructure-as-code",
        "automation",
        "serverless",
    ],
    # Package configuration
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    # Additional metadata for modern Python packaging
    options={
        "egg_info": {
            "tag_build": "",
            "tag_date": 0,
        }
    },
)