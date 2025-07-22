"""
Setup configuration for Document Processing Pipeline CDK application

This package contains the AWS CDK Python code for deploying a complete
document processing pipeline using Amazon Textract and Step Functions.
"""

from setuptools import setup, find_packages

# Read the contents of requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file"""
    with open(filename, 'r') as f:
        return [
            line.strip() for line in f 
            if line.strip() and not line.startswith('#')
        ]

# Read the contents of README.md if it exists
def read_long_description():
    """Read long description from README.md"""
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return "Document Processing Pipeline CDK Application"

setup(
    name="document-processing-pipeline-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="example@example.com",
    description="AWS CDK Python application for document processing pipeline",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/document-processing-pipeline",
    packages=find_packages(),
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    python_requires=">=3.8",
    install_requires=parse_requirements("requirements.txt"),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "isort>=5.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3>=1.26.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-pipeline=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/document-processing-pipeline/issues",
        "Source": "https://github.com/aws-samples/document-processing-pipeline",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "document-processing",
        "textract",
        "step-functions",
        "serverless",
        "lambda",
        "s3",
        "dynamodb",
        "sns",
    ],
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    zip_safe=False,
)