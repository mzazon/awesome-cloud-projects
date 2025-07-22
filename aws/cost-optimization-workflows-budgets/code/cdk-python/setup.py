"""
Setup configuration for AWS CDK Python Cost Optimization Application.

This setup.py file configures the Python package for the automated cost optimization
workflows using AWS Cost Optimization Hub and AWS Budgets.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = [
                line.strip()
                for line in f
                if line.strip() and not line.startswith("#")
            ]
        return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.150.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "typing-extensions>=4.0.0",
        ]


def read_long_description() -> str:
    """Read long description from README file if available."""
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return """
        # AWS Cost Optimization Workflows with CDK

        This CDK Python application deploys automated cost optimization workflows 
        using AWS Cost Optimization Hub and AWS Budgets for proactive cost management.

        ## Features

        - AWS Cost Optimization Hub integration for centralized recommendations
        - Multiple budget types (cost, usage, RI utilization)
        - SNS notifications for budget alerts and anomaly detection
        - Lambda automation for processing cost optimization events
        - IAM roles and policies with least privilege principles
        - Cost anomaly detection with machine learning

        ## Deployment

        ```bash
        pip install -r requirements.txt
        cdk deploy
        ```

        ## Configuration

        Set environment variables or CDK context for customization:
        - NOTIFICATION_EMAIL: Email for budget alerts
        - MONTHLY_BUDGET_LIMIT: Monthly cost budget in USD
        - EC2_USAGE_LIMIT: EC2 usage limit in hours
        - RI_UTILIZATION_THRESHOLD: RI utilization threshold percentage
        """


setuptools.setup(
    name="aws-cost-optimization-workflows",
    version="1.0.0",
    author="AWS Solutions Architecture",
    author_email="aws-solutions@amazon.com",
    description="CDK Python application for automated cost optimization workflows with AWS Cost Optimization Hub and Budgets",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-cost-optimization-workflows",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cost-management/",
        "Source": "https://github.com/aws-samples/aws-cost-optimization-workflows",
        "Bug Reports": "https://github.com/aws-samples/aws-cost-optimization-workflows/issues",
    },
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "isort>=5.10.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Office/Business :: Financial :: Accounting",
    ],
    keywords=[
        "aws",
        "cdk",
        "cost-optimization",
        "budgets",
        "finops",
        "cloud-financial-management",
        "cost-anomaly-detection",
        "serverless",
        "infrastructure-as-code",
    ],
    entry_points={
        "console_scripts": [
            "cdk-cost-optimization=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)