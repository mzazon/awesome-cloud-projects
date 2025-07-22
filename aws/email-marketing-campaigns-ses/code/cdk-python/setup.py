"""
Setup configuration for Email Marketing Campaigns CDK Python application.

This setup file configures the CDK Python project for email marketing campaigns
using Amazon SES, including all necessary dependencies and metadata.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [
        line.strip()
        for line in f
        if line.strip() and not line.startswith("#")
    ]

setup(
    name="email-marketing-campaigns-ses",
    version="1.0.0",
    description="CDK Python application for email marketing campaigns with Amazon SES",
    long_description="""
    This CDK Python application creates a complete email marketing infrastructure
    on AWS using Amazon SES as the core email service. It includes:
    
    - Amazon SES email identities and configuration sets
    - Email templates for personalized campaigns
    - S3 bucket for subscriber lists and template storage
    - SNS topic for real-time email event notifications
    - Lambda functions for bounce handling and campaign automation
    - CloudWatch dashboard and alarms for monitoring
    - EventBridge rules for automated campaign scheduling
    
    The application follows AWS best practices for security, scalability,
    and cost optimization while providing a foundation for sophisticated
    email marketing automation workflows.
    """,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    install_requires=requirements,
    python_requires=">=3.8",
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Communications :: Email",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Office/Business :: Groupware",
    ],
    keywords=[
        "aws",
        "cdk",
        "ses",
        "email-marketing",
        "campaigns",
        "sns",
        "s3",
        "lambda",
        "cloudwatch",
        "infrastructure",
        "automation",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS SES Documentation": "https://docs.aws.amazon.com/ses/",
    },
    entry_points={
        "console_scripts": [
            "email-marketing-cdk=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-setuptools>=68.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
)