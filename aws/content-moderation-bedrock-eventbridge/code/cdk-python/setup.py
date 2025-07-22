"""
Setup configuration for Content Moderation CDK Application.

This setup.py file configures the Python package for the intelligent content
moderation system using Amazon Bedrock and EventBridge.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="content-moderation-cdk",
    version="1.0.0",
    
    description="Intelligent Content Moderation with Amazon Bedrock and EventBridge",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="cdk-generator@aws.amazon.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    install_requires=[
        "aws-cdk-lib>=2.150.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
    ],
    
    extras_require={
        "dev": [
            "mypy>=1.8.0",
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "black>=24.1.0",
            "flake8>=7.0.0",
            "isort>=5.13.0",
            "boto3-stubs[bedrock,s3,events,sns,lambda,iam]>=1.34.0",
        ]
    },
    
    packages=setuptools.find_packages(),
    
    entry_points={
        "console_scripts": [
            "cdk-content-moderation=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
)