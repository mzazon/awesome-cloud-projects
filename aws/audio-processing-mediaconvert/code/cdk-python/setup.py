"""
Setup configuration for AWS CDK Audio Processing Pipeline application.

This setup.py file configures the Python package for the audio processing pipeline
built with AWS CDK, including all necessary dependencies and metadata.
"""

from setuptools import setup, find_packages

# Read the contents of README file
from pathlib import Path
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

setup(
    name="audio-processing-pipeline-cdk",
    version="1.0.0",
    description="AWS CDK application for Audio Processing Pipelines with MediaConvert",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Recipe Generator",
    author_email="support@aws.amazon.com",
    url="https://github.com/aws/audio-processing-pipeline-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.124.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pylint>=2.15.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "audio-processing-pipeline=app:main",
        ],
    },
    
    # Project metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "audio",
        "processing",
        "mediaconvert",
        "pipeline",
        "serverless",
        "lambda",
        "s3",
        "cloudformation",
        "infrastructure",
        "iac",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/audio-processing-pipeline-cdk/issues",
        "Source": "https://github.com/aws/audio-processing-pipeline-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS MediaConvert": "https://docs.aws.amazon.com/mediaconvert/",
    },
)