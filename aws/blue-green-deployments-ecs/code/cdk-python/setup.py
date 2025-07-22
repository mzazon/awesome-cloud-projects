"""
Setup configuration for Blue-Green Deployments CDK Python application
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read long description from README if it exists
long_description = """
# Blue-Green Deployments CDK Python Application

This CDK application implements a complete blue-green deployment infrastructure 
for containerized applications on Amazon ECS using AWS CodeDeploy.

## Features

- Amazon ECS cluster with Fargate capacity
- Application Load Balancer with blue/green target groups
- AWS CodeDeploy for automated blue-green deployments
- ECR repository for container images
- CloudWatch logging and monitoring
- VPC with public subnets across multiple AZs
- Security groups with least privilege access
- S3 bucket for deployment artifacts

## Architecture

The infrastructure creates two identical environments (blue and green) behind 
an Application Load Balancer. CodeDeploy manages the deployment process by:

1. Creating a new task set in the green environment
2. Gradually shifting traffic from blue to green
3. Monitoring health checks and rollback if issues occur
4. Terminating the blue environment after successful deployment

## Usage

```bash
# Install dependencies
pip install -r requirements.txt

# Deploy the infrastructure
cdk deploy

# Clean up resources
cdk destroy
```

## Requirements

- AWS CLI configured with appropriate permissions
- AWS CDK CLI installed
- Python 3.8 or higher
- Docker for building container images
"""

setup(
    name="blue-green-deployments-cdk",
    version="1.0.0",
    description="CDK Python application for blue-green deployments on ECS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=requirements,
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    keywords="aws cdk python blue-green deployment ecs codedeploy containers",
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    entry_points={
        "console_scripts": [
            "deploy=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)