"""
Setup script for Real-time Data Synchronization with AWS AppSync CDK Application

This setup.py file configures the Python package for the CDK application,
defining dependencies, metadata, and packaging information.
"""

from setuptools import setup, find_packages

# Read README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Real-time Data Synchronization with AppSync"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            requirements = []
            for line in req_file:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.160.0",
            "constructs>=10.0.0",
            "boto3>=1.34.0",
        ]

setup(
    name="realtime-data-sync-appsync",
    version="1.0.0",
    description="AWS CDK Python application for Real-time Data Synchronization with AppSync",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Team",
    author_email="recipes@example.com",
    url="https://github.com/aws-samples/aws-recipes",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.9.0",
            "flake8>=6.1.0",
            "mypy>=1.6.0",
            "bandit>=1.7.5",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=1.3.0",
        ]
    },
    
    # Package classifiers for PyPI
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
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
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws", "cdk", "appsync", "graphql", "dynamodb", "real-time",
        "subscriptions", "collaborative", "infrastructure", "cloud"
    ],
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "deploy-realtime-sync=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/aws-recipes",
        "Bug Reports": "https://github.com/aws-samples/aws-recipes/issues",
        "AWS AppSync": "https://aws.amazon.com/appsync/",
        "CDK Python": "https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html",
    },
    
    # Package data and manifest
    package_data={
        "": ["*.md", "*.txt", "*.graphql", "*.json"],
    },
    
    # Zip safe configuration
    zip_safe=False,
    
    # License information
    license="MIT",
    
    # Additional metadata
    platforms=["any"],
)