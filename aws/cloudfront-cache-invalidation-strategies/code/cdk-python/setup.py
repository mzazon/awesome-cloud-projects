"""
Python package setup for CloudFront Cache Invalidation Strategies CDK application.

This setup.py file configures the Python package for the CDK application that
deploys an intelligent CloudFront cache invalidation system with automated
event processing and cost optimization.
"""

from setuptools import setup, find_packages

# Read the contents of README file
from pathlib import Path
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

setup(
    name="cloudfront-cache-invalidation-cdk",
    version="1.0.0",
    description="CDK Python application for intelligent CloudFront cache invalidation strategies",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Include non-Python files
    include_package_data=True,
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib==2.100.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
        "pyyaml>=6.0",
        "python-dotenv>=1.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "cdk-invalidation-deploy=app:main",
        ],
    },
    
    # Classification metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: System :: Distributed Computing",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloudfront",
        "cache-invalidation",
        "content-delivery",
        "optimization",
        "event-driven",
        "serverless",
        "infrastructure-as-code",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Funding": "https://github.com/sponsors/aws",
    },
    
    # Package data
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
    
    # Data files
    data_files=[
        ("", ["requirements.txt"]),
    ],
    
    # Zip safety
    zip_safe=False,
)