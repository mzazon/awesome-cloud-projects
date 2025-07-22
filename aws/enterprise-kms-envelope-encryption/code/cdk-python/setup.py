"""
Setup configuration for Enterprise KMS Envelope Encryption CDK Application.

This setup.py file configures the Python package for the CDK application
Enterprise KMS Envelope Encryption.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Enterprise KMS envelope encryption with automated key rotation using AWS CDK"

setup(
    name="enterprise-kms-encryption-cdk",
    version="1.0.0",
    description="Enterprise KMS envelope encryption with automated key rotation using AWS CDK",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architecture",
    author_email="solutions@amazon.com",
    url="https://github.com/aws-samples/enterprise-kms-encryption",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.9",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "mypy>=1.8.0",
            "black>=23.12.0",
            "flake8>=7.0.0",
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
        ]
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Security :: Cryptography",
        "Topic :: System :: Systems Administration",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "kms",
        "encryption",
        "envelope-encryption",
        "key-rotation",
        "security",
        "enterprise",
        "lambda",
        "s3",
        "cloudformation",
    ],
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/enterprise-kms-encryption/issues",
        "Source": "https://github.com/aws-samples/enterprise-kms-encryption",
        "Documentation": "https://docs.aws.amazon.com/kms/",
    },
)