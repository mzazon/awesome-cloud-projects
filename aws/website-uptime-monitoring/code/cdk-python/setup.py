"""
Setup configuration for Website Uptime Monitoring CDK Python application.

This setup.py file configures the Python package for the CDK application,
defining metadata, dependencies, and package configuration.
"""

import setuptools

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Website Uptime Monitoring with Route 53 Health Checks CDK Application"

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file."""
    try:
        with open(filename, "r", encoding="utf-8") as f:
            lines = f.readlines()
        
        requirements = []
        for line in lines:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith("#"):
                requirements.append(line)
        
        return requirements
    except FileNotFoundError:
        # Fallback to minimal requirements if file not found
        return [
            "aws-cdk-lib>=2.166.0,<3.0.0",
            "constructs>=10.0.0,<12.0.0"
        ]

setuptools.setup(
    name="website-uptime-monitoring-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="Website Uptime Monitoring with Route 53 Health Checks CDK Application",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(),
    
    # Entry points
    entry_points={
        "console_scripts": [
            "website-uptime-monitoring=app:main",
        ],
    },
    
    # Dependencies
    install_requires=parse_requirements("requirements.txt"),
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package classifiers
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Networking :: Monitoring",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "infrastructure",
        "monitoring",
        "uptime",
        "route53",
        "health-checks",
        "cloudwatch",
        "sns",
        "alerting"
    ],
    
    # Additional package data
    include_package_data=True,
    
    # Package options
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/v2/guide/",
        "AWS CDK API Reference": "https://docs.aws.amazon.com/cdk/api/v2/",
    },
)