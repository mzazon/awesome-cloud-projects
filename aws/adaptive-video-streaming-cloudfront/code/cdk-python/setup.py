"""
Setup configuration for AWS CDK Adaptive Bitrate Streaming Application

This setup.py file configures the Python package for the CDK application that
deploys a complete adaptive bitrate video streaming solution using AWS services.

Author: AWS CDK Generator
Version: 1.0.0
Python: >=3.8
CDK Version: 2.x
"""

import setuptools
from pathlib import Path


def read_long_description() -> str:
    """Read the long description from README file if it exists"""
    readme_path = Path(__file__).parent / "README.md"
    if readme_path.exists():
        return readme_path.read_text(encoding="utf-8")
    return "AWS CDK application for adaptive bitrate video streaming with MediaConvert and CloudFront"


def read_requirements() -> list:
    """Read requirements from requirements.txt file"""
    requirements_path = Path(__file__).parent / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, 'r', encoding='utf-8') as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith('#')
            ]
    return [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0,<2.0.0"
    ]


setuptools.setup(
    name="adaptive-bitrate-streaming-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    description="AWS CDK application for adaptive bitrate video streaming infrastructure",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/adaptive-bitrate-streaming-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.2.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "mypy>=1.0.0,<2.0.0",
            "black>=23.0.0,<24.0.0",
            "isort>=5.12.0,<6.0.0",
            "flake8>=6.0.0,<7.0.0",
            "safety>=2.3.0,<3.0.0",
            "bandit>=1.7.0,<2.0.0"
        ],
        "docs": [
            "sphinx>=6.1.0,<7.0.0",
            "sphinx-rtd-theme>=1.2.0,<2.0.0"
        ]
    },
    
    # Package classification
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
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: Multimedia :: Video :: Conversion",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content"
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "video",
        "streaming",
        "adaptive-bitrate",
        "mediaconvert",
        "cloudfront",
        "s3",
        "lambda",
        "abr",
        "hls",
        "dash",
        "transcoding"
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-abr-streaming=app:main",
        ],
    },
    
    # Include additional files in package
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yaml",
            "*.yml",
            "*.json"
        ]
    },
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/adaptive-bitrate-streaming-cdk",
        "Bug Tracker": "https://github.com/aws-samples/adaptive-bitrate-streaming-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS MediaConvert": "https://aws.amazon.com/mediaconvert/",
        "AWS CloudFront": "https://aws.amazon.com/cloudfront/",
    },
    
    # License
    license="Apache License 2.0",
    
    # Additional metadata
    platforms=["any"],
    
    # CDK-specific metadata
    cdk_version="2.x",
    aws_services=[
        "S3",
        "Lambda", 
        "MediaConvert",
        "CloudFront",
        "IAM",
        "CloudWatch"
    ],
    
    # Architecture patterns implemented
    patterns=[
        "Event-driven architecture",
        "Serverless computing",
        "Content delivery networks",
        "Video processing pipelines",
        "Adaptive bitrate streaming"
    ]
)


# CDK App configuration metadata
CDK_APP_CONFIG = {
    "app": "python app.py",
    "watch": {
        "include": ["**"],
        "exclude": [
            "README.md",
            "cdk*.json",
            "requirements*.txt",
            "source.bat",
            "**/__pycache__",
            "**/*.pyc"
        ]
    },
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
        "@aws-cdk/aws-stepfunctions-tasks:enableLoggingCfnOutputs": True
    }
}


if __name__ == "__main__":
    print("AWS CDK Adaptive Bitrate Streaming Application Setup")
    print("====================================================")
    print()
    print("This setup.py configures a CDK application for deploying")
    print("adaptive bitrate video streaming infrastructure on AWS.")
    print()
    print("Key Features:")
    print("- S3 buckets for video storage")
    print("- Lambda-based video processing automation")
    print("- MediaConvert ABR transcoding")
    print("- CloudFront global content delivery")
    print("- IAM roles with least privilege access")
    print()
    print("To install dependencies:")
    print("  pip install -r requirements.txt")
    print()
    print("To deploy the infrastructure:")
    print("  cdk deploy")
    print()
    print("To destroy the infrastructure:")
    print("  cdk destroy")
    print()
    print("For more information, see the AWS CDK documentation:")
    print("  https://docs.aws.amazon.com/cdk/")