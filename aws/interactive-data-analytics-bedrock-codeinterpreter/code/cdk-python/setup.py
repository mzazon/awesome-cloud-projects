"""
Setup configuration for Interactive Data Analytics CDK Python Application.

This package implements a comprehensive analytics platform using AWS CDK Python
that combines natural language processing with secure code execution capabilities
through AWS Bedrock AgentCore Code Interpreter.

Features:
- S3 buckets for scalable data storage and results archiving
- Lambda functions for serverless orchestration and workflow management
- Bedrock AgentCore Code Interpreter for AI-powered data analysis
- API Gateway for secure external access with rate limiting
- CloudWatch for comprehensive monitoring and alerting
- IAM roles with least privilege access principles
- SQS dead letter queues for robust error handling

The solution enables users to submit analytical requests in natural language,
automatically generates and executes Python code in sandboxed environments,
and delivers actionable insights through secure, enterprise-grade infrastructure.
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read README.md file for package long description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return __doc__

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Handle version constraints and comments
                    if "#" in line:
                        line = line.split("#")[0].strip()
                    if line:
                        requirements.append(line)
    
    return requirements

# Package metadata
setup(
    name="interactive-data-analytics-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Interactive Data Analytics with Bedrock AgentCore Code Interpreter",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Development Team",
    author_email="aws-cdk-dev@example.com",
    maintainer="Data Analytics Team",
    maintainer_email="data-analytics@example.com",
    
    # URLs and links
    url="https://github.com/aws-samples/interactive-data-analytics-bedrock",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/bedrock/",
        "Source": "https://github.com/aws-samples/interactive-data-analytics-bedrock",
        "Tracker": "https://github.com/aws-samples/interactive-data-analytics-bedrock/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Bedrock": "https://aws.amazon.com/bedrock/"
    },
    
    # Package discovery and structure
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_dir={"": "."},
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.0.0"
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
            "myst-parser>=2.0.0"
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.3.0",
            "cdk-nag>=2.28.0"
        ]
    },
    
    # Package classification
    classifiers=[
        # Development Status
        "Development Status :: 4 - Beta",
        
        # Intended Audience
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Information Technology",
        
        # Topic Classification
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
        "Topic :: Office/Business :: Financial :: Spreadsheet",
        
        # License
        "License :: OSI Approved :: Apache Software License",
        
        # Programming Language
        "Programming Language :: Python",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Programming Language :: Python :: 3 :: Only",
        
        # Operating System
        "Operating System :: OS Independent",
        "Operating System :: POSIX :: Linux",
        "Operating System :: Microsoft :: Windows",
        "Operating System :: MacOS",
        
        # Environment
        "Environment :: Console",
        "Environment :: Web Environment",
        
        # Framework
        "Framework :: AWS CDK",
        
        # Natural Language
        "Natural Language :: English"
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "bedrock", "analytics", "data-science", 
        "machine-learning", "artificial-intelligence", "serverless",
        "lambda", "s3", "api-gateway", "cloudwatch", "code-interpreter",
        "natural-language-processing", "data-analysis", "python",
        "infrastructure-as-code", "cloud-computing", "enterprise"
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "cdk-analytics-deploy=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
            "cdk.json",
            "cdk.context.json"
        ]
    },
    
    # Exclude development files from distribution
    exclude_package_data={
        "": [
            "*.pyc",
            "__pycache__/*",
            "*.pyo",
            "*.pyd",
            ".git/*",
            ".gitignore",
            ".pytest_cache/*",
            "*.egg-info/*",
            "build/*",
            "dist/*"
        ]
    },
    
    # Zip safe configuration
    zip_safe=False,
    
    # Platform specification
    platforms=["any"],
    
    # License specification
    license="Apache-2.0",
    
    # Additional metadata
    project_urls={
        "Homepage": "https://github.com/aws-samples/interactive-data-analytics-bedrock",
        "Documentation": "https://docs.aws.amazon.com/bedrock/latest/userguide/",
        "Repository": "https://github.com/aws-samples/interactive-data-analytics-bedrock.git",
        "Bug Reports": "https://github.com/aws-samples/interactive-data-analytics-bedrock/issues",
        "Funding": "https://github.com/sponsors/aws",
        "Source": "https://github.com/aws-samples/interactive-data-analytics-bedrock/tree/main/",
        "Changelog": "https://github.com/aws-samples/interactive-data-analytics-bedrock/blob/main/CHANGELOG.md"
    },
    
    # Test suite configuration
    test_suite="tests",
    tests_require=[
        "pytest>=7.4.0",
        "pytest-cov>=4.1.0",
        "pytest-mock>=3.11.0",
        "boto3-stubs[essential]>=1.34.0"
    ],
    
    # Options for various tools
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3"
        },
        "egg_info": {
            "tag_build": "",
            "tag_date": False
        }
    }
)

# Additional setup for CDK-specific configuration
if __name__ == "__main__":
    print("Setting up Interactive Data Analytics CDK Python Application...")
    print("This package provides infrastructure as code for:")
    print("  • AWS Bedrock AgentCore Code Interpreter integration")
    print("  • Serverless data analytics orchestration")
    print("  • Secure API Gateway with rate limiting")
    print("  • Comprehensive CloudWatch monitoring")
    print("  • Enterprise-grade security and compliance")
    print("  • Scalable S3 data storage and lifecycle management")
    print("")
    print("For deployment instructions, see README.md")
    print("For AWS CDK documentation, visit: https://docs.aws.amazon.com/cdk/")