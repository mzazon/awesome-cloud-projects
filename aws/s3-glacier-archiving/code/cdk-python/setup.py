"""
Setup script for Long-term Data Archiving CDK Python Application

This setup.py file defines the package configuration for the CDK application
that implements long-term data archiving using S3 Glacier Deep Archive.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = ""
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as readme_file:
        long_description = readme_file.read()

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as req_file:
        install_requires = [
            line.strip()
            for line in req_file
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="long-term-archiving-cdk",
    version="1.0.0",
    
    description="CDK Python application for S3 Glacier Deep Archive for Long-term Storage",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Archiving",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cloud-development-kit",
        "s3",
        "glacier",
        "archiving",
        "lifecycle-policies",
        "deep-archive",
        "storage",
        "compliance"
    ],
    
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    install_requires=install_requires,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.9.0",
            "flake8>=6.1.0",
            "mypy>=1.6.0",
            "pre-commit>=3.5.0",
        ],
        "cli": [
            "awscli>=1.29.0",
        ],
        "sdk": [
            "boto3>=1.29.0",
        ]
    },
    
    entry_points={
        "console_scripts": [
            "deploy-archive=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package data
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # CDK-specific metadata
    zip_safe=False,
)