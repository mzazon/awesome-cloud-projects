"""
Setup configuration for Event-Driven Microservices CDK Python Application

This setup.py file defines the package configuration for the CDK application,
including metadata, dependencies, and development tools integration.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        install_requires = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#") and not line.startswith("-")
        ]
else:
    install_requires = [
        "aws-cdk-lib==2.115.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.8.0",
    ]

setuptools.setup(
    name="event-driven-microservices-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for Event-Driven Microservices with EventBridge and Step Functions",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    # Package information
    packages=setuptools.find_packages(),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=install_requires,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.9.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "boto3-stubs[essential]",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto[all]>=4.2.0",  # AWS service mocking for tests
        ],
    },
    
    # Project classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud-development-kit",
        "microservices", 
        "event-driven",
        "eventbridge",
        "step-functions",
        "lambda",
        "dynamodb",
        "serverless",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "cdk-app=app:main",
        ],
    },
    
    # Package data files
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
)