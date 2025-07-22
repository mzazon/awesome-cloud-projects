"""
Setup configuration for ECR Container Registry Replication Strategies CDK Application

This setup.py file configures the Python package for the CDK application
that implements ECR replication strategies with monitoring and automation.
"""

from setuptools import setup, find_packages

# Read the long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python application for implementing ECR container registry replication strategies.
    
    This application creates a comprehensive ECR replication solution with:
    - Source repositories with vulnerability scanning
    - Cross-region replication configuration
    - Lifecycle policies for cost optimization
    - Repository policies for access control
    - CloudWatch monitoring and alerting
    - Lambda automation for cleanup
    """

# Read version from version file or set default
try:
    with open("VERSION", "r", encoding="utf-8") as version_file:
        version = version_file.read().strip()
except FileNotFoundError:
    version = "1.0.0"

setup(
    name="ecr-replication-strategies-cdk",
    version=version,
    description="AWS CDK Python application for ECR container registry replication strategies",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Solutions Architecture",
    author_email="solutions-architecture@amazon.com",
    
    # Package information
    url="https://github.com/aws-samples/ecr-replication-strategies",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/ecr/",
        "Source": "https://github.com/aws-samples/ecr-replication-strategies",
        "Tracker": "https://github.com/aws-samples/ecr-replication-strategies/issues",
    },
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib==2.157.0",
        "constructs>=10.3.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.9.1",
            "flake8>=6.1.0",
            "mypy>=1.6.0",
            "types-boto3>=1.0.2",
            "autopep8>=2.0.0",
            "isort>=5.12.0",
            "pre-commit>=3.4.0",
            "bandit>=1.7.5",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "test": [
            "moto>=4.2.0",
            "pytest-mock>=3.11.0",
            "jsonschema>=4.19.0",
        ],
    },
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "ecr-replication-deploy=app:main",
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
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: System :: Networking",
        "Topic :: System :: Distributed Computing",
        "Topic :: Software Development :: Build Tools",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Framework :: AWS CDK",
        "Environment :: Console",
        "Typing :: Typed",
    ],
    
    # Keywords for PyPI search
    keywords=[
        "aws",
        "cdk",
        "ecr",
        "docker",
        "containers",
        "registry",
        "replication",
        "infrastructure",
        "automation",
        "monitoring",
        "devops",
        "cloud",
        "deployment",
        "lifecycle",
        "security",
        "compliance",
        "governance",
        "multi-region",
        "disaster-recovery",
        "cost-optimization",
    ],
    
    # Package metadata
    license="MIT",
    platforms=["any"],
    zip_safe=False,
    
    # Configuration for package building
    options={
        "build_sphinx": {
            "source_dir": "docs",
            "build_dir": "docs/_build",
            "all_files": True,
        },
        "upload_sphinx": {
            "upload_dir": "docs/_build/html",
        },
    },
    
    # Additional package data
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yaml",
            "*.yml",
            "*.json",
            "LICENSE",
            "NOTICE",
            "VERSION",
        ],
    },
    
    # Test suite configuration
    test_suite="tests",
    
    # Ensure wheel distribution
    bdist_wheel={
        "universal": False,
    },
)