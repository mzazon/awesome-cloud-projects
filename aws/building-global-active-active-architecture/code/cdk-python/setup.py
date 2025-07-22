"""
Setup configuration for Multi-Region Active-Active Applications with AWS Global Accelerator
CDK Python package.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="global-accelerator-app-cdk",
    version="1.0.0",
    author="AWS Solutions Team",
    author_email="solutions@amazon.com",
    description="CDK Python implementation for Multi-Region Active-Active Applications with AWS Global Accelerator",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/global-accelerator-app-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/global-accelerator-app-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/v2/guide/",
        "Source Code": "https://github.com/aws-samples/global-accelerator-app-cdk",
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.164.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "python-dotenv>=0.19.0",
        "pydantic>=1.8.0",
    ],
    extras_require={
        "dev": [
            "pytest>=6.0.0",
            "pytest-cov>=2.10.0",
            "black>=21.0.0",
            "flake8>=3.8.0",
            "mypy>=0.812",
            "boto3-stubs[dynamodb,lambda,elbv2,globalaccelerator,iam,ec2]>=1.34.0",
        ],
        "cli": [
            "awscli>=1.32.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-global-app=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "global-accelerator",
        "dynamodb",
        "lambda",
        "multi-region",
        "active-active",
        "load-balancer",
        "serverless",
        "infrastructure-as-code",
    ],
    zip_safe=False,
)