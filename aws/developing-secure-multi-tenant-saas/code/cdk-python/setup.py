"""
Setup configuration for Multi-Tenant SaaS CDK Python Application

This setup.py file configures the Python package for the CDK application
that deploys a comprehensive multi-tenant SaaS platform using AWS services.
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Multi-Tenant SaaS Application CDK Python Stack"

# Read requirements from requirements.txt
def read_requirements():
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="multitenant-saas-cdk",
    version="1.0.0",
    description="CDK Python stack for multi-tenant SaaS application with Amplify and fine-grained authorization",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="solutions@aws.amazon.com",
    url="https://github.com/aws-samples/multitenant-saas-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for different environments
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-mock>=3.12.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.8.0",
            "pre-commit>=3.6.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-mock>=3.12.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "boto3-stubs[essential]>=1.35.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
            "myst-parser>=2.0.0",
        ],
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-multitenant-saas=app:main",
        ],
    },
    
    # Package classifiers
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
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Office/Business :: Enterprise",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "multi-tenant",
        "saas",
        "amplify",
        "appsync",
        "cognito",
        "dynamodb",
        "lambda",
        "serverless",
        "authorization",
        "infrastructure",
        "cloud",
        "python"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/multitenant-saas-cdk",
        "Tracker": "https://github.com/aws-samples/multitenant-saas-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Amplify": "https://aws.amazon.com/amplify/",
        "AWS AppSync": "https://aws.amazon.com/appsync/",
    },
    
    # Package data to include
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yml",
            "*.yaml",
            "*.json",
            "graphql/*.graphql",
            "lambda/**/*.py",
            "templates/**/*.vtl",
            "templates/**/*.json",
        ],
    },
    
    # Manifest template for additional files
    # This is handled by MANIFEST.in if needed
)

# Additional setup for CDK-specific configuration
if __name__ == "__main__":
    print("Multi-Tenant SaaS CDK Python Setup")
    print("==================================")
    print("")
    print("This CDK application deploys a production-ready multi-tenant SaaS platform with:")
    print("  ✓ AWS Amplify for frontend hosting and CI/CD")
    print("  ✓ Amazon Cognito for tenant-aware authentication")
    print("  ✓ AWS AppSync for GraphQL API with fine-grained authorization")
    print("  ✓ Amazon DynamoDB for tenant-isolated data storage")
    print("  ✓ AWS Lambda for business logic and tenant management")
    print("  ✓ Amazon S3 for tenant-specific file storage")
    print("  ✓ Amazon CloudWatch for monitoring and analytics")
    print("")
    print("Prerequisites:")
    print("  • AWS CLI configured with appropriate permissions")
    print("  • Node.js 18+ installed for CDK CLI")
    print("  • Python 3.8+ installed")
    print("  • AWS CDK CLI installed (npm install -g aws-cdk)")
    print("")
    print("Quick Start:")
    print("  1. pip install -r requirements.txt")
    print("  2. cdk bootstrap (if first time)")
    print("  3. cdk deploy")
    print("")
    print("For more information, see the README.md file.")