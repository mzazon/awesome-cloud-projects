"""
Setup configuration for Feature Flags with AWS AppConfig CDK application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

import setuptools

# Read the long description from README
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Feature Flags with AWS AppConfig - CDK Python Implementation"

# Read requirements from requirements.txt
def read_requirements(filename: str) -> list:
    """Read requirements from requirements.txt file"""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith('#'):
                    # Remove inline comments
                    requirement = line.split('#')[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        return []

# Development dependencies
dev_requirements = [
    "pytest>=6.2.5",
    "pytest-cov>=2.12.1",
    "black>=21.6b0",
    "flake8>=3.9.2",
    "mypy>=0.910",
    "pre-commit>=2.15.0",
    "bandit>=1.7.0",
    "safety>=1.10.3"
]

setuptools.setup(
    name="feature-flags-appconfig-cdk",
    version="1.0.0",
    
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    
    description="Feature Flags with AWS AppConfig - CDK Python Implementation",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws/aws-cdk",
    
    # Package discovery
    packages=setuptools.find_packages(),
    
    # Include package data
    include_package_data=True,
    package_data={
        "": ["*.md", "*.json", "*.yaml", "*.yml"],
    },
    
    # Dependencies
    install_requires=read_requirements("requirements.txt"),
    
    # Development dependencies
    extras_require={
        "dev": dev_requirements,
        "test": [
            "pytest>=6.2.5",
            "pytest-cov>=2.12.1",
            "moto>=4.0.0",
            "pytest-mock>=3.6.1"
        ]
    },
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Classification metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "appconfig",
        "feature-flags",
        "lambda",
        "cloudwatch",
        "infrastructure",
        "cloud",
        "devops"
    ],
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "deploy-feature-flags=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "CDK Workshop": "https://cdkworkshop.com/",
    },
    
    # License
    license="Apache License 2.0",
    
    # Zip safety
    zip_safe=False,
)