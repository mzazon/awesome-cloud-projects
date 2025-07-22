"""
Setup configuration for Aurora DSQL Multi-Region Disaster Recovery CDK Application

This setup.py file defines the package metadata and dependencies for the
Aurora DSQL disaster recovery CDK application, enabling proper packaging
and distribution of the infrastructure code.

Author: AWS CDK Generator
Version: 1.0
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    """Read the README.md file for the long description"""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Aurora DSQL Multi-Region Disaster Recovery CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="aurora-dsql-disaster-recovery-cdk",
    version="1.0.0",
    description="Aurora DSQL Multi-Region Disaster Recovery Infrastructure using AWS CDK",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS DevOps Team",
    author_email="devops@company.com",
    url="https://github.com/company/aws-recipes",
    
    # Package discovery
    packages=find_packages(exclude=["tests*", "docs*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "pytest-mock>=3.12.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.8.0",
            "moto>=4.2.0"
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0"
        ]
    },
    
    # Entry points for CLI scripts
    entry_points={
        "console_scripts": [
            "aurora-dsql-dr-deploy=app:main",
        ],
    },
    
    # Package metadata
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
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Site Management",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "infrastructure",
        "disaster-recovery",
        "aurora-dsql",
        "multi-region",
        "eventbridge",
        "lambda",
        "cloudwatch",
        "monitoring",
        "high-availability"
    ],
    
    # Package data inclusion
    include_package_data=True,
    
    # ZIP safe configuration
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/company/aws-recipes/issues",
        "Source": "https://github.com/company/aws-recipes",
        "Documentation": "https://github.com/company/aws-recipes/tree/main/aws/building-multi-region-disaster-recovery-with-aurora-dsql-and-eventbridge",
    },
    
    # License
    license="MIT",
    
    # Manifest configuration
    package_data={
        "": ["*.txt", "*.md", "*.json", "*.yaml", "*.yml"],
    },
)