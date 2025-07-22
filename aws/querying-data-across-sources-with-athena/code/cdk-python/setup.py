"""
Setup configuration for Serverless Analytics with Athena Federated Query CDK Python application

This setup.py file configures the Python package for the CDK application that deploys
infrastructure for cross-platform analytics using Amazon Athena with federated query
capabilities across RDS MySQL and DynamoDB.
"""

import os
import setuptools


def read_requirements(filename: str) -> list:
    """Read requirements from a file"""
    requirements_path = os.path.join(os.path.dirname(__file__), filename)
    with open(requirements_path, "r", encoding="utf-8") as file:
        return [
            line.strip()
            for line in file
            if line.strip() and not line.startswith("#")
        ]


def read_long_description() -> str:
    """Read the long description from README if available"""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as file:
            return file.read()
    return "CDK Python application for Serverless Analytics with Athena Federated Query"


setuptools.setup(
    name="serverless-analytics-athena-federated-query",
    version="1.0.0",
    
    description="CDK Python application for Serverless Analytics with Athena Federated Query",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="cdk-feedback@amazon.com",
    
    url="https://github.com/aws/aws-cdk",
    
    packages=setuptools.find_packages(),
    
    install_requires=read_requirements("requirements.txt"),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "athena",
        "federated-query",
        "analytics",
        "serverless",
        "mysql",
        "dynamodb",
        "lambda",
        "infrastructure",
        "cloud",
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    entry_points={
        "console_scripts": [
            "cdk-serverless-analytics=app:main",
        ],
    },
    
    include_package_data=True,
    
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
    
    zip_safe=False,
    
    # Additional metadata for PyPI
    license="Apache-2.0",
    
    # Extras for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
            "sphinx>=5.0.0",
            "moto>=4.0.0",
            "pytest-mock>=3.8.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "pytest-mock>=3.8.0",
            "factory-boy>=3.2.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-autodoc-typehints>=1.19.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
    },
    
    # Platform support
    platforms=["any"],
    
    # CDK specific configuration
    cdk_json={
        "app": "python app.py",
        "watch": {
            "include": ["**"],
            "exclude": [
                "README.md",
                "cdk*.json",
                "requirements*.txt",
                "source.bat",
                "**/__pycache__",
                "**/*.pyc",
                ".venv/**",
                ".env",
                ".pytest_cache/**",
                "**/.mypy_cache/**",
                "**/node_modules/**",
            ],
        },
        "context": {
            "@aws-cdk/aws-apigateway:usagePlanKeyOrderInsensitiveId": True,
            "@aws-cdk/core:stackRelativeExports": True,
            "@aws-cdk/aws-rds:lowercaseDbIdentifier": True,
            "@aws-cdk/aws-lambda:recognizeVersionProps": True,
            "@aws-cdk/aws-lambda:recognizeLayerVersion": True,
            "@aws-cdk/aws-cloudfront:defaultSecurityPolicyTLSv1.2_2021": True,
            "@aws-cdk/aws-apigateway:requestValidatorUniqueId": True,
            "@aws-cdk/aws-kms:aliasNameRef": True,
            "@aws-cdk/aws-autoscaling:generateLaunchTemplateInsteadOfLaunchConfig": True,
            "@aws-cdk/aws-lambda:checkSecurityGroupRules": True,
            "@aws-cdk/aws-iam:minimizePolicies": True,
            "@aws-cdk/aws-apigateway:disableCloudWatchRole": True,
            "@aws-cdk/core:enableStackNameDuplicates": True,
            "aws-cdk:enableDiffNoFail": True,
            "@aws-cdk/aws-ec2:vpnConnectionSupportsIpv6": True,
            "@aws-cdk/aws-lambda:caseSensitiveEnvVars": True,
            "@aws-cdk/aws-events:connectionSecretManagerSecretTargetEncryption": True,
            "@aws-cdk/aws-iam:standardizedServicePrincipals": True,
            "@aws-cdk/aws-ecs:disableExplicitDeploymentControllerForCircuitBreaker": True,
            "@aws-cdk/aws-iam:importedRoleStackSafeDefaultPolicyName": True,
            "@aws-cdk/aws-s3:serverAccessLogsUseBucketPolicy": True,
            "@aws-cdk/aws-route53-pattersn:useCertificate": True,
            "@aws-cdk/customresources:installLatestAwsSdkDefault": False,
            "@aws-cdk/aws-rds:databaseProxyUniqueResourceName": True,
            "@aws-cdk/aws-codedeploy:removeAlarmsFromDeploymentGroup": True,
            "@aws-cdk/aws-apigateway:authorizerChangeDeploymentLogicalId": True,
            "@aws-cdk/aws-ec2:launchTemplateDefaultUserData": True,
            "@aws-cdk/aws-secretsmanager:useAttachedSecretResourcePolicyForSecretTargetAttachments": True,
            "@aws-cdk/aws-redshift:columnId": True,
            "@aws-cdk/aws-stepfunctions-tasks:enableLoggingConfiguration": True,
            "@aws-cdk/aws-ec2:restrictDefaultSecurityGroup": True,
            "@aws-cdk/aws-apigateway:requestValidatorUniqueId": True,
            "@aws-cdk/aws-kms:aliasNameRef": True,
            "@aws-cdk/aws-autoscaling:generateLaunchTemplateInsteadOfLaunchConfig": True,
            "@aws-cdk/aws-lambda:checkSecurityGroupRules": True,
            "@aws-cdk/aws-iam:minimizePolicies": True,
            "@aws-cdk/core:validateSnapshotRemovalPolicy": True,
            "@aws-cdk/aws-codepipeline:crossAccountKeyAliasStackSafeResourceName": True,
            "@aws-cdk/aws-s3:createDefaultLoggingPolicy": True,
            "@aws-cdk/aws-sns-subscriptions:restrictSqsDescryption": True,
            "@aws-cdk/aws-apigateway:disableCloudWatchRole": True,
            "@aws-cdk/core:enablePartitionLiterals": True,
            "@aws-cdk/core:enableStackNameDuplicates": True,
            "aws-cdk:enableDiffNoFail": True,
            "@aws-cdk/core:stackRelativeExports": True,
            "@aws-cdk/aws-ecr:defaultTagImmutability": True,
            "@aws-cdk/aws-opensearch:enableOpensearchMultiAzWithStandby": True,
            "@aws-cdk/aws-events:eventsTargetQueueSameAccount": True,
            "@aws-cdk/aws-iam:standardizedServicePrincipals": True,
            "@aws-cdk/aws-ecs:disableExplicitDeploymentControllerForCircuitBreaker": True,
            "@aws-cdk/aws-events:connectionSecretManagerSecretTargetEncryption": True,
            "@aws-cdk/aws-iam:importedRoleStackSafeDefaultPolicyName": True,
            "@aws-cdk/aws-s3:serverAccessLogsUseBucketPolicy": True,
            "@aws-cdk/customresources:installLatestAwsSdkDefault": False,
        },
    },
)