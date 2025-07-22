"""
Setup configuration for Live Event Broadcasting CDK Python application.

This setup.py file defines the package configuration for the CDK Python
application that deploys live event broadcasting infrastructure using
AWS Elemental MediaConnect, MediaLive, and MediaPackage.
"""

from setuptools import setup, find_packages

# Read the contents of README file
from pathlib import Path
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

setup(
    name="live-event-broadcasting-cdk",
    version="1.0.0",
    description="CDK Python application for live event broadcasting with AWS Elemental MediaConnect",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.164.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "pyyaml>=6.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "live-event-broadcasting=app:main",
        ],
    },
    
    # Package metadata
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Multimedia :: Video :: Conversion",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "mediaconnect",
        "medialive",
        "mediapackage",
        "live-streaming",
        "broadcasting",
        "video",
        "hls",
        "rtmp",
        "redundancy",
        "failover",
    ],
    
    # Package data
    package_data={
        "": ["*.yaml", "*.yml", "*.json", "*.md"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
)