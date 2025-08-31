"""
Setup configuration for VPC Lattice Health Monitoring CDK Application

This setup.py file configures the Python package for the AWS CDK application
that deploys a comprehensive health monitoring system using VPC Lattice,
CloudWatch, and Lambda for automated remediation.

Author: AWS CDK Generator
Version: 1.0.0
License: MIT
"""

import setuptools
from typing import List


def get_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Returns:
        List of package requirements
    """
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.155.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "cdk-nag>=2.28.0,<3.0.0",
            "boto3>=1.34.0,<2.0.0"
        ]


def get_long_description() -> str:
    """
    Get long description from README if available.
    
    Returns:
        Long description text
    """
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return """
        # VPC Lattice Health Monitoring CDK Application
        
        This AWS CDK application deploys a comprehensive health monitoring system
        using VPC Lattice service metrics, CloudWatch alarms, and Lambda functions
        for automated remediation and alerting.
        
        ## Features
        
        - VPC Lattice service network and service configuration
        - Target groups with configurable health checks
        - CloudWatch alarms for automated monitoring
        - Lambda-based auto-remediation capabilities
        - SNS notifications for operations teams
        - CloudWatch dashboard for centralized monitoring
        
        ## Architecture
        
        The solution monitors key health indicators including HTTP error rates,
        request timeouts, and response times, automatically triggering remediation
        actions and notifications when thresholds are breached.
        """


setuptools.setup(
    name="vpc-lattice-health-monitoring",
    version="1.0.0",
    
    description="AWS CDK application for VPC Lattice health monitoring with CloudWatch and auto-remediation",
    long_description=get_long_description(),
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="aws-cdk-generator@example.com",
    
    url="https://github.com/aws-samples/vpc-lattice-health-monitoring",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=get_requirements(),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: System :: Monitoring",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "vpc-lattice",
        "cloudwatch",
        "monitoring",
        "health-checks",
        "auto-remediation",
        "observability",
        "infrastructure-as-code",
        "serverless",
        "lambda",
        "sns",
        "alarms"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/vpc-lattice/",
        "Source": "https://github.com/aws-samples/vpc-lattice-health-monitoring",
        "Bug Tracker": "https://github.com/aws-samples/vpc-lattice-health-monitoring/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "VPC Lattice": "https://aws.amazon.com/vpc/lattice/",
        "CloudWatch": "https://aws.amazon.com/cloudwatch/"
    },
    
    extras_require={
        "dev": [
            "pytest>=7.4.0,<8.0.0",
            "pytest-cov>=4.1.0,<5.0.0",
            "black>=23.0.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.5.0,<2.0.0",
            "safety>=3.0.0,<4.0.0",
            "bandit>=1.7.0,<2.0.0"
        ],
        "typing": [
            "boto3-stubs[essential]>=1.34.0,<2.0.0",
            "types-requests>=2.31.0,<3.0.0"
        ],
        "security": [
            "cdk-nag>=2.28.0,<3.0.0",
            "safety>=3.0.0,<4.0.0",
            "bandit>=1.7.0,<2.0.0"
        ]
    },
    
    entry_points={
        "console_scripts": [
            "deploy-health-monitoring=app:main",
        ],
    },
    
    include_package_data=True,
    zip_safe=False,
    
    # Package metadata for better discoverability
    license="MIT",
    platforms=["any"],
    
    # CDK specific metadata
    cdk_version=">=2.155.0,<3.0.0",
    
    # Security and compliance
    download_url="https://github.com/aws-samples/vpc-lattice-health-monitoring/archive/v1.0.0.tar.gz",
    
    # Additional metadata
    maintainer="AWS Solutions Architecture Team",
    maintainer_email="aws-solutions@amazon.com"
)