"""
Setup configuration for Asynchronous API Patterns CDK Python application.

This setup.py file configures the Python package for the CDK application
that creates an asynchronous job processing system using API Gateway and SQS.
"""

from setuptools import setup, find_packages
import os

# Read long description from README if it exists
def read_readme():
    """Read README file for long description."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "Asynchronous API Patterns with API Gateway and SQS - CDK Python Implementation"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    requirements.append(line)
    
    return requirements

setup(
    name="async-api-patterns-cdk",
    version="1.0.0",
    description="AWS CDK Python implementation for Asynchronous API Patterns with API Gateway and SQS",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Recipe Generator",
    author_email="recipes@example.com",
    
    # Project URLs
    url="https://github.com/aws-recipes/asynchronous-api-patterns",
    project_urls={
        "Documentation": "https://github.com/aws-recipes/asynchronous-api-patterns/blob/main/README.md",
        "Source": "https://github.com/aws-recipes/asynchronous-api-patterns",
        "Tracker": "https://github.com/aws-recipes/asynchronous-api-patterns/issues",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "mypy>=1.8.0",
            "black>=23.12.0",
            "flake8>=7.0.0",
            "isort>=5.13.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # AWS mocking library for tests
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-async-api=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk api-gateway sqs lambda dynamodb s3 serverless asynchronous job-processing",
    
    # License
    license="Apache License 2.0",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safe configuration
    zip_safe=False,
)