#!/usr/bin/env python3
"""
Setup configuration for Business Process Automation CDK Python Application.

This setup.py file configures the Python package for the business process
automation solution using Amazon Bedrock Agents and EventBridge.
"""

from setuptools import setup, find_packages
import pathlib

# Read the README file for the long description
here = pathlib.Path(__file__).parent.resolve()
long_description = (here / "README.md").read_text(encoding="utf-8") if (here / "README.md").exists() else ""

# Package metadata
PACKAGE_NAME = "business-process-automation-cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK Python application for intelligent business process automation with Bedrock Agents and EventBridge"
AUTHOR = "AWS Solutions Team"
AUTHOR_EMAIL = "aws-solutions@amazon.com"
LICENSE = "Apache License 2.0"

# Read requirements from requirements.txt
def get_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = here / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    return []

# Define package setup
setup(
    # Basic package information
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=long_description,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    license=LICENSE,
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_dir={"": "."},
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=get_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "mypy>=1.8.0",
            "pre-commit>=3.6.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=3.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=2.0.0",
            "sphinx-autodoc-typehints>=1.25.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-automation=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
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
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "bedrock", "eventbridge", "lambda", "s3",
        "business-automation", "document-processing", "ai", "serverless",
        "workflow", "event-driven", "artificial-intelligence"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/",
        "Bug Reports": "https://github.com/aws-samples/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon Bedrock": "https://aws.amazon.com/bedrock/",
        "Amazon EventBridge": "https://aws.amazon.com/eventbridge/",
    },
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
    
    # Package data files
    package_data={
        "": [
            "*.json",
            "*.yaml", 
            "*.yml",
            "*.md",
            "*.txt",
            "schemas/*",
        ],
    },
    
    # Data files to include in distribution
    data_files=[
        ("schemas", ["schemas/action-schema.json"]) if pathlib.Path("schemas/action-schema.json").exists() else ("", []),
    ],
)

# Additional setup for CDK-specific configurations
def setup_cdk_environment():
    """
    Setup CDK-specific environment and configurations.
    
    This function can be called to ensure proper CDK environment setup
    including bootstrapping and configuration validation.
    """
    import os
    import subprocess
    import sys
    
    # Check if CDK is installed
    try:
        subprocess.run(["cdk", "--version"], check=True, capture_output=True)
        print("✅ AWS CDK is installed and available")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ AWS CDK is not installed. Please install it using: npm install -g aws-cdk")
        sys.exit(1)
    
    # Check AWS credentials
    try:
        subprocess.run(["aws", "sts", "get-caller-identity"], check=True, capture_output=True)
        print("✅ AWS credentials are configured")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ AWS credentials not configured. Please run: aws configure")
        sys.exit(1)
    
    # Set default CDK environment if not set
    if not os.environ.get("CDK_DEFAULT_ACCOUNT"):
        try:
            result = subprocess.run(
                ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"],
                check=True, capture_output=True, text=True
            )
            os.environ["CDK_DEFAULT_ACCOUNT"] = result.stdout.strip()
            print(f"✅ Set CDK_DEFAULT_ACCOUNT to {os.environ['CDK_DEFAULT_ACCOUNT']}")
        except subprocess.CalledProcessError:
            print("⚠️  Could not determine AWS account ID")
    
    if not os.environ.get("CDK_DEFAULT_REGION"):
        try:
            result = subprocess.run(
                ["aws", "configure", "get", "region"],
                check=True, capture_output=True, text=True
            )
            region = result.stdout.strip()
            if region:
                os.environ["CDK_DEFAULT_REGION"] = region
                print(f"✅ Set CDK_DEFAULT_REGION to {region}")
            else:
                os.environ["CDK_DEFAULT_REGION"] = "us-east-1"
                print("⚠️  No default region configured, using us-east-1")
        except subprocess.CalledProcessError:
            os.environ["CDK_DEFAULT_REGION"] = "us-east-1"
            print("⚠️  Could not determine default region, using us-east-1")

if __name__ == "__main__":
    print("Setting up Business Process Automation CDK Application...")
    setup_cdk_environment()
    print("✅ Setup complete! You can now run: cdk deploy")