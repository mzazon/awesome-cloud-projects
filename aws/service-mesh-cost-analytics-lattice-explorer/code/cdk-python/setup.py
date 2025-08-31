"""
Setup configuration for VPC Lattice Cost Analytics CDK Python application.

This setup file configures the Python package for the VPC Lattice cost analytics
platform, including all necessary dependencies and metadata for proper deployment
and distribution.

Author: AWS CDK Generator
Version: 1.0
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.165.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.8.0"
    ]

setuptools.setup(
    name="vpc-lattice-cost-analytics",
    version="1.0.0",
    description="AWS CDK Python application for VPC Lattice cost analytics platform",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="aws-solutions@example.com",
    
    # Package configuration
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.2",
            "boto3-stubs[essential]>=1.29.7",
            "mypy>=1.5.1",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "aws-lambda-powertools[all]>=2.28.0"
        ],
        "powertools": [
            "aws-lambda-powertools[all]>=2.28.0"
        ]
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "Operating System :: OS Independent",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws", "cdk", "vpc-lattice", "cost-analytics", "service-mesh",
        "cloudwatch", "lambda", "s3", "cost-explorer", "monitoring",
        "infrastructure-as-code", "serverless", "optimization"
    ],
    
    # Entry points for command-line tools (if any)
    entry_points={
        "console_scripts": [
            # Add CLI tools here if needed
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/vpc-lattice-cost-analytics/issues",
        "Source": "https://github.com/aws-samples/vpc-lattice-cost-analytics",
        "Documentation": "https://docs.aws.amazon.com/vpc-lattice/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # Security and licensing
    license="Apache-2.0",
    license_files=["LICENSE"],
    
    # Platform compatibility
    platforms=["any"],
    
    # Zip safety
    zip_safe=False,
)