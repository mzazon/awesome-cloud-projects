"""
Python package setup configuration for CDK Automated Data Archiving application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
"""

from setuptools import setup, find_packages

# Read the contents of README file for long description
from pathlib import Path
this_directory = Path(__file__).parent
try:
    long_description = (this_directory / "README.md").read_text()
except FileNotFoundError:
    long_description = "CDK Python application for Automated Data Archiving with S3 Glacier"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = this_directory / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, 'r') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith('#'):
                    requirements.append(line)
            return requirements
    return []

setup(
    # Package metadata
    name="automated-data-archiving-cdk",
    version="1.0.0",
    description="CDK Python application for Automated Data Archiving with S3 Glacier",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    
    # Project URLs
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package discovery
    packages=find_packages(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Additional development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "isort>=5.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    # Classification
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Cloud Computing",
    ],
    
    # Keywords
    keywords="aws cdk cloud infrastructure s3 glacier archiving storage lifecycle",
    
    # License
    license="Apache-2.0",
    
    # Include additional files
    include_package_data=True,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safe
    zip_safe=False,
)