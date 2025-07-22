"""
Setup configuration for AWS CDK Python Chatbot Application

This setup.py file configures the Python package for the Amazon Lex chatbot
development recipe. It includes all necessary dependencies and metadata for
proper package management and deployment.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="aws-lex-chatbot-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="dev@example.com",
    description="AWS CDK Python application for Amazon Lex chatbot development",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-lex-chatbot-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/aws-lex-chatbot-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/lexv2/latest/dg/",
        "Source Code": "https://github.com/aws-samples/aws-lex-chatbot-cdk",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
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
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib==2.115.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=22.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "flake8>=5.0.0",
            "autopep8>=2.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-chatbot=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "amazon-lex",
        "chatbot",
        "conversational-ai",
        "customer-service",
        "infrastructure-as-code",
        "serverless",
        "lambda",
        "dynamodb",
    ],
    include_package_data=True,
    zip_safe=False,
)