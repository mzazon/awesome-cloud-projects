"""
Setup configuration for Business Continuity Testing Framework CDK application.

This setup file configures the Python package for the AWS CDK application
that deploys a comprehensive business continuity testing framework using
AWS Systems Manager, Lambda, EventBridge, and CloudWatch.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="business-continuity-testing-framework",
    version="1.0.0",
    author="AWS CDK Business Continuity Team",
    author_email="admin@example.com",
    description="AWS CDK application for automated business continuity testing framework",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/business-continuity-testing-framework",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/business-continuity-testing-framework/issues",
        "Documentation": "https://docs.aws.amazon.com/systems-manager/",
        "Source Code": "https://github.com/aws-samples/business-continuity-testing-framework",
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Monitoring",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.115.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
        "boto3>=1.34.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "aws-cdk.aws-lambda-python-alpha>=2.115.0a0,<3.0.0a0",
        ],
        "enhanced": [
            "pydantic>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "bc-testing-deploy=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "business-continuity",
        "disaster-recovery", 
        "systems-manager",
        "automation",
        "testing",
        "backup",
        "failover",
        "monitoring",
        "compliance"
    ],
    include_package_data=True,
    zip_safe=False,
)