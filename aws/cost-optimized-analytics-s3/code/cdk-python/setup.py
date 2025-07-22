"""
Setup configuration for Cost-Optimized Analytics S3 Intelligent-Tiering CDK application.

This setup.py file configures the Python package for the CDK application,
including metadata, dependencies, and entry points for deployment scripts.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
README_PATH = Path(__file__).parent / "README.md"
try:
    with open(README_PATH, "r", encoding="utf-8") as readme_file:
        long_description = readme_file.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python application for Cost-Optimized Analytics with S3 Tiering.
    
    This application deploys infrastructure for a cost-optimized analytics solution
    using S3 Intelligent-Tiering, AWS Glue, Amazon Athena, and CloudWatch monitoring.
    """

# Read requirements from requirements.txt
REQUIREMENTS_PATH = Path(__file__).parent / "requirements.txt"
try:
    with open(REQUIREMENTS_PATH, "r", encoding="utf-8") as req_file:
        requirements = [
            line.strip() 
            for line in req_file.readlines() 
            if line.strip() and not line.startswith("#")
        ]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.114.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0"
    ]

setuptools.setup(
    # Package metadata
    name="cost-optimized-analytics-s3-intelligent-tiering",
    version="1.0.0",
    author="AWS Recipe CDK Generator",
    author_email="example@amazon.com",
    description="AWS CDK Python application for Cost-Optimized Analytics with S3 Tiering",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/cost-optimized-analytics-s3-intelligent-tiering",
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.3",
            "pytest-cov>=4.1.0",
            "mypy>=1.7.0",
            "black>=23.10.1",
            "flake8>=6.1.0",
            "isort>=5.12.0",
            "bandit>=1.7.5",
            "safety>=2.3.5",
            "moto>=4.2.13",
            "freezegun>=1.2.2"
        ],
        "docs": [
            "sphinx>=7.2.6",
            "sphinx-rtd-theme>=1.3.0"
        ]
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-analytics=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Database",
        "Typing :: Typed",
    ],
    
    # Package keywords
    keywords=[
        "aws", "cdk", "cloud", "infrastructure", "s3", "analytics", 
        "cost-optimization", "intelligent-tiering", "athena", "glue", 
        "cloudwatch", "serverless", "data-lake", "big-data"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/cost-optimized-analytics-s3-intelligent-tiering",
        "Tracker": "https://github.com/aws-samples/cost-optimized-analytics-s3-intelligent-tiering/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS S3 Intelligent-Tiering": "https://aws.amazon.com/s3/storage-classes/intelligent-tiering/",
        "AWS Athena": "https://aws.amazon.com/athena/",
        "AWS Glue": "https://aws.amazon.com/glue/"
    },
    
    # License
    license="MIT",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
)