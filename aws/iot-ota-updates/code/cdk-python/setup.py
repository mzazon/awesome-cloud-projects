"""
Python package setup for IoT Fleet Management CDK Application

This setup.py file defines the package configuration for the CDK Python application
that creates infrastructure for IoT fleet management and over-the-air updates.
"""

from setuptools import setup, find_packages

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python Application for IoT Fleet Management and Over-the-Air Updates
    
    This application creates the necessary AWS infrastructure for managing IoT device fleets
    and deploying firmware updates over-the-air using AWS IoT Core services.
    """

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file"""
    with open(filename, "r", encoding="utf-8") as f:
        return [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]

setup(
    name="iot-fleet-management-cdk",
    version="1.0.0",
    description="AWS CDK Python application for IoT fleet management and OTA updates",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Package discovery
    packages=find_packages(),
    
    # Include package data
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=parse_requirements("requirements.txt"),
    
    # Development dependencies
    extras_require={
        "dev": [
            "mypy>=1.8.0",
            "black>=23.12.0",
            "pylint>=3.0.0",
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "iot",
        "fleet-management",
        "ota-updates",
        "firmware",
        "device-management",
        "cloud-infrastructure",
        "infrastructure-as-code",
    ],
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "iot-fleet-cdk=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
        "Changelog": "https://github.com/aws/aws-cdk/releases",
    },
    
    # Package metadata
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
    
    # Additional metadata
    maintainer="AWS CDK Team",
    maintainer_email="aws-cdk-team@amazon.com",
)