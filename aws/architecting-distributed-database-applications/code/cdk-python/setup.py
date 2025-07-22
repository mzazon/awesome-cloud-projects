"""
Setup configuration for Aurora DSQL multi-region distributed application CDK Python project.

This setup.py file configures the Python package for the Aurora DSQL CDK application,
including dependencies, metadata, and development tools configuration.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
README_PATH = Path(__file__).parent / "README.md"
if README_PATH.exists():
    with open(README_PATH, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = """
    AWS CDK Python application for Architecting Distributed Database Applications with Aurora DSQL.
    
    This application demonstrates how to create a resilient, scalable distributed database
    architecture using Aurora DSQL's active-active multi-region capabilities, combined with
    Lambda functions for serverless compute and EventBridge for event-driven coordination.
    """

# Read requirements from requirements.txt
def read_requirements():
    """Read and parse requirements.txt file."""
    requirements_path = Path(__file__).parent / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        
        # Filter out comments and empty lines
        requirements = []
        for line in lines:
            line = line.strip()
            if line and not line.startswith("#"):
                # Handle version constraints properly
                if ">=" in line and "<" in line:
                    requirements.append(line)
                elif line.startswith("-"):
                    # Skip pip options
                    continue
                else:
                    requirements.append(line)
        
        return requirements
    
    # Fallback to core requirements if file doesn't exist
    return [
        "aws-cdk-lib>=2.110.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "boto3>=1.34.0,<2.0.0",
    ]

setuptools.setup(
    name="aurora-dsql-multiregion-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="AWS CDK Python application for Aurora DSQL multi-region distributed applications",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0,<8.0.0",
            "pytest-cov>=4.1.0,<5.0.0",
            "black>=23.7.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.5.0,<2.0.0",
            "isort>=5.12.0,<6.0.0",
            "rich>=13.5.0,<14.0.0",
        ],
        "test": [
            "pytest>=7.4.0,<8.0.0",
            "pytest-cov>=4.1.0,<5.0.0",
            "moto>=4.2.0,<5.0.0",  # AWS service mocking
            "freezegun>=1.2.0,<2.0.0",  # Time mocking for tests
        ],
        "docs": [
            "sphinx>=7.1.0,<8.0.0",
            "sphinx-rtd-theme>=1.3.0,<2.0.0",
            "sphinxcontrib-apidoc>=0.3.0,<1.0.0",
        ]
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Database :: Database Engines/Servers",
        "Topic :: System :: Distributed Computing",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9", 
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Framework :: AWS CDK",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Software Development :: Code Generators",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk aurora dsql multi-region distributed database serverless lambda eventbridge",
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Aurora DSQL": "https://aws.amazon.com/rds/aurora/dsql/",
    },
    
    # Entry points for CLI tools (if needed)
    entry_points={
        "console_scripts": [
            "aurora-dsql-deploy=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Platform requirements
    platforms=["any"],
    
    # License
    license="Apache-2.0",
    
    # Maintainer information
    maintainer="AWS CDK Team",
    maintainer_email="aws-cdk@amazon.com",
)