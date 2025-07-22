"""
Setup configuration for DNS Security Monitoring CDK Application

This setup file configures the Python package for the DNS Security Monitoring 
CDK application, including dependencies, metadata, and installation requirements.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file
    
    Returns:
        List of package requirements
    """
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    if "#" in line:
                        line = line.split("#")[0].strip()
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib>=2.120.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.26.0",
            "typing-extensions>=4.0.0"
        ]


def read_long_description() -> str:
    """
    Read long description from README or return default description
    
    Returns:
        Long description for the package
    """
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return """
# DNS Security Monitoring CDK Application

This AWS CDK Python application implements automated DNS security monitoring using:

- **Route 53 Resolver DNS Firewall** for threat filtering and domain blocking
- **CloudWatch** for metrics analysis, logging, and alerting  
- **Lambda** for automated security response and incident handling
- **SNS** for real-time security notifications and alerts

## Features

- Comprehensive DNS threat detection and blocking
- Real-time monitoring of DNS query patterns
- Automated response to security incidents
- Scalable architecture following AWS best practices
- Infrastructure as Code with AWS CDK

## Deployment

1. Install dependencies: `pip install -r requirements.txt`
2. Configure AWS credentials and region
3. Deploy the stack: `cdk deploy`

## Security Benefits

- Proactive DNS-based threat prevention
- Real-time security monitoring and alerting
- Automated incident response capabilities
- Comprehensive audit logging for compliance
- Cost-effective serverless architecture
"""


setuptools.setup(
    # Package Metadata
    name="dns-security-monitoring-cdk",
    version="1.0.0",
    author="AWS Recipes Team",
    author_email="recipes@example.com",
    description="AWS CDK application for automated DNS security monitoring with Route 53 Resolver DNS Firewall",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/recipes",
    
    # Package Configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    zip_safe=False,
    
    # Python Version Requirements
    python_requires=">=3.8",
    
    # Package Dependencies
    install_requires=read_requirements(),
    
    # Optional Dependencies for Development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0", 
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0"
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0"
        ]
    },
    
    # Package Classifications
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Topic :: Internet :: Name Service (DNS)",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2"
    ],
    
    # Keywords for Package Discovery
    keywords=[
        "aws", "cdk", "dns", "security", "monitoring", 
        "route53", "firewall", "cloudwatch", "lambda",
        "infrastructure", "automation", "threat-detection"
    ],
    
    # Entry Points for CLI Tools (if needed)
    entry_points={
        "console_scripts": [
            "dns-security-deploy=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "Documentation": "https://github.com/aws-samples/recipes/tree/main/aws/implementing-automated-dns-security-monitoring-with-route-53-resolver-dns-firewall-and-cloudwatch",
        "Source": "https://github.com/aws-samples/recipes",
    },
    
    # License Information
    license="Apache-2.0",
    license_files=["LICENSE"],
)