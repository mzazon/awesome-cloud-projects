"""
Setup configuration for AWS CDK Python application
Data Warehousing Solutions with Redshift

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

import setuptools

# Read the contents of README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for Data Warehousing Solutions with Redshift"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            requirements = []
            for line in fh:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.150.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "typing-extensions>=4.0.0"
        ]

setuptools.setup(
    name="data-warehousing-redshift-cdk",
    version="1.0.0",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    description="CDK Python application for Data Warehousing Solutions with Redshift",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/data-warehousing-redshift-cdk",
    
    packages=setuptools.find_packages(),
    
    install_requires=read_requirements(),
    
    python_requires=">=3.8",
    
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
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "redshift",
        "data-warehouse",
        "analytics",
        "serverless",
        "big-data",
        "etl",
        "business-intelligence"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/data-warehousing-redshift-cdk/issues",
        "Source": "https://github.com/aws-samples/data-warehousing-redshift-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "CDK API Reference": "https://docs.aws.amazon.com/cdk/api/v2/",
        "Redshift Documentation": "https://docs.aws.amazon.com/redshift/",
    },
    
    # Entry points for command line scripts (if needed)
    entry_points={
        "console_scripts": [
            # Add console scripts here if needed
            # "command-name=module:function",
        ],
    },
    
    # Include additional data files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Specify minimum versions for critical dependencies
    dependency_links=[],
    
    # ZIP safe configuration
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    license="MIT",
    license_files=["LICENSE"],
)