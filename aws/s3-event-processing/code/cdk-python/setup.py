"""
Setup configuration for Event-Driven Data Processing CDK Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
"""

from setuptools import setup, find_packages

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for event-driven data processing with S3 event notifications"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.100.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0"
    ]

setup(
    name="event-driven-data-processing-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for event-driven data processing with S3 event notifications",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/event-driven-data-processing-cdk",
    
    # Package discovery
    packages=find_packages(),
    
    # Package data
    include_package_data=True,
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "isort>=5.0.0"
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0"
        ]
    },
    
    # Python version requirement
    python_requires=">=3.7",
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Framework :: AWS CDK",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: Software Development :: Libraries :: Python Modules"
    ],
    
    # Keywords for package discovery
    keywords="aws cdk cloud infrastructure serverless lambda s3 event-driven data-processing",
    
    # Entry points for CLI tools (if any)
    entry_points={
        "console_scripts": [
            # Add any CLI tools here if needed
            # "my-tool=my_package.module:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/event-driven-data-processing-cdk/issues",
        "Source": "https://github.com/aws-samples/event-driven-data-processing-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # Zip safety
    zip_safe=False,
    
    # License
    license="Apache-2.0"
)