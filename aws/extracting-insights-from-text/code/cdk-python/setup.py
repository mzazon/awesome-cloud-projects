"""
Setup configuration for Amazon Comprehend NLP Solution CDK Python application.

This setup.py file configures the Python package for the CDK application that
deploys a complete natural language processing solution using Amazon Comprehend,
AWS Lambda, Amazon S3, and Amazon EventBridge.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="comprehend-nlp-solution",
    version="1.0.0",
    author="AWS Recipe Generator",
    author_email="recipes@example.com",
    description="CDK Python application for Amazon Comprehend NLP Solution",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/recipes",
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: Text Processing :: Linguistic",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.115.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    extras_require={
        "dev": [
            "mypy>=1.7.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "python-dotenv>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "comprehend-nlp=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "comprehend",
        "nlp",
        "natural-language-processing",
        "lambda",
        "s3",
        "eventbridge",
        "sentiment-analysis",
        "entity-detection",
        "machine-learning",
        "artificial-intelligence",
        "text-analysis",
        "serverless",
    ],
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/recipes/issues",
        "Documentation": "https://docs.aws.amazon.com/comprehend/",
        "Source": "https://github.com/aws-samples/recipes",
    },
)