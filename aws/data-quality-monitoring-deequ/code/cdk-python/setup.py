"""
Setup script for Data Quality Monitoring with Deequ on EMR - CDK Python Application

This setup script configures the Python package for the CDK application that deploys
a comprehensive data quality monitoring solution using Amazon Deequ on EMR.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_file = this_directory / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, 'r') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Remove inline comments
                    if '#' in line:
                        line = line.split('#')[0].strip()
                    requirements.append(line)
            return requirements
    return []

setuptools.setup(
    name="data-quality-monitoring-deequ-emr",
    version="1.0.0",
    
    description="CDK Python application for real-time data quality monitoring with Deequ on EMR",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture Team",
    author_email="aws-solutions@amazon.com",
    
    url="https://github.com/aws-samples/data-quality-monitoring-deequ-emr",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=read_requirements(),
    
    python_requires=">=3.8",
    
    classifiers=[
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "emr",
        "deequ",
        "data-quality",
        "spark",
        "analytics",
        "monitoring",
        "cloudwatch",
        "sns"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/data-quality-monitoring-deequ-emr",
        "Tracker": "https://github.com/aws-samples/data-quality-monitoring-deequ-emr/issues",
    },
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
            "myst-parser>=1.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "deploy-data-quality-monitoring=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # CDK specific configuration
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
    
    zip_safe=False,
)