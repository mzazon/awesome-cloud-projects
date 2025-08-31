"""
Setup configuration for Environment Health Check CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that deploys environment health monitoring infrastructure using Systems Manager,
SNS, Lambda, and EventBridge services.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
def read_long_description() -> str:
    """Read the README file content for package description."""
    readme_path = Path(__file__).parent / "README.md"
    if readme_path.exists():
        return readme_path.read_text(encoding="utf-8")
    return "AWS CDK Python application for environment health monitoring"

# Read requirements from requirements.txt
def read_requirements() -> list[str]:
    """Read requirements from requirements.txt file."""
    requirements_path = Path(__file__).parent / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Handle inline comments
                    req = line.split("#")[0].strip()
                    if req:
                        requirements.append(req)
            return requirements
    return [
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0"
    ]

setuptools.setup(
    # Package metadata
    name="environment-health-check-cdk",
    version="1.0.0",
    author="AWS Solutions Architecture",
    author_email="solutions@amazon.com",
    description="AWS CDK Python application for automated environment health monitoring",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"]
    },
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "mypy>=1.8.0",
            "black>=23.12.0",
            "flake8>=6.1.0",
            "aws-cdk>=2.120.0"
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # For mocking AWS services in tests
            "boto3-stubs>=1.34.0"  # Type stubs for boto3
        ]
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Developers",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Framework :: AWS CDK",
        "Topic :: Software Development :: Libraries :: Python Modules"
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "infrastructure", "monitoring", "health-check",
        "systems-manager", "sns", "lambda", "eventbridge", "compliance",
        "automation", "devops", "operations", "alerting"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Systems Manager": "https://aws.amazon.com/systems-manager/",
        "AWS SNS": "https://aws.amazon.com/sns/",
        "AWS Lambda": "https://aws.amazon.com/lambda/",
        "AWS EventBridge": "https://aws.amazon.com/eventbridge/"
    },
    
    # Entry points for command-line tools (if needed)
    entry_points={
        "console_scripts": [
            "deploy-health-check=app:main",
        ],
    },
    
    # License information
    license="Apache-2.0",
    license_files=["LICENSE"],
    
    # Additional metadata
    platforms=["any"],
    zip_safe=False,  # Required for CDK applications
    
    # Setuptools-specific options
    options={
        "egg_info": {
            "tag_build": "",
            "tag_date": False,
        }
    }
)