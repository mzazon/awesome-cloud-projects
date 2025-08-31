"""
Setup script for Infrastructure Monitoring Quick Setup CDK Application
====================================================================

This setup script configures the Python package for the AWS CDK application
that deploys infrastructure monitoring using Systems Manager and CloudWatch.

Usage:
    pip install -e .              # Install in development mode
    pip install .                 # Install the package
    python setup.py develop       # Alternative development install
    python setup.py sdist         # Create source distribution
"""

from setuptools import setup, find_packages
import os


def read_file(filename: str) -> str:
    """Read the contents of a file."""
    with open(os.path.join(os.path.dirname(__file__), filename), 'r', encoding='utf-8') as f:
        return f.read()


def read_requirements() -> list:
    """Read requirements from requirements.txt file."""
    try:
        requirements = []
        with open('requirements.txt', 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Remove inline comments
                    requirement = line.split('#')[0].strip()
                    if requirement:
                        requirements.append(requirement)
        return requirements
    except FileNotFoundError:
        # Fallback to minimal requirements if file not found
        return [
            "aws-cdk-lib>=2.100.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0"
        ]


# Package metadata
PACKAGE_NAME = "infrastructure-monitoring-cdk"
PACKAGE_VERSION = "1.0.0"
PACKAGE_DESCRIPTION = "AWS CDK application for Infrastructure Monitoring Quick Setup"
PACKAGE_AUTHOR = "AWS CDK Team"
PACKAGE_AUTHOR_EMAIL = "support@example.com"
PACKAGE_URL = "https://github.com/aws-samples/infrastructure-monitoring-cdk"

# Long description from README if available
try:
    LONG_DESCRIPTION = read_file("README.md")
    LONG_DESCRIPTION_CONTENT_TYPE = "text/markdown"
except FileNotFoundError:
    LONG_DESCRIPTION = PACKAGE_DESCRIPTION
    LONG_DESCRIPTION_CONTENT_TYPE = "text/plain"

# Python and CDK version requirements
PYTHON_REQUIRES = ">=3.8"
CDK_VERSION = ">=2.100.0,<3.0.0"

setup(
    # Basic package information
    name=PACKAGE_NAME,
    version=PACKAGE_VERSION,
    description=PACKAGE_DESCRIPTION,
    long_description=LONG_DESCRIPTION,
    long_description_content_type=LONG_DESCRIPTION_CONTENT_TYPE,
    
    # Author information
    author=PACKAGE_AUTHOR,
    author_email=PACKAGE_AUTHOR_EMAIL,
    url=PACKAGE_URL,
    
    # Package discovery and structure
    packages=find_packages(exclude=["tests", "tests.*"]),
    py_modules=["app"],
    
    # Python version requirement
    python_requires=PYTHON_REQUIRES,
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-setuptools>=67.0.0"
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.0.0"
        ]
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
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities"
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "infrastructure", "monitoring", "cloudwatch", 
        "systems-manager", "devops", "observability", "automation"
    ],
    
    # Entry points for command-line tools (optional)
    entry_points={
        "console_scripts": [
            # Uncomment if you want to create CLI commands
            # "infra-mon-deploy=app:main",
        ],
    },
    
    # Package data to include
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.json"]
    },
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs for PyPI
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/infrastructure-monitoring-cdk",
        "Bug Reports": "https://github.com/aws-samples/infrastructure-monitoring-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Systems Manager": "https://aws.amazon.com/systems-manager/",
        "AWS CloudWatch": "https://aws.amazon.com/cloudwatch/"
    }
)