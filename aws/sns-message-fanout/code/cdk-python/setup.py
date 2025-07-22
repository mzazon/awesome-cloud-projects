"""
Setup configuration for SNS-SQS Message Fan-out CDK Application

This setup.py file configures the Python package for the CDK application
that deploys a message fan-out architecture using Amazon SNS and SQS.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python Application for SNS-SQS Message Fan-out Architecture
    
    This CDK application deploys a complete message fan-out solution using:
    - Amazon SNS for publish-subscribe messaging
    - Multiple SQS queues for different business functions
    - Dead letter queues for error handling
    - Message filtering for intelligent routing
    - CloudWatch monitoring and alerting
    """

setup(
    name="sns-sqs-message-fanout",
    version="1.0.0",
    description="AWS CDK Python application for SNS-SQS message fan-out architecture",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="support@aws.amazon.com",
    url="https://github.com/aws-samples/aws-cdk-examples",
    
    # Package configuration
    packages=find_packages(),
    py_modules=["app"],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
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
        "Topic :: System :: Networking",
        "Topic :: System :: Distributed Computing",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "sns",
        "sqs",
        "messaging",
        "fanout",
        "publish-subscribe",
        "serverless",
        "microservices",
        "event-driven",
        "distributed-systems"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "deploy-message-fanout=app:main",
        ],
    },
    
    # Additional package data
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
    },
)