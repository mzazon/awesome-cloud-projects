"""
Setup configuration for Intelligent Document Processing CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages

# Read the contents of requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read the contents of README.md if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    # Intelligent Document Processing with Amazon Textract
    
    This CDK application deploys infrastructure for intelligent document processing
    using Amazon Textract, S3, and Lambda services.
    """

setup(
    name="intelligent-document-processing-textract",
    version="1.1.0",
    author="AWS Recipe Generator",
    author_email="support@aws.amazon.com",
    description="CDK Python application for intelligent document processing with Amazon Textract",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/intelligent-document-processing-textract",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
        "Topic :: Office/Business :: Office Suites",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    python_requires=">=3.9",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "mypy>=1.8.0",
            "pre-commit>=3.6.0",
            "types-boto3>=1.0.2",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=2.0.0",
            "sphinx-autodoc-typehints>=1.25.0",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "textract",
        "document-processing",
        "machine-learning",
        "ocr",
        "serverless",
        "lambda",
        "s3",
        "intelligent-document-processing",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/intelligent-document-processing-textract/issues",
        "Source": "https://github.com/aws-samples/intelligent-document-processing-textract",
        "Documentation": "https://docs.aws.amazon.com/textract/",
        "AWS CDK": "https://docs.aws.amazon.com/cdk/",
        "Recipe": "https://github.com/aws-samples/recipes/tree/main/aws/intelligent-document-processing-amazon-textract",
    },
    include_package_data=True,
    zip_safe=False,
)