"""
Setup configuration for Database Backup and Point-in-Time Recovery CDK Python application.

This package creates a comprehensive backup and recovery solution for Amazon RDS
using AWS CDK Python, including automated backups, cross-region replication,
and monitoring capabilities.
"""

from setuptools import setup, find_packages

# Read the requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

# Read the README content for long description
long_description = """
# Database Backup and Point-in-Time Recovery CDK Application

This CDK Python application implements a comprehensive database backup and recovery
strategy using Amazon RDS, AWS Backup, and cross-region replication capabilities.

## Features

- **RDS Instance**: MySQL database with automated backups and encryption
- **AWS Backup Integration**: Centralized backup management with lifecycle policies
- **Cross-Region Replication**: Disaster recovery with regional backup copies
- **KMS Encryption**: Customer-managed encryption keys for data protection
- **Monitoring & Alerting**: CloudWatch alarms and SNS notifications
- **IAM Security**: Least privilege access with service-specific roles
- **VPC Isolation**: Secure networking with private subnets

## Architecture Components

### Primary Stack (DatabaseBackupRecoveryStack)
- RDS MySQL instance with automated backups
- AWS Backup vault with KMS encryption
- Backup plan with daily and weekly schedules
- CloudWatch monitoring and SNS alerting
- IAM roles and policies for backup operations

### DR Stack (CrossRegionReplicationStack)
- Cross-region backup vault
- Separate KMS key for DR region
- Support for cross-region backup replication

## Usage

```python
from aws_cdk import App, Environment
from app import DatabaseBackupRecoveryStack, CrossRegionReplicationStack

app = App()

# Deploy primary stack
primary_stack = DatabaseBackupRecoveryStack(
    app, "DatabaseBackupRecoveryStack",
    env=Environment(region="us-east-1")
)

# Deploy DR stack
dr_stack = CrossRegionReplicationStack(
    app, "CrossRegionReplicationStack",
    primary_region="us-east-1",
    primary_kms_key_arn=primary_stack.backup_kms_key.key_arn,
    env=Environment(region="us-west-2")
)

app.synth()
```

## Security Features

- Customer-managed KMS keys for encryption
- IAM roles with least privilege access
- VPC isolation for database instances
- Security groups with minimal required access
- Encrypted backups and snapshots
- Cross-region encrypted replication

## Monitoring & Alerting

- CloudWatch alarms for backup failures
- SNS notifications for operational alerts
- CloudWatch Logs for database activity
- Backup job status monitoring

## Cost Optimization

- Intelligent backup lifecycle management
- Automated transition to cold storage
- Configurable retention periods
- Resource tagging for cost allocation

## Compliance & Governance

- Tag-based resource management
- Audit trail through CloudTrail integration
- Backup compliance reporting
- Cross-account access policies

## Deployment

1. Install dependencies: `pip install -r requirements.txt`
2. Configure AWS credentials
3. Deploy primary stack: `cdk deploy DatabaseBackupRecoveryStack`
4. Deploy DR stack: `cdk deploy CrossRegionReplicationStack`

## Testing

Run the test suite with: `pytest tests/`

## Documentation

Generate documentation with: `sphinx-build -b html docs/ docs/_build/html`
"""

setup(
    name="database-backup-recovery-cdk",
    version="1.0.0",
    description="CDK Python application for database backup and point-in-time recovery",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/database-backup-recovery-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Systems Administration",
        "Topic :: Database",
        "Topic :: Security :: Cryptography",
        "Environment :: Console",
        "Operating System :: OS Independent",
    ],
    keywords=[
        "aws",
        "cdk",
        "python",
        "database",
        "backup",
        "recovery",
        "rds",
        "mysql",
        "disaster-recovery",
        "point-in-time-recovery",
        "aws-backup",
        "kms",
        "encryption",
        "cross-region",
        "replication",
        "monitoring",
        "cloudwatch",
        "sns",
        "iam",
        "security",
        "compliance",
        "infrastructure-as-code",
        "devops",
        "automation"
    ],
    python_requires=">=3.9",
    install_requires=requirements,
    extras_require={
        "dev": [
            "mypy>=1.8.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "bandit>=1.7.0",
            "safety>=3.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-backup-solution=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/database-backup-recovery-cdk/issues",
        "Source": "https://github.com/aws-samples/database-backup-recovery-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS Backup": "https://docs.aws.amazon.com/aws-backup/",
        "Amazon RDS": "https://docs.aws.amazon.com/rds/",
    },
)