"""
Setup configuration for TCP Resource Connectivity with VPC Lattice and CloudWatch CDK application.

This setup.py file configures the Python package for the CDK application that deploys
secure TCP connectivity to RDS databases using Amazon VPC Lattice service networking
with comprehensive CloudWatch monitoring and alerting capabilities.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
requirements_path = this_directory / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, 'r') as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith('#')
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.150.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0"
    ]

setuptools.setup(
    name="tcp-resource-connectivity-lattice-cloudwatch",
    version="1.0.0",
    
    description="AWS CDK application for TCP Resource Connectivity with VPC Lattice and CloudWatch",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: System :: Networking",
        "Topic :: Database",
        "Topic :: System :: Monitoring",
        "Typing :: Typed",
    ],
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "mypy>=1.7.0",
            "pytest>=7.4.0",
            "black>=23.0.0",
            "flake8>=6.1.0",
            "pytest-cov>=4.1.0",
            "bandit>=1.7.5"
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0"
        ]
    },
    
    packages=setuptools.find_packages(),
    
    include_package_data=True,
    
    zip_safe=False,
    
    keywords=[
        "aws",
        "cdk",
        "vpc-lattice",
        "rds",
        "cloudwatch",
        "networking",
        "database",
        "monitoring",
        "tcp",
        "service-mesh",
        "infrastructure-as-code"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "VPC Lattice": "https://docs.aws.amazon.com/vpc-lattice/",
        "CloudWatch": "https://docs.aws.amazon.com/cloudwatch/",
        "RDS": "https://docs.aws.amazon.com/rds/"
    },
    
    entry_points={
        "console_scripts": [
            "tcp-connectivity-deploy=app:main",
        ],
    },
)