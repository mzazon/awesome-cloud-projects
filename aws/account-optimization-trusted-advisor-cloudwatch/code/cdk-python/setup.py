"""
Setup configuration for AWS CDK Python Application
Account Optimization Monitoring with Trusted Advisor and CloudWatch
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="trusted-advisor-monitoring-cdk",
    version="1.0.0",
    author="AWS Cloud Operations Team",
    author_email="cloudops@company.com",
    description="AWS CDK Python application for monitoring Trusted Advisor optimization recommendations",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/company/trusted-advisor-monitoring",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Developers",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Environment :: Console",
        "Framework :: AWS CDK",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.155.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "trusted-advisor-monitoring=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloudwatch",
        "sns",
        "trusted-advisor",
        "monitoring",
        "alerts",
        "optimization",
        "cost-management",
        "security",
        "infrastructure-as-code"
    ],
    project_urls={
        "Bug Reports": "https://github.com/company/trusted-advisor-monitoring/issues",
        "Source": "https://github.com/company/trusted-advisor-monitoring",
        "Documentation": "https://github.com/company/trusted-advisor-monitoring/wiki",
    },
)