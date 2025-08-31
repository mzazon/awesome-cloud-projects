"""
Setup configuration for Website Monitoring with CloudWatch Synthetics CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.

Author: Recipe Generator v1.3
Last Updated: 2025-07-12
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "Website Monitoring with CloudWatch Synthetics CDK Application"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith("#"):
                # Remove inline comments
                requirement = line.split("#")[0].strip()
                if requirement:
                    install_requires.append(requirement)

setuptools.setup(
    name="website-monitoring-synthetics-cdk",
    version="1.1.0",
    
    author="AWS CDK Recipe Generator",
    author_email="recipes@aws.com",
    description="CDK Python application for Website Monitoring with CloudWatch Synthetics",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/cloud-recipes",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/cloud-recipes/issues",
        "Documentation": "https://github.com/aws-samples/cloud-recipes/blob/main/aws/website-monitoring-synthetics-cloudwatch/",
        "Source Code": "https://github.com/aws-samples/cloud-recipes/tree/main/aws/website-monitoring-synthetics-cloudwatch/code/cdk-python/",
    },
    
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
        "Topic :: Internet :: WWW/HTTP :: Site Management",
        "Typing :: Typed",
    ],
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    python_requires=">=3.8",
    install_requires=install_requires,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "boto3-stubs[essential]>=1.34.0",
            "pytest-cov>=4.1.0",
            "pytest-mock>=3.11.0",
            "coverage>=7.3.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "testing": [
            "moto>=4.2.0",
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "pytest-mock>=3.11.0",
            "coverage>=7.3.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "website-monitoring-cdk=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloudwatch",
        "synthetics",
        "monitoring",
        "website",
        "canary",
        "automation",
        "infrastructure",
        "devops",
    ],
    
    include_package_data=True,
    zip_safe=False,
    
    # CDK-specific metadata
    data_files=[
        (".", ["cdk.json"]),
    ],
    
    # Project metadata for PyPI
    license="MIT",
    platforms=["any"],
    
    # Additional metadata
    maintainer="AWS CDK Recipe Team",
    maintainer_email="cdk-recipes@aws.com",
    
    # Security and quality indicators
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)