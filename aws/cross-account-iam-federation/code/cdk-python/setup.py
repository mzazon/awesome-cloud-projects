"""
Setup configuration for Advanced Cross-Account IAM Role Federation CDK Application

This setup.py file configures the Python package for the CDK application
implementing advanced cross-account IAM role federation with comprehensive
security controls and audit capabilities.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="advanced-cross-account-iam-federation",
    version="1.0.0",
    author="AWS CDK Recipe Generator",
    author_email="contact@example.com",
    description="Advanced Cross-Account IAM Role Federation with AWS CDK",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/advanced-cross-account-iam-federation",
    project_urls={
        "Bug Tracker": "https://github.com/example/advanced-cross-account-iam-federation/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/latest/guide/",
        "Source": "https://github.com/example/advanced-cross-account-iam-federation",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Typing :: Typed",
    ],
    package_dir={"": "src"},
    packages=setuptools.find_packages(where="src"),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.168.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "bandit>=1.7.4",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "type-hints": [
            "boto3-stubs[essential]>=1.26.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-cross-account-federation=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "iam",
        "cross-account",
        "federation",
        "security",
        "saml",
        "cloudtrail",
        "lambda",
        "automation",
        "compliance",
        "audit",
        "enterprise",
        "zero-trust",
    ],
    include_package_data=True,
    zip_safe=False,
)