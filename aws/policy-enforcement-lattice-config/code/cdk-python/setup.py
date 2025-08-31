"""
Setup configuration for Policy Enforcement Automation with VPC Lattice and Config CDK application.

This setup.py file configures the Python package for the CDK application that deploys
automated policy enforcement for VPC Lattice resources using AWS Config.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="policy-enforcement-lattice-config",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="admin@company.com",
    description="Policy Enforcement Automation with VPC Lattice and Config - CDK Python Application",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/policy-enforcement-lattice-config",
    project_urls={
        "Bug Tracker": "https://github.com/your-org/policy-enforcement-lattice-config/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/latest/guide/",
        "Source": "https://github.com/your-org/policy-enforcement-lattice-config",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Topic :: System :: Monitoring",
        "Operating System :: OS Independent",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib==2.167.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.35.0",
        "botocore>=1.35.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.2",
        ],
        "cli": [
            "aws-cdk>=2.167.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "policy-enforcement=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "vpc-lattice", 
        "aws-config",
        "compliance",
        "policy-enforcement",
        "automation",
        "security",
        "governance",
        "infrastructure-as-code",
        "cloud-development-kit",
    ],
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    zip_safe=False,
)