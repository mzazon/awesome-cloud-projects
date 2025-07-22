"""
Setup configuration for the Infrastructure Deployment Pipeline CDK application.

This setup.py file defines the package structure, dependencies, and metadata
for the CDK Python application that creates automated infrastructure deployment
pipelines using AWS CDK and CodePipeline.
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read the README file for the long description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Infrastructure Deployment Pipeline CDK Application"

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
PACKAGE_NAME = "infrastructure-deployment-pipeline"
VERSION = "1.0.0"
AUTHOR = "AWS CDK Team"
AUTHOR_EMAIL = "cdk-team@example.com"
DESCRIPTION = "Infrastructure Deployment Pipeline using AWS CDK and CodePipeline"
URL = "https://github.com/aws-samples/infrastructure-deployment-pipeline"

# Classification metadata
CLASSIFIERS = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "Intended Audience :: System Administrators",
    "License :: OSI Approved :: Apache Software License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    "Operating System :: OS Independent",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "infrastructure",
    "deployment",
    "pipeline",
    "codepipeline",
    "codecommit",
    "cloudformation",
    "devops",
    "ci-cd",
    "automation",
    "infrastructure-as-code",
    "cloud",
]

# Setup configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    description=DESCRIPTION,
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    url=URL,
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package classification
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    
    # Entry points
    entry_points={
        "console_scripts": [
            "infrastructure-pipeline=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "isort>=5.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "boto3>=1.26.0",
            "moto>=4.0.0",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": f"{URL}/issues",
        "Source": URL,
        "Documentation": f"{URL}/docs",
        "Homepage": URL,
    },
    
    # License
    license="Apache-2.0",
    
    # Zip safety
    zip_safe=False,
)