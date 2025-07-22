"""
Setup configuration for AWS CDK VPN Site-to-Site application.

This package contains the CDK Python application for creating AWS Site-to-Site VPN
infrastructure as described in the VPN connections recipe.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="vpn-site-to-site-cdk",
    version="1.0.0",
    author="Claude Code",
    author_email="code@anthropic.com",
    description="AWS CDK application for Site-to-Site VPN infrastructure",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/anthropic/recipes",
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
            "types-requests>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "vpn-site-to-site=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/anthropic/recipes/issues",
        "Source": "https://github.com/anthropic/recipes",
        "Documentation": "https://github.com/anthropic/recipes/blob/main/aws/vpn-connections-aws-site-to-site-vpn/vpn-connections-aws-site-to-site-vpn.md",
    },
    keywords=[
        "aws",
        "cdk",
        "vpn",
        "site-to-site",
        "networking",
        "infrastructure",
        "cloud",
        "hybrid",
        "bgp",
        "ipsec",
    ],
)