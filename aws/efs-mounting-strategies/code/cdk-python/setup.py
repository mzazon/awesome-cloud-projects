"""
Setup configuration for EFS Mounting Strategies CDK Python application.

This setup.py file configures the Python package for the CDK application
demonstrating comprehensive EFS mounting strategies including multi-AZ
deployment, access points, and security configurations.
"""

from setuptools import setup, find_packages
import os

# Read the README file for the long description
def read_readme():
    """Read and return the contents of the README file."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "CDK Python application for EFS mounting strategies demonstration"

# Read requirements from requirements.txt
def read_requirements():
    """Read and return the requirements from requirements.txt."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="efs-mounting-strategies-cdk",
    version="1.0.0",
    description="CDK Python application demonstrating EFS mounting strategies",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS Solutions Architecture",
    author_email="solutions@aws.amazon.com",
    url="https://github.com/aws-samples/efs-mounting-strategies-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=22.0.0,<24.0.0",
            "flake8>=4.0.0,<7.0.0",
            "mypy>=0.991,<2.0.0",
            "types-requests>=2.28.0,<3.0.0",
        ],
        "docs": [
            "sphinx>=4.0.0,<8.0.0",
            "sphinx-rtd-theme>=1.0.0,<2.0.0",
        ],
    },
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "efs-cdk=app:main",
        ],
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
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Office/Business :: Financial",
        "Topic :: Scientific/Engineering :: Information Analysis",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "efs",
        "elastic-file-system",
        "nfs",
        "mount",
        "storage",
        "multi-az",
        "access-points",
        "security",
        "infrastructure",
        "cloud",
        "devops",
        "automation",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/efs/",
        "Source": "https://github.com/aws-samples/efs-mounting-strategies-cdk",
        "Bug Reports": "https://github.com/aws-samples/efs-mounting-strategies-cdk/issues",
        "AWS EFS": "https://aws.amazon.com/efs/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # License
    license="MIT",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
)