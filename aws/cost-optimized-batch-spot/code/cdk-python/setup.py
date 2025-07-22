"""
Setup configuration for Cost-Optimized Batch Processing CDK Python application.

This package provides Infrastructure as Code (IaC) for deploying a complete
batch processing solution using AWS Batch with EC2 Spot Instances for
cost optimization.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [
        line.strip() 
        for line in f 
        if line.strip() and not line.startswith("#")
    ]

# Read long description from README if it exists
long_description = """
# Cost-Optimized Batch Processing with AWS Batch and Spot Instances

This CDK Python application creates a complete infrastructure for cost-optimized 
batch processing using AWS Batch with EC2 Spot Instances.

## Features

- **Cost Optimization**: Uses EC2 Spot Instances with up to 90% cost savings
- **Fault Tolerance**: Intelligent retry strategies for Spot interruptions
- **Auto Scaling**: Automatic scaling from 0 to 256 vCPUs based on demand
- **Container Support**: ECR repository for containerized batch applications
- **Monitoring**: CloudWatch logging and monitoring integration
- **Security**: IAM roles with least privilege access
- **Storage**: S3 bucket for job artifacts with lifecycle policies

## Architecture

- VPC with public and private subnets
- ECR repository for container images
- AWS Batch compute environment with Spot instances
- Job queue and job definition with retry strategies
- CloudWatch log group for job monitoring
- S3 bucket for job artifacts

## Usage

```bash
# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# Destroy the stack
cdk destroy
```

## Configuration

The stack can be customized through CDK context variables:
- `account`: AWS account ID
- `region`: AWS region

## Cost Optimization Features

1. **Spot Instance Allocation**: Uses SPOT_CAPACITY_OPTIMIZED strategy
2. **Mixed Instance Types**: Supports multiple instance families
3. **Intelligent Scaling**: Scales down to 0 when no jobs are running
4. **Lifecycle Policies**: Automatic cleanup of old resources
5. **Bid Percentage**: Maximum 80% of On-Demand pricing
"""

setup(
    name="cost-optimized-batch-processing-cdk",
    version="1.0.0",
    
    description="CDK Python application for cost-optimized batch processing with AWS Batch and Spot Instances",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    
    url="https://github.com/aws/aws-cdk",
    
    packages=find_packages(),
    
    install_requires=requirements,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    keywords="aws cdk batch spot-instances cost-optimization infrastructure-as-code",
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    entry_points={
        "console_scripts": [
            "batch-app=app:main",
        ],
    },
    
    include_package_data=True,
    
    zip_safe=False,
)