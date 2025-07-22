"""
Setup configuration for Ordered Message Processing CDK Python Application

This setup.py file configures the Python package for the CDK application that
implements ordered message processing with SQS FIFO queues and dead letter queues.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="ordered-message-processing-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="cdk-generator@example.com",
    description="CDK Python application for ordered message processing with SQS FIFO and dead letter queues",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/ordered-message-processing-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/ordered-message-processing-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/aws-samples/ordered-message-processing-cdk",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: System :: Distributed Computing",
        "Topic :: System :: Networking",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.165.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "jsonschema>=4.0.0",
        "python-dateutil>=2.8.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.26.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto[all]>=4.0.0",  # For mocking AWS services in tests
            "freezegun>=1.2.0",  # For mocking datetime in tests
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-ordered-processing=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "sqs", 
        "fifo",
        "lambda",
        "dynamodb",
        "s3",
        "sns",
        "cloudwatch",
        "message-processing",
        "dead-letter-queue",
        "ordered-processing",
        "financial-systems",
        "trading-systems",
        "infrastructure-as-code",
        "serverless",
        "microservices",
        "event-driven",
        "poison-messages",
        "message-replay",
        "monitoring",
        "alerting",
        "fault-tolerance",
        "exactly-once-processing",
        "message-deduplication",
        "high-throughput",
        "enterprise-architecture",
    ],
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    zip_safe=False,
)