"""
Setup configuration for EFS Performance Optimization CDK Application

This setup.py file configures the Python package for the EFS Performance 
Optimization and Monitoring CDK application, including dependencies,
metadata, and development requirements.
"""

import setuptools

# Read the long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK application for EFS Performance Optimization and Monitoring"

# Define the package requirements
install_requires = [
    "aws-cdk-lib>=2.100.0,<3.0.0",
    "constructs>=10.0.0,<11.0.0",
]

# Define development requirements
dev_requires = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0", 
    "black>=23.0.0",
    "flake8>=6.0.0",
    "mypy>=1.0.0",
    "boto3>=1.34.0",
    "python-dotenv>=1.0.0",
]

setuptools.setup(
    name="efs-performance-optimization-cdk",
    version="1.0.0",
    
    # Package metadata
    description="AWS CDK application for EFS Performance Optimization and Monitoring",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Recipes Team",
    author_email="aws-recipes@example.com",
    
    # Project URLs
    url="https://github.com/aws-samples/efs-performance-optimization",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/efs-performance-optimization/issues",
        "Source": "https://github.com/aws-samples/efs-performance-optimization",
        "Documentation": "https://docs.aws.amazon.com/efs/",
    },
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    
    # Dependencies
    install_requires=install_requires,
    extras_require={
        "dev": dev_requires,
    },
    
    # Python version requirement
    python_requires=">=3.8",
    
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Filesystems",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "efs",
        "elastic-file-system",
        "performance",
        "monitoring",
        "cloudwatch",
        "infrastructure",
        "storage",
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "efs-perf-deploy=app:main",
        ],
    },
    
    # License information
    license="Apache-2.0",
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
)