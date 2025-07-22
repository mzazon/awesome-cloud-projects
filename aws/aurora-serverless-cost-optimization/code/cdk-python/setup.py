"""
Setup configuration for Aurora Serverless v2 Cost Optimization CDK Application

This setup.py file configures the Python package for the Aurora Serverless v2 
cost optimization patterns CDK application. It defines package metadata, 
dependencies, and entry points for the application.

The package implements intelligent auto-scaling patterns for Aurora Serverless v2
with comprehensive cost optimization strategies including automated scaling,
pause/resume capabilities, and cost monitoring.
"""

from setuptools import setup, find_packages
import os

# Read the contents of README file
this_directory = os.path.abspath(os.path.dirname(__file__))
try:
    with open(os.path.join(this_directory, 'README.md'), encoding='utf-8') as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = """
    Aurora Serverless v2 Cost Optimization Patterns - CDK Python Application
    
    This CDK application implements intelligent auto-scaling patterns for Aurora Serverless v2
    that automatically adjust capacity based on workload demands while incorporating cost 
    optimization strategies.
    """

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements_path = os.path.join(this_directory, 'requirements.txt')
    try:
        with open(requirements_path, 'r') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Handle inline comments
                    if '#' in line:
                        line = line[:line.index('#')].strip()
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib>=2.100.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.28.0"
        ]

setup(
    # Package metadata
    name="aurora-serverless-v2-cost-optimization",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="Aurora Serverless v2 Cost Optimization Patterns using AWS CDK",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "isort>=5.12.0"
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0"
        ],
        "security": [
            "bandit>=1.7.5",
            "safety>=2.3.5"
        ]
    },
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "aurora-sv2-cost-opt=app:main",
        ],
    },
    
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Database",
        "Topic :: Internet :: WWW/HTTP",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "aurora",
        "serverless",
        "cost-optimization",
        "database",
        "scaling",
        "postgresql",
        "infrastructure",
        "cloud"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Aurora": "https://aws.amazon.com/rds/aurora/",
    },
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Additional metadata
    platforms=["any"],
    license="Apache License 2.0",
)