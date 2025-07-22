"""
Setup configuration for AWS CDK Python application
Automated Development Environment Provisioning with WorkSpaces Personal
"""

from setuptools import setup, find_packages

with open("requirements.txt") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

setup(
    name="workspaces-automation-cdk",
    version="1.0.0",
    
    description="AWS CDK application for automated WorkSpaces Personal development environment provisioning",
    long_description="""
    This CDK application creates an automated system that provisions standardized WorkSpaces Personal 
    environments with pre-configured development tools, security policies, and team-specific software stacks.
    
    Features:
    - Lambda function for orchestrating WorkSpaces provisioning
    - Systems Manager document for development environment setup
    - EventBridge rule for automated scheduling
    - IAM roles and policies for secure operation
    - Secrets Manager for storing Active Directory credentials
    """,
    long_description_content_type="text/plain",
    
    author="AWS CDK Generator",
    author_email="developer@company.com",
    
    python_requires=">=3.8",
    
    packages=find_packages(),
    
    install_requires=requirements,
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
    ],
    
    keywords="aws cdk workspaces automation development-environment",
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
)