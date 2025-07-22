"""
Setup configuration for Secure Remote Access Session Manager CDK application.

This setup.py file configures the Python package for the CDK application
that implements secure remote access using AWS Systems Manager Session Manager.
"""

import setuptools


with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()


setuptools.setup(
    name="secure-remote-access-session-manager",
    version="1.0.0",
    
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    
    description="CDK application for Accessing Instances with Session Manager",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-solutions/secure-remote-access-session-manager",
    
    packages=setuptools.find_packages(),
    
    install_requires=[
        "aws-cdk-lib>=2.164.1",
        "constructs>=10.0.0,<11.0.0",
    ],
    
    python_requires=">=3.8",
    
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "session-manager",
        "remote-access",
        "security",
        "zero-trust",
        "infrastructure-as-code",
        "systems-manager",
        "ec2",
        "iam"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws-solutions/secure-remote-access-session-manager/issues",
        "Source": "https://github.com/aws-solutions/secure-remote-access-session-manager",
        "Documentation": "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html",
    },
)