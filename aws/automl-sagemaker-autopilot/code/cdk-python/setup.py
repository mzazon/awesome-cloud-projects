"""
Setup configuration for AutoML Solutions with Amazon SageMaker Autopilot CDK Python application.

This package contains the CDK Python code for deploying infrastructure
needed for automated machine learning using SageMaker Autopilot.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="automl-sagemaker-autopilot-cdk",
    version="1.0.0",
    author="AWS Recipe Generator",
    author_email="developer@example.com",
    description="CDK Python application for AutoML Solutions with Amazon SageMaker Autopilot",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/automl-sagemaker-autopilot",
    packages=setuptools.find_packages(),
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
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[sagemaker,s3,iam,logs]>=1.28.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    keywords="aws cdk sagemaker autopilot automl machine-learning",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/automl-sagemaker-autopilot/issues",
        "Source": "https://github.com/aws-samples/automl-sagemaker-autopilot",
        "Documentation": "https://docs.aws.amazon.com/sagemaker/latest/dg/autopilot-automate-model-development.html",
    },
)