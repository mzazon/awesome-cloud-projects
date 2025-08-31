"""
Setup configuration for EC2 Launch Templates with Auto Scaling CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="ec2-launch-template-auto-scaling-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for EC2 Launch Templates with Auto Scaling",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib==2.170.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "boto3>=1.34.0",
            "botocore>=1.34.0",
            "types-boto3>=1.0.2",
        ],
    },
    entry_points={
        "console_scripts": [
            "ec2-autoscaling-app=app:main",
        ],
    },
    keywords="aws cdk ec2 autoscaling launch-template infrastructure",
    include_package_data=True,
    zip_safe=False,
)