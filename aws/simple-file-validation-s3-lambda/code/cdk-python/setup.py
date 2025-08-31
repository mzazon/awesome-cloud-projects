"""
Setup configuration for Simple File Validation CDK Application

This setup.py file configures the Python package for the AWS CDK application
that deploys a serverless file validation system using S3 and Lambda.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Simple File Validation with S3 and Lambda - CDK Python Application"

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file."""
    with open(filename, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    
    requirements = []
    for line in lines:
        line = line.strip()
        # Skip empty lines and comments
        if line and not line.startswith("#"):
            requirements.append(line)
    
    return requirements

setup(
    name="file-validation-cdk",
    version="1.0.0",
    description="AWS CDK application for serverless file validation with S3 and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/simple-file-validation-s3-lambda",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=parse_requirements("requirements.txt"),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "isort>=5.0.0",
        ]
    },
    
    # Project metadata
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "s3",
        "lambda",
        "serverless",
        "file-validation",
        "cloud",
        "infrastructure-as-code",
        "python"
    ],
    
    # Entry points
    entry_points={
        "console_scripts": [
            "file-validation-cdk=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/simple-file-validation-s3-lambda/issues",
        "Source": "https://github.com/aws-samples/simple-file-validation-s3-lambda",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # License
    license="Apache License 2.0",
    
    # Minimum Python version check
    zip_safe=False,
)