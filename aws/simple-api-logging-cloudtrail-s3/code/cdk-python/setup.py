"""
Setup configuration for Simple API Logging CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that implements comprehensive API logging using CloudTrail, S3, and CloudWatch.
"""

import setuptools
from typing import List, Dict, Any

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Simple API Logging with CloudTrail and S3"

# Read requirements from requirements.txt
def parse_requirements(filename: str) -> List[str]:
    """Parse requirements from requirements.txt file."""
    requirements = []
    try:
        with open(filename, "r", encoding="utf-8") as req_file:
            for line in req_file:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
    except FileNotFoundError:
        # Fallback to core requirements if file doesn't exist
        requirements = [
            "aws-cdk-lib>=2.171.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0"
        ]
    return requirements

# Package metadata
package_info: Dict[str, Any] = {
    "name": "simple-api-logging-cdk",
    "version": "1.0.0",
    "author": "AWS Recipes Team",
    "author_email": "aws-recipes@example.com",
    "description": "AWS CDK Python application for comprehensive API logging with CloudTrail and S3",
    "long_description": long_description,
    "long_description_content_type": "text/markdown",
    "url": "https://github.com/aws-recipes/simple-api-logging-cloudtrail-s3",
    "project_urls": {
        "Bug Reports": "https://github.com/aws-recipes/simple-api-logging-cloudtrail-s3/issues",
        "Source": "https://github.com/aws-recipes/simple-api-logging-cloudtrail-s3",
        "Documentation": "https://docs.aws.amazon.com/cdk/latest/guide/",
    },
    "packages": setuptools.find_packages(),
    "classifiers": [
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Logging",
        "Topic :: System :: Monitoring",
        "Topic :: Security",
        "Typing :: Typed",
    ],
    "python_requires": ">=3.8",
    "install_requires": parse_requirements("requirements.txt"),
    "extras_require": {
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-setuptools>=65.0.0",
        ],
        "security": [
            "cdk-nag>=2.28.0",
        ],
        "powertools": [
            "aws-lambda-powertools>=2.25.0",
        ],
        "all": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0", 
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-setuptools>=65.0.0",
            "cdk-nag>=2.28.0",
            "aws-lambda-powertools>=2.25.0",
        ]
    },
    "entry_points": {
        "console_scripts": [
            "simple-api-logging=app:main",
        ],
    },
    "include_package_data": True,
    "zip_safe": False,
    "keywords": [
        "aws",
        "cdk", 
        "cloudtrail",
        "s3",
        "cloudwatch",
        "logging",
        "audit",
        "security",
        "compliance",
        "monitoring",
        "infrastructure-as-code"
    ],
}

# Setup configuration
setuptools.setup(**package_info)

# Development setup instructions in docstring
__doc__ = """
Development Setup Instructions:

1. Create and activate a virtual environment:
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\\Scripts\\activate.bat

2. Install the package in development mode:
   pip install -e .

3. Install development dependencies:
   pip install -e ".[dev]"

4. Install all optional dependencies:
   pip install -e ".[all]"

5. Run tests:
   pytest

6. Format code:
   black .

7. Lint code:
   flake8 .

8. Type check:
   mypy .

Deployment Instructions:

1. Install the AWS CDK CLI:
   npm install -g aws-cdk

2. Verify CDK installation:
   cdk --version

3. Bootstrap your AWS environment (first time only):
   cdk bootstrap

4. Synthesize CloudFormation template:
   cdk synth

5. Deploy the stack:
   cdk deploy

6. View stack outputs:
   cdk deploy --outputs-file outputs.json

7. Destroy the stack when done:
   cdk destroy

Environment Variables:

Set these environment variables before deployment:
- CDK_DEFAULT_ACCOUNT: Your AWS account ID
- CDK_DEFAULT_REGION: Your preferred AWS region (e.g., us-east-1)

Security Considerations:

This CDK application implements AWS security best practices:
- S3 bucket encryption and versioning
- Least-privilege IAM policies
- CloudWatch monitoring and alerting
- Multi-region CloudTrail logging
- Source ARN conditions in policies

For production deployments, consider:
- Enabling CDK Nag security checks
- Implementing AWS Config for compliance
- Setting up log retention policies
- Configuring SNS email subscriptions
- Implementing lifecycle rules for cost optimization
"""