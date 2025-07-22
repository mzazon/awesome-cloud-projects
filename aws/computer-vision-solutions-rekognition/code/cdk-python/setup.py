"""
Setup configuration for Computer Vision Solutions with Amazon Rekognition CDK Python application

This setup.py file defines the package configuration and dependencies for the
CDK Python application that deploys computer vision infrastructure using
Amazon Rekognition, S3, DynamoDB, Lambda, and API Gateway.

Package Structure:
- Main CDK application in app.py
- Infrastructure stacks and constructs
- Lambda function code embedded in CDK
- Comprehensive testing and validation

Usage:
    pip install -e .          # Install in development mode
    python setup.py build     # Build the package
    python setup.py test      # Run tests
"""

from setuptools import setup, find_packages
import os

# Read version from environment or use default
VERSION = os.environ.get("PACKAGE_VERSION", "1.0.0")

# Read the README file for long description
def read_readme():
    """Read README file for package description"""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Computer Vision Solutions with Amazon Rekognition - CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
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

# Define package metadata
setup(
    # Basic package information
    name="computer-vision-rekognition-cdk",
    version=VERSION,
    description="CDK Python application for deploying computer vision solutions with Amazon Rekognition",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author and project information
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package classification
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
        "Topic :: Software Development :: Code Generators",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    # Package discovery and dependencies
    packages=find_packages(exclude=["tests*", "docs*"]),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    
    # Optional dependencies for different use cases
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "pytest-mock>=3.10.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinx-autodoc-typehints>=1.19.0",
        ],
        "security": [
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "cdk-cv-deploy=app:main",
        ],
    },
    
    # Package data and resources
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yaml",
            "*.yml",
            "*.json",
        ],
    },
    
    # Additional metadata
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "computer-vision",
        "rekognition",
        "machine-learning",
        "ai",
        "image-analysis",
        "face-detection",
        "object-recognition",
        "text-extraction",
        "content-moderation",
    ],
    
    # Licensing
    license="Apache-2.0",
    
    # Platform support
    platforms=["any"],
    
    # Zip safety
    zip_safe=False,
    
    # Test configuration
    test_suite="tests",
    
    # Setup requirements (needed during setup)
    setup_requires=[
        "wheel>=0.37.0",
        "setuptools>=65.0.0",
    ],
    
    # Development status
    options={
        "build": {
            "build_base": "build",
        },
        "bdist_wheel": {
            "universal": False,
        },
    },
)