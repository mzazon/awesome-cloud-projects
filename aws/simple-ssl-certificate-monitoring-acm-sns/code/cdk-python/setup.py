"""
Setup configuration for SSL Certificate Monitoring CDK Python Application

This setup.py file configures the Python package for the SSL certificate
monitoring solution using AWS CDK. The application monitors SSL certificates
for expiration and sends email notifications through SNS.
"""

import setuptools
from pathlib import Path

# Read the contents of README file
this_directory = Path(__file__).parent
long_description = ""
readme_path = this_directory / "README.md"
if readme_path.exists():
    long_description = readme_path.read_text(encoding='utf-8')

setuptools.setup(
    name="ssl-certificate-monitoring-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for SSL certificate expiration monitoring",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Python Recipe",
    author_email="admin@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: DevOps Engineers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: System :: Monitoring",
        "Topic :: Security :: Cryptography",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    
    install_requires=[
        "aws-cdk-lib>=2.164.1,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.35.0",
        "botocore>=1.35.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.8.0",
            "types-boto3>=1.0.0",
            "boto3-stubs[acm,cloudwatch,sns]>=1.35.0",
        ]
    },
    
    packages=setuptools.find_packages(),
    
    keywords=[
        "aws", 
        "cdk", 
        "ssl", 
        "certificate", 
        "monitoring", 
        "acm", 
        "cloudwatch", 
        "sns", 
        "security",
        "infrastructure-as-code"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
    
    entry_points={
        "console_scripts": [
            "ssl-cert-monitor=app:main",
        ],
    },
    
    zip_safe=False,
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)