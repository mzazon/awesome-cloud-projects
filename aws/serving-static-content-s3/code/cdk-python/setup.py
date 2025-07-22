"""
Setup configuration for AWS CDK Python Static Website Application.

This setup.py file configures the Python package for the static website
hosting CDK application. It defines package metadata, dependencies,
and installation requirements.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = this_directory / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Extract just the package name and version constraint
                    if ">=" in line and "<" in line:
                        requirements.append(line.split()[0])
                    elif line and not line.startswith("-"):
                        requirements.append(line)
            return requirements
    return []

setuptools.setup(
    name="static-website-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for static website hosting with S3 and CloudFront",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Recipe Generator",
    author_email="noreply@example.com",
    
    license="MIT",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
    ],
    
    keywords="aws cdk cloudformation s3 cloudfront static website hosting",
    
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    python_requires=">=3.8",
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
            "mypy>=1.7.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "deploy-static-website=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    include_package_data=True,
    
    zip_safe=False,
    
    # CDK-specific metadata
    cdk_version=">=2.120.0",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)