"""
Setup configuration for Text-to-Speech Applications with Amazon Polly CDK Python project
"""

from setuptools import setup, find_packages

# Read the contents of README file
with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="text-to-speech-polly-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for text-to-speech applications using Amazon Polly",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/text-to-speech-polly-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Multimedia :: Sound/Audio :: Speech",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0",
        "constructs>=10.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "boto3": [
            "boto3>=1.26.0",
            "boto3-stubs[polly,s3,iam]>=1.26.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-polly-stack=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/text-to-speech-polly-cdk/issues",
        "Source": "https://github.com/aws-samples/text-to-speech-polly-cdk",
        "Documentation": "https://docs.aws.amazon.com/polly/",
    },
)