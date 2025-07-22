"""
Setup configuration for Cross-Region Disaster Recovery Automation CDK Application

This setup.py file configures the Python package for the AWS CDK application
that implements cross-region disaster recovery automation using AWS Elastic
Disaster Recovery (DRS) with automated failover capabilities.
"""

from setuptools import setup, find_packages
import pathlib

# Get the long description from the README file
here = pathlib.Path(__file__).parent.resolve()
long_description = (here / "README.md").read_text(encoding="utf-8") if (here / "README.md").exists() else ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = here / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, "r", encoding="utf-8") as f:
            return [
                line.strip()
                for line in f
                if line.strip() and not line.startswith("#")
            ]
    return []

setup(
    name="cross-region-disaster-recovery-automation",
    version="1.0.0",
    description="AWS CDK Python application for cross-region disaster recovery automation with Elastic Disaster Recovery",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/disaster-recovery-automation",
    author="AWS Recipe CDK Generator",
    author_email="aws-recipes@amazon.com",
    license="MIT-0",
    
    # Classifiers help users find your project by categorizing it
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
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Disaster Recovery",
        "Topic :: System :: Systems Administration",
    ],
    
    # Keywords that describe your project
    keywords="aws cdk disaster-recovery automation elastic-disaster-recovery cross-region failover",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*", "docs", "docs.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for different use cases
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
            "sphinxcontrib-mermaid>=0.9.0",
        ],
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-dr-automation=app:main",
        ],
    },
    
    # Additional data files to include in the package
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
            "cdk.json",
        ],
    },
    
    # Include additional files specified in MANIFEST.in
    include_package_data=True,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/disaster-recovery-automation/issues",
        "Source": "https://github.com/aws-samples/disaster-recovery-automation",
        "Documentation": "https://docs.aws.amazon.com/drs/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Elastic Disaster Recovery": "https://aws.amazon.com/disaster-recovery/",
    },
    
    # Zip safe configuration
    zip_safe=False,
    
    # Platform specific configurations
    platforms=["any"],
)