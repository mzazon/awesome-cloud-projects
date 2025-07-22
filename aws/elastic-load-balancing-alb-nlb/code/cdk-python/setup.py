"""
Setup configuration for the Elastic Load Balancing CDK Python application.

This setup.py file defines the package configuration for the CDK application,
including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages
import os

# Read the contents of README file if it exists
def read_readme():
    """Read README file if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as fh:
            return fh.read()
    return "AWS CDK Python application for Elastic Load Balancing with ALB and NLB"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as fh:
            return [
                line.strip() 
                for line in fh.readlines() 
                if line.strip() and not line.startswith("#")
            ]
    return [
        "aws-cdk-lib>=2.169.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setup(
    name="elastic-load-balancing-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="AWS CDK Python application for Elastic Load Balancing with Application and Network Load Balancers",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=find_packages(where="."),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.4.3",
            "pytest-cov>=4.1.0",
            "black>=23.12.1",
            "flake8>=6.1.0",
            "mypy>=1.8.0",
        ],
        "testing": [
            "pytest>=7.4.3",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "boto3>=1.35.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-elb=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "load-balancer",
        "alb",
        "nlb",
        "ec2",
        "networking",
    ],
    license="Apache-2.0",
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
)