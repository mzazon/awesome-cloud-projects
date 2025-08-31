"""
Setup configuration for Enterprise Identity Federation with Bedrock AgentCore CDK Application.

This setup.py file configures the Python package for the CDK application that creates
a comprehensive enterprise identity federation system integrating Bedrock AgentCore
with Cognito User Pools for SAML federation with corporate identity providers.
"""

import pathlib
from setuptools import setup, find_packages

# Read the contents of README.md for long description
HERE = pathlib.Path(__file__).parent
README = (HERE / "README.md").read_text() if (HERE / "README.md").exists() else ""

# Read requirements from requirements.txt
REQUIREMENTS = []
if (HERE / "requirements.txt").exists():
    with open(HERE / "requirements.txt", "r") as f:
        REQUIREMENTS = [
            line.strip() 
            for line in f.readlines() 
            if line.strip() and not line.startswith("#")
        ]

setup(
    name="enterprise-identity-federation-bedrock-agentcore",
    version="1.0.0",
    description="Enterprise Identity Federation with Bedrock AgentCore CDK Application",
    long_description=README,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architects",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/enterprise-identity-federation-bedrock-agentcore",
    license="Apache-2.0",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.8",
    install_requires=REQUIREMENTS,
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-enterprise-identity=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Topic :: Internet :: WWW/HTTP :: Session",
        "Operating System :: OS Independent",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud-development-kit",
        "infrastructure-as-code",
        "enterprise-identity",
        "saml-federation", 
        "oauth",
        "cognito",
        "bedrock-agentcore",
        "identity-management",
        "ai-agents",
        "enterprise-authentication",
        "security",
        "iam",
        "lambda",
    ],
    
    # Additional metadata
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/enterprise-identity-federation-bedrock-agentcore",
        "Bug Reports": "https://github.com/aws-samples/enterprise-identity-federation-bedrock-agentcore/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Cognito": "https://aws.amazon.com/cognito/",
        "AWS Bedrock": "https://aws.amazon.com/bedrock/",
    },
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.11.0",
            "flake8>=6.1.0",
            "mypy>=1.7.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
    },
)