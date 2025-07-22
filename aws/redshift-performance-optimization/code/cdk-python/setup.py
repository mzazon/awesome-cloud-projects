"""
Setup configuration for Redshift Performance Optimization CDK Python application.

This package provides a complete Infrastructure as Code solution for optimizing
Amazon Redshift performance using AWS CDK Python constructs.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
long_description = """
# Redshift Performance Optimization CDK Application

This AWS CDK Python application deploys a comprehensive performance optimization
infrastructure for Amazon Redshift, including:

- **Automated Workload Management (WLM)** configuration with concurrency scaling
- **CloudWatch monitoring dashboard** with key performance metrics
- **Intelligent alerting system** using SNS for performance threshold breaches
- **Automated maintenance Lambda function** for VACUUM and ANALYZE operations
- **Scheduled maintenance** using EventBridge for consistent performance
- **Secure credential management** using AWS Secrets Manager

## Features

### Performance Monitoring
- Real-time CloudWatch dashboard with cluster, queue, and storage metrics
- Configurable CloudWatch alarms for CPU, queue length, and disk usage
- SNS notifications for performance threshold breaches

### Automated Maintenance
- Intelligent VACUUM operations targeting tables with >10% unsorted data
- Automatic ANALYZE operations to update table statistics
- Serverless Lambda function with built-in error handling and logging
- EventBridge-scheduled execution during off-peak hours

### Workload Management
- Optimized parameter group with automatic WLM configuration
- Concurrency scaling enabled for handling query spikes
- Performance-tuned settings based on AWS best practices

### Security & Compliance
- AWS Secrets Manager integration for secure credential storage
- IAM roles with least privilege access
- VPC-compatible Lambda function configuration
- Encryption at rest and in transit

## Prerequisites

- AWS CDK v2.110.0 or later
- Python 3.8 or later
- AWS CLI configured with appropriate permissions
- Existing Redshift cluster (cluster identifier required)

## Quick Start

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Configure context parameters:
   ```bash
   cdk context --set cluster_identifier=your-cluster-name
   cdk context --set notification_email=admin@example.com
   ```

3. Deploy the stack:
   ```bash
   cdk deploy
   ```

## Configuration

The application supports the following context parameters:

- `cluster_identifier`: Name of your existing Redshift cluster
- `notification_email`: Email address for performance alerts
- `maintenance_schedule`: Cron expression for maintenance schedule (default: daily at 2 AM)

## Architecture

The solution implements a multi-layered performance optimization approach:

1. **Monitoring Layer**: CloudWatch metrics and dashboards provide visibility
2. **Alerting Layer**: SNS-based notifications for threshold breaches
3. **Automation Layer**: Lambda-based maintenance with intelligent targeting
4. **Configuration Layer**: Optimized parameter groups and WLM settings

## Post-Deployment Steps

1. Update the Secrets Manager secret with your Redshift credentials
2. Apply the generated parameter group to your Redshift cluster
3. Confirm SNS subscription for email notifications
4. Monitor the CloudWatch dashboard for performance metrics

## Cost Considerations

This solution is designed to be cost-effective:
- Lambda function runs only during scheduled maintenance
- CloudWatch alarms incur minimal charges
- SNS notifications are usage-based
- No additional compute resources required

Estimated monthly cost: $5-15 USD for typical usage patterns.

## Support

For issues or questions:
- Review CloudWatch logs for Lambda function execution details
- Check SNS topic subscription status
- Verify IAM permissions for Redshift access
- Consult AWS Redshift documentation for performance best practices
"""

setuptools.setup(
    name="redshift-performance-optimization",
    version="1.0.0",
    
    description="AWS CDK Python application for comprehensive Redshift performance optimization",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture Team",
    author_email="solutions-architecture@example.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=[
        "aws-cdk-lib>=2.110.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "psycopg2-binary>=2.9.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "mypy>=1.0.0",
            "flake8>=5.0.0",
            "boto3-stubs[redshift,cloudwatch,sns,lambda,events,iam,logs,secretsmanager]>=1.26.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: DevOps Engineers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: System :: Systems Administration",
        "Topic :: Database",
        "Topic :: System :: Monitoring",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws", "cdk", "redshift", "performance", "optimization", 
        "monitoring", "automation", "data-warehouse", "analytics",
        "cloudwatch", "lambda", "infrastructure-as-code"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/redshift/",
        "Source": "https://github.com/aws-samples/redshift-performance-optimization",
        "Bug Reports": "https://github.com/aws-samples/redshift-performance-optimization/issues",
        "AWS CDK": "https://docs.aws.amazon.com/cdk/",
        "Amazon Redshift": "https://aws.amazon.com/redshift/",
    },
    
    zip_safe=False,
    include_package_data=True,
)