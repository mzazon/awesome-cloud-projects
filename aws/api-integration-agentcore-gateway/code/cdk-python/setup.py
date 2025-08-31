"""
Setup configuration for the Enterprise API Integration CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

from setuptools import setup, find_packages

# Read the contents of README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Enterprise API Integration with AgentCore Gateway and Step Functions"

# Define package metadata
setup(
    name="api-integration-agentcore-gateway",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="Enterprise API Integration with Amazon Bedrock AgentCore Gateway and Step Functions",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/api-integration-agentcore-gateway",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.8",
    
    # Core dependencies
    install_requires=[
        "aws-cdk-lib>=2.150.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "aws-cdk.aws-lambda-python-alpha>=2.150.0a0,<3.0.0a0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "isort>=5.12.0",
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "typing": [
            "types-boto3>=1.0.0",
            "types-requests>=2.31.0",
        ],
    },
    
    # Package metadata
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
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: System :: Networking",
        "Typing :: Typed",
    ],
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-api-integration=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/api-integration-agentcore-gateway",
        "Bug Reports": "https://github.com/aws-samples/api-integration-agentcore-gateway/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Bedrock": "https://aws.amazon.com/bedrock/",
        "AWS Step Functions": "https://aws.amazon.com/step-functions/",
    },
    
    # Package data
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "api-gateway",
        "lambda",
        "step-functions",
        "bedrock",
        "agentcore",
        "enterprise",
        "integration",
        "serverless",
        "ai",
        "machine-learning",
    ],
)