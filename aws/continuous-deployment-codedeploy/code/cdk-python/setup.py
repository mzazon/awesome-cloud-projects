"""
Setup configuration for the Continuous Deployment with CodeDeploy CDK application.

This setup.py file defines the package configuration, dependencies, and metadata
for the CDK Python application that implements continuous deployment using
AWS CodeDeploy with blue-green deployment strategy.
"""

from setuptools import setup, find_packages

# Read the contents of the README file for long description
from pathlib import Path
this_directory = Path(__file__).parent
long_description = ""
readme_path = this_directory / "README.md"
if readme_path.exists():
    long_description = readme_path.read_text()

setup(
    name="continuous-deployment-codedeploy-cdk",
    version="1.0.0",
    
    description="CDK Python application for Continuous Deployment with CodeDeploy",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk-dev@amazon.com",
    
    url="https://github.com/aws/aws-cdk",
    
    license="Apache-2.0",
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Package data
    include_package_data=True,
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "PyYAML>=6.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.990",
            "awscli>=1.27.0",
            "jsonschema>=4.0.0",
        ],
    },
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    # Classifiers for PyPI
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Installation/Setup",
        "Topic :: System :: Software Distribution",
        "Typing :: Typed",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "codedeploy",
        "codecommit",
        "codebuild",
        "continuous-deployment",
        "blue-green",
        "cicd",
        "devops",
        "automation",
        "deployment",
        "load-balancer",
        "auto-scaling",
        "cloudwatch",
        "monitoring",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Changelog": "https://github.com/aws/aws-cdk/blob/main/CHANGELOG.md",
    },
    
    # Package metadata
    zip_safe=False,
    
    # Minimum setuptools version
    setup_requires=["setuptools>=45", "wheel"],
)