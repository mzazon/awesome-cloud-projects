"""
Setup configuration for the Real-Time WebSocket API CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages

# Read the contents of the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Real-time WebSocket API with route management and connection handling using AWS CDK"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.28.0",
        "botocore>=1.31.0",
    ]

setup(
    name="websocket-api-cdk",
    version="1.0.0",
    description="Real-time WebSocket API with route management and connection handling using AWS CDK",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    url="https://github.com/aws-samples/websocket-api-cdk",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=requirements,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Communications :: Chat",
        "Topic :: System :: Networking",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "websocket",
        "api-gateway",
        "real-time",
        "chat",
        "messaging",
        "serverless",
        "lambda",
        "dynamodb",
        "infrastructure-as-code",
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-websocket-api=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/websocket-api-cdk/issues",
        "Source": "https://github.com/aws-samples/websocket-api-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/v2/guide/",
        "API Gateway WebSocket": "https://docs.aws.amazon.com/apigateway/latest/developerguide/websocket-api.html",
    },
)