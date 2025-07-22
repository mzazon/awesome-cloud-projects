"""
Setup configuration for Multi-Branch CI/CD Pipelines CDK Python application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="multi-branch-cicd-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for Multi-Branch CI/CD Pipelines with CodePipeline",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/multi-branch-cicd-cdk",
    packages=setuptools.find_packages(),
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
        "Topic :: Software Development :: Build Tools",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.165.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
        "typing-extensions>=4.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "multi-branch-cicd-cdk=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/example/multi-branch-cicd-cdk/issues",
        "Source": "https://github.com/example/multi-branch-cicd-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    keywords="aws cdk python codepipeline codecommit codebuild lambda eventbridge cicd devops",
    zip_safe=False,
)