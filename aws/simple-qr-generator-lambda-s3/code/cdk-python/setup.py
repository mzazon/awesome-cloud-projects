"""
Python package setup for QR Generator CDK application.

This setup.py file defines the package metadata and dependencies
for the CDK Python application that creates a serverless QR code
generator using AWS Lambda, S3, and API Gateway.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="qr-generator-cdk",
    version="1.0.0",
    
    description="CDK Python application for Simple QR Code Generator with Lambda and S3",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipes Team",
    author_email="aws-recipes@example.com",
    
    url="https://github.com/aws-recipes/qr-generator-cdk",
    
    packages=setuptools.find_packages(),
    
    install_requires=[
        "aws-cdk-lib==2.167.1",
        "constructs>=10.0.0,<11.0.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
        ],
        "local": [
            "boto3>=1.34.0",
            "qrcode[pil]>=7.4.2",
        ]
    },
    
    python_requires=">=3.8",
    
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Multimedia :: Graphics",
    ],
    
    keywords="aws cdk lambda s3 api-gateway qr-code serverless",
    
    project_urls={
        "Bug Reports": "https://github.com/aws-recipes/qr-generator-cdk/issues",
        "Source": "https://github.com/aws-recipes/qr-generator-cdk",
        "Documentation": "https://github.com/aws-recipes/qr-generator-cdk/blob/main/README.md",
    },
    
    entry_points={
        "console_scripts": [
            "qr-generator-cdk=app:main",
        ],
    },
)