"""
Setup script for AWS CDK Email Processing System

This setup.py file configures the Python package for the serverless email processing
CDK application. It defines package metadata, dependencies, and installation requirements.
"""

import setuptools
from pathlib import Path

# Read the contents of README file
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
def parse_requirements(filename: str):
    """Parse requirements from requirements.txt file."""
    requirements = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and not line.startswith('-'):
                # Remove inline comments
                if '#' in line:
                    line = line[:line.index('#')].strip()
                requirements.append(line)
    return requirements

setuptools.setup(
    name="email-processing-cdk",
    version="1.0.0",
    
    description="AWS CDK application for serverless email processing with SES and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    
    url="https://github.com/aws-samples/email-processing-cdk",
    
    packages=setuptools.find_packages(),
    
    install_requires=parse_requirements("requirements.txt"),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Communications :: Email",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "email",
        "processing",
        "serverless",
        "ses",
        "lambda",
        "automation",
        "infrastructure",
        "cloud"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/email-processing-cdk",
        "Bug Reports": "https://github.com/aws-samples/email-processing-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS SES": "https://aws.amazon.com/ses/",
        "AWS Lambda": "https://aws.amazon.com/lambda/",
    },
    
    entry_points={
        "console_scripts": [
            "email-processing-cdk=app:main",
        ],
    },
    
    include_package_data=True,
    
    zip_safe=False,
    
    # Additional metadata
    maintainer="AWS Solutions Team",
    maintainer_email="aws-solutions@amazon.com",
    
    platforms=["any"],
    
    # Package data
    package_data={
        "": ["*.txt", "*.md", "*.yml", "*.yaml", "*.json"],
    },
)