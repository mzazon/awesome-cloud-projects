"""
Setup configuration for AWS Application Migration Service CDK Python application.

This setup file configures the Python package for the CDK application that
provisions infrastructure for large-scale server migration using AWS Application
Migration Service.
"""

from setuptools import setup, find_packages

# Read long description from README
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS Application Migration Service CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            return [line.strip() for line in fh if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.100.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0",
            "boto3>=1.28.0"
        ]

setup(
    name="aws-mgn-cdk-python",
    version="1.0.0",
    description="AWS CDK Python application for Application Migration Service",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/aws-mgn-cdk-python",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "boto3-stubs[essential]>=1.28.0",
            "types-setuptools>=68.0.0"
        ]
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "mgn-cdk-deploy=app:main",
        ],
    },
    
    # Classifiers
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
        "Topic :: Utilities"
    ],
    
    # Keywords
    keywords="aws cdk migration mgn application-migration-service infrastructure-as-code",
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/aws-mgn-cdk-python/issues",
        "Source": "https://github.com/aws-samples/aws-mgn-cdk-python",
        "Documentation": "https://docs.aws.amazon.com/mgn/",
        "AWS CDK": "https://docs.aws.amazon.com/cdk/",
    },
    
    # License
    license="Apache-2.0",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Zip safety
    zip_safe=False,
)