"""
Setup configuration for AWS CDK Python application
GraphQL APIs with AppSync and DynamoDB
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements_file = this_directory / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, 'r') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Handle version constraints
                    if '>=' in line or '==' in line or '<' in line:
                        requirements.append(line)
                    else:
                        requirements.append(line)
            return requirements
    return []

setuptools.setup(
    name="graphql-appsync-dynamodb",
    version="1.0.0",
    
    description="AWS CDK Python application for GraphQL APIs with AppSync and DynamoDB",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    url="https://github.com/aws-samples/graphql-appsync-dynamodb",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
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
    
    packages=setuptools.find_packages(),
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "testing": [
            "moto>=4.0.0",
            "pytest-mock>=3.0.0",
            "responses>=0.20.0",
        ]
    },
    
    entry_points={
        "console_scripts": [
            "deploy-graphql-api=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/graphql-appsync-dynamodb/issues",
        "Source": "https://github.com/aws-samples/graphql-appsync-dynamodb",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "appsync",
        "graphql",
        "dynamodb",
        "opensearch",
        "lambda",
        "cognito",
        "serverless",
        "api",
        "real-time",
        "subscriptions"
    ],
    
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yaml",
            "*.yml",
            "*.json",
            "schema.graphql",
        ],
    },
    
    include_package_data=True,
    
    zip_safe=False,
    
    # CDK-specific metadata
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3",
        },
    },
)

# Additional metadata for CDK applications
CDK_METADATA = {
    "app": "python3 app.py",
    "language": "python",
    "context": {
        "@aws-cdk/aws-lambda:recognizeLayerVersion": True,
        "@aws-cdk/core:checkSecretUsage": True,
        "@aws-cdk/core:target-partitions": ["aws", "aws-cn"],
        "@aws-cdk-containers/ecs-service-extensions:enableDefaultLogDriver": True,
        "@aws-cdk/aws-ec2:uniqueImdsv2TemplateName": True,
        "@aws-cdk/aws-ecs:arnFormatIncludesClusterName": True,
        "@aws-cdk/aws-iam:minimizePolicies": True,
        "@aws-cdk/core:validateSnapshotRemovalPolicy": True,
        "@aws-cdk/aws-codepipeline:crossAccountKeyAliasStackSafeResourceName": True,
        "@aws-cdk/aws-s3:createDefaultLoggingPolicy": True,
        "@aws-cdk/aws-sns-subscriptions:restrictSqsDescryption": True,
        "@aws-cdk/aws-apigateway:disableCloudWatchRole": True,
        "@aws-cdk/core:enablePartitionLiterals": True,
        "@aws-cdk/aws-events:eventsTargetQueueSameAccount": True,
        "@aws-cdk/aws-iam:standardizedServicePrincipals": True,
        "@aws-cdk/aws-ecs:disableExplicitDeploymentControllerForCircuitBreaker": True,
        "@aws-cdk/aws-iam:importedRoleStackSafeDefaultPolicyName": True,
        "@aws-cdk/aws-s3:serverAccessLogsUseBucketPolicy": True,
        "@aws-cdk/aws-route53-patters:useCertificate": True,
        "@aws-cdk/customresources:installLatestAwsSdkDefault": False,
        "@aws-cdk/aws-rds:databaseProxyUniqueResourceName": True,
        "@aws-cdk/aws-codedeploy:removeAlarmsFromDeploymentGroup": True,
        "@aws-cdk/aws-apigateway:authorizerChangeDeploymentLogicalId": True,
        "@aws-cdk/aws-ec2:launchTemplateDefaultUserData": True,
        "@aws-cdk/aws-secretsmanager:useAttachedSecretResourcePolicyForSecretTargetAttachments": True,
        "@aws-cdk/aws-redshift:columnId": True,
        "@aws-cdk/aws-stepfunctions-tasks:enableLoggingForLambdaInvoke": True,
        "@aws-cdk/aws-ec2:restrictDefaultSecurityGroup": True,
        "@aws-cdk/aws-apigateway:requestValidatorUniqueId": True,
        "@aws-cdk/aws-kms:aliasNameRef": True,
        "@aws-cdk/aws-autoscaling:generateLaunchTemplateInsteadOfLaunchConfig": True,
        "@aws-cdk/core:includePrefixInUniqueNameGeneration": True,
        "@aws-cdk/aws-efs:denyAnonymousAccess": True,
        "@aws-cdk/aws-opensearch:enableOpensearchMultiAzWithStandby": True,
        "@aws-cdk/aws-lambda-nodejs:useLatestRuntimeVersion": True,
        "@aws-cdk/aws-efs:mountTargetOrderInsensitiveLogicalId": True,
        "@aws-cdk/aws-rds:auroraClusterChangeScopeOfInstanceParameterGroupWithEachParameters": True,
        "@aws-cdk/aws-appsync:useArnForSourceApiAssociationIdentifier": True,
        "@aws-cdk/aws-rds:preventRenderingDeprecatedCredentials": True,
        "@aws-cdk/aws-codepipeline-actions:useNewDefaultBranchForSourceAction": True
    }
}