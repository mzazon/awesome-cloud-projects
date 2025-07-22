"""
Setup configuration for Multi-Region Event Replication CDK Python application

This setup.py file configures the CDK Python application as a package
with all necessary dependencies and metadata.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "Multi-Region Event Replication with EventBridge using AWS CDK Python"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.118.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setuptools.setup(
    name="multi-region-event-replication-eventbridge",
    version="1.0.0",
    author="AWS CDK Python Generator",
    author_email="support@example.com",
    description="Multi-Region Event Replication with EventBridge using AWS CDK Python",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/multi-region-event-replication",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/multi-region-event-replication/issues",
        "Documentation": "https://docs.aws.amazon.com/eventbridge/",
        "Source": "https://github.com/aws-samples/multi-region-event-replication",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: System :: Systems Administration",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "types-boto3>=1.0.0",
        ],
        "cli": [
            "awscli>=1.32.0",
            "boto3>=1.26.0",
            "botocore>=1.29.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-multi-region-eventbridge=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "eventbridge",
        "multi-region",
        "disaster-recovery",
        "event-replication",
        "lambda",
        "cloudwatch",
        "serverless",
    ],
    include_package_data=True,
    zip_safe=False,
)