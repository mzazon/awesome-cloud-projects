"""
Setup configuration for EKS Spot Node Groups CDK Python application

This setup.py file configures the Python package for the CDK application
that creates cost-optimized EKS node groups with Spot instances and mixed
instance types.
"""

from setuptools import setup, find_packages


def read_requirements():
    """Read requirements from requirements.txt file"""
    with open("requirements.txt", "r", encoding="utf-8") as f:
        return [
            line.strip()
            for line in f.readlines()
            if line.strip() and not line.startswith("#")
        ]


setup(
    name="eks-spot-node-groups-cdk",
    version="1.0.0",
    description="CDK Python application for EKS Node Groups with Spot Instances and Mixed Instance Types",
    long_description="""
    This CDK application creates cost-optimized Amazon EKS node groups using EC2 Spot instances
    and mixed instance types. The solution achieves up to 90% cost savings compared to On-Demand
    instances while maintaining high availability through intelligent instance diversification.
    
    Key features:
    - EKS cluster with VPC and subnets
    - Spot instance node group with mixed instance types (m5, m5a, c5, c5a families)
    - On-Demand backup node group for critical workloads
    - AWS Node Termination Handler for graceful Spot interruption handling
    - Cluster Autoscaler for dynamic scaling
    - CloudWatch monitoring and alerting
    - IAM roles and policies following least privilege principle
    - SNS notifications for operational alerts
    """,
    long_description_content_type="text/plain",
    author="AWS Solutions Architecture",
    author_email="solutions-architecture@amazon.com",
    url="https://github.com/aws-samples/eks-spot-node-groups",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=read_requirements(),
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
        "Topic :: Software Development :: Libraries",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    keywords=[
        "aws",
        "cdk",
        "eks",
        "kubernetes",
        "spot-instances",
        "cost-optimization",
        "infrastructure-as-code",
        "cloud-native",
        "containers",
        "autoscaling",
    ],
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/eks/latest/userguide/",
        "Source": "https://github.com/aws-samples/eks-spot-node-groups",
        "Tracker": "https://github.com/aws-samples/eks-spot-node-groups/issues",
    },
    entry_points={
        "console_scripts": [
            "eks-spot-deploy=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)