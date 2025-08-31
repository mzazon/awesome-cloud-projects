"""
Setup configuration for AWS CDK Python Service Quota Monitoring application.

This setup.py file defines the package configuration, dependencies, and
metadata for the service quota monitoring CDK application.
"""

from setuptools import setup, find_packages

# Read the contents of README file if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for service quota monitoring with CloudWatch alarms"

# Package configuration
setup(
    name="service-quota-monitoring-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS CDK Python Generator",
    author_email="admin@example.com",
    description="AWS CDK Python application for monitoring service quotas with CloudWatch alarms",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Package discovery
    packages=find_packages(exclude=["tests*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
            "isort>=5.12.0",
        ],
        "cli": [
            "awscli>=1.27.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "quota-monitoring-deploy=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package classifiers
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Monitoring",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk cloudwatch service-quotas monitoring alarms sns notifications infrastructure-as-code",
    
    # Include additional files
    include_package_data=True,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safe configuration
    zip_safe=False,
)