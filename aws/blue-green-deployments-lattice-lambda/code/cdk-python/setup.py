"""
Setup configuration for Blue-Green Deployments with VPC Lattice CDK application.

This package provides Infrastructure as Code (IaC) using AWS CDK Python
for implementing blue-green deployments with VPC Lattice and Lambda.
"""

import os
from setuptools import setup, find_packages


def read_requirements(filename: str) -> list:
    """Read requirements from a file and return as a list."""
    requirements_path = os.path.join(os.path.dirname(__file__), filename)
    with open(requirements_path, 'r', encoding='utf-8') as f:
        return [
            line.strip()
            for line in f
            if line.strip() and not line.startswith('#')
        ]


def read_file(filename: str) -> str:
    """Read the contents of a file."""
    file_path = os.path.join(os.path.dirname(__file__), filename)
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return ""


# Package metadata
PACKAGE_NAME = "blue-green-lattice-cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK Python application for Blue-Green Deployments with VPC Lattice"
LONG_DESCRIPTION = read_file("README.md") or DESCRIPTION

# Author information
AUTHOR = "AWS CDK Recipe Generator"
AUTHOR_EMAIL = "recipes@example.com"

# URLs
PROJECT_URL = "https://github.com/aws-samples/aws-cdk-examples"
DOCUMENTATION_URL = "https://docs.aws.amazon.com/cdk/"

# Classifiers for PyPI
CLASSIFIERS = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Operating System :: OS Independent",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Programming Language :: JavaScript",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Internet :: WWW/HTTP",
    "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    "Typing :: Typed",
]

# Keywords for better discoverability
KEYWORDS = [
    "aws",
    "cdk",
    "aws-cdk",
    "blue-green",
    "deployment",
    "vpc-lattice",
    "lambda",
    "serverless",
    "infrastructure",
    "iac",
    "cloudformation",
    "canary",
    "traffic-shifting",
    "microservices",
    "networking",
]

setup(
    name=PACKAGE_NAME,
    version=VERSION,
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    description=DESCRIPTION,
    long_description=LONG_DESCRIPTION,
    long_description_content_type="text/markdown",
    url=PROJECT_URL,
    project_urls={
        "Documentation": DOCUMENTATION_URL,
        "Source": PROJECT_URL,
        "Bug Reports": f"{PROJECT_URL}/issues",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests*", "docs*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.9",
    
    # Dependencies
    install_requires=read_requirements("requirements.txt"),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "mypy>=1.8.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
        "testing": [
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "moto>=5.0.0",
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "blue-green-deploy=app:BlueGreenDeploymentApp",
        ],
    },
    
    # Package classification
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    
    # License
    license="MIT",
    
    # Platform compatibility
    platforms=["any"],
    
    # Package data
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # CDK-specific configuration
    options={
        "build_py": {
            "exclude_dirs": [
                "cdk.out",
                "node_modules", 
                ".pytest_cache",
                "__pycache__",
                "*.egg-info",
            ]
        }
    },
)