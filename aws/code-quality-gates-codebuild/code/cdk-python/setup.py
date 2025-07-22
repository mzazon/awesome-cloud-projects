"""
Setup configuration for the Code Quality Gates CDK Python application.

This setup.py file defines the package configuration, dependencies, and metadata
for the CDK Python application that implements code quality gates with CodeBuild.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
requirements_path = this_directory / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        install_requires = [
            line.strip()
            for line in f.readlines()
            if line.strip() and not line.startswith("#") and not line.startswith("-")
        ]
else:
    # Fallback requirements if file doesn't exist
    install_requires = [
        "aws-cdk-lib>=2.164.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
        "typing-extensions>=4.0.0",
    ]

setuptools.setup(
    name="code-quality-gates-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for Code Quality Gates with CodeBuild",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Software Development :: Build Tools",
        "Topic :: Software Development :: Quality Assurance",
        "Topic :: Software Development :: Testing",
    ],
    
    # Package requirements
    python_requires=">=3.8",
    install_requires=install_requires,
    
    # Development dependencies
    extras_require={
        "dev": [
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Package discovery
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    # Entry points
    entry_points={
        "console_scripts": [
            "quality-gates-cdk=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/latest/guide/",
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "codebuild",
        "quality-gates",
        "ci-cd",
        "testing",
        "code-quality",
        "static-analysis",
        "security-scanning",
        "devops",
        "infrastructure-as-code",
    ],
    
    # License
    license="Apache-2.0",
    
    # Package metadata
    zip_safe=False,
    platforms=["any"],
    
    # Minimum CDK version
    install_requires=install_requires,
)