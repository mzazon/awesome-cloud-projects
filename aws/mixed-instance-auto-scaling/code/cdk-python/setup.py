"""
Setup configuration for Mixed Instance Auto Scaling Groups CDK Python Application

This setup.py file configures the Python package for the CDK application that creates
cost-optimized Auto Scaling groups with mixed instance types and Spot Instances.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="mixed-instance-autoscaling-cdk",
    version="1.0.0",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    description="CDK Python application for mixed instance Auto Scaling groups with Spot Instances",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/your-org/mixed-instance-autoscaling-cdk",
    
    project_urls={
        "Bug Tracker": "https://github.com/your-org/mixed-instance-autoscaling-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/your-org/mixed-instance-autoscaling-cdk",
    },
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    packages=setuptools.find_packages(),
    
    python_requires=">=3.8",
    
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    
    extras_require={
        "dev": [
            "aws-cdk>=2.100.0,<3.0.0",
            "mypy>=1.5.0",
            "black>=23.0.0",
            "pytest>=7.0.0",
            "boto3>=1.28.0",
            "colorama>=0.4.6",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "deploy-mixed-instances=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "autoscaling",
        "spot-instances",
        "mixed-instances",
        "cost-optimization",
        "infrastructure-as-code",
        "cloud-computing",
        "ec2",
        "load-balancer",
    ],
    
    include_package_data=True,
    zip_safe=False,
    
    # Package metadata
    license="MIT",
    
    # CDK-specific metadata
    cdk_version=">=2.100.0",
)