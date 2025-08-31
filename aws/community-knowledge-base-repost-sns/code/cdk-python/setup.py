"""
Setup configuration for Community Knowledge Base CDK Python application.

This setup.py file configures the Python package for the CDK application that creates
infrastructure for a Community Knowledge Base with AWS re:Post Private and SNS notifications.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="community-knowledge-base-cdk",
    version="1.0.0",
    author="Enterprise DevOps Team",
    author_email="devops@company.com",
    description="AWS CDK Python application for Community Knowledge Base with re:Post Private and SNS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/company/community-knowledge-base-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/company/community-knowledge-base-cdk/issues",
        "Documentation": "https://github.com/company/community-knowledge-base-cdk/wiki",
    },
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "boto3>=1.34.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "knowledge-base-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "knowledge-base",
        "sns",
        "repost",
        "notifications",
        "enterprise",
    ],
)