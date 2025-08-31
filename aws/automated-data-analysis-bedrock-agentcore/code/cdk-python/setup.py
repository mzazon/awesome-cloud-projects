"""
Setup configuration for Automated Data Analysis CDK Python Application

This setup.py file configures the Python package for the CDK application that
deploys automated data analysis infrastructure using AWS Bedrock AgentCore Runtime.

The package includes all necessary dependencies and configuration for deploying
a complete serverless data analysis pipeline.
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    """Read README.md file for package description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "CDK Python application for automated data analysis with Bedrock AgentCore Runtime"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements.txt file for dependencies."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith("#")
            ]
    return []

# Package metadata
PACKAGE_NAME = "automated-data-analysis-cdk"
VERSION = "1.0.0"
DESCRIPTION = "CDK Python application for automated data analysis with AWS Bedrock AgentCore Runtime"
AUTHOR = "AWS CDK Generator"
AUTHOR_EMAIL = "cdk-generator@example.com"
URL = "https://github.com/aws-samples/automated-data-analysis-bedrock-agentcore"
LICENSE = "MIT"

# Classifiers for PyPI
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
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
    "Topic :: Scientific/Engineering :: Artificial Intelligence",
    "Topic :: Office/Business :: Financial :: Spreadsheet",
    "Framework :: AWS CDK",
    "Typing :: Typed",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "bedrock",
    "agentcore",
    "data-analysis",
    "serverless",
    "lambda",
    "s3",
    "cloudwatch",
    "automation",
    "ai",
    "machine-learning",
    "infrastructure-as-code",
    "cloud-formation",
    "python"
]

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Entry points for command-line scripts
ENTRY_POINTS = {
    "console_scripts": [
        "deploy-data-analysis=app:main",
    ],
}

# Additional package data
PACKAGE_DATA = {
    PACKAGE_NAME: [
        "*.json",
        "*.yaml",
        "*.yml",
        "*.md",
        "templates/*.json",
        "templates/*.yaml",
    ],
}

# Setup configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    license=LICENSE,
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    python_requires=PYTHON_REQUIRES,
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_data=PACKAGE_DATA,
    include_package_data=True,
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.9.0",
            "flake8>=6.1.0",
            "mypy>=1.7.0",
            "isort>=5.12.0",
            "autoflake>=2.2.0",
            "bandit>=1.7.5",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "aws-cdk.assertions>=2.120.0",
        ],
    },
    
    # Entry points
    entry_points=ENTRY_POINTS,
    
    # Project URLs
    project_urls={
        "Documentation": f"{URL}/blob/main/README.md",
        "Source Code": URL,
        "Bug Reports": f"{URL}/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Bedrock": "https://aws.amazon.com/bedrock/",
    },
    
    # Additional metadata
    zip_safe=False,
    platforms=["any"],
    
    # Package configuration
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)

# Post-installation message
def post_install():
    """Display post-installation instructions."""
    print("""
    ╔══════════════════════════════════════════════════════════════════╗
    ║                                                                  ║
    ║  🚀 Automated Data Analysis CDK Application Installed!          ║
    ║                                                                  ║
    ║  Next Steps:                                                     ║
    ║  1. Set up AWS credentials: aws configure                        ║
    ║  2. Bootstrap CDK (if first time): cdk bootstrap                 ║
    ║  3. Deploy the stack: cdk deploy                                 ║
    ║  4. Upload datasets to the created S3 bucket                     ║
    ║                                                                  ║
    ║  📖 Documentation: README.md                                     ║
    ║  🐛 Issues: GitHub Issues                                        ║
    ║  💡 Features: AWS Bedrock AgentCore, Lambda, S3, CloudWatch     ║
    ║                                                                  ║
    ╚══════════════════════════════════════════════════════════════════╝
    """)

if __name__ == "__main__":
    post_install()