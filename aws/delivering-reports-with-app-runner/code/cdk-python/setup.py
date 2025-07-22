"""
Setup configuration for Scheduled Email Reports CDK Python application.

This package provides Infrastructure as Code (IaC) using AWS CDK Python
for deploying a serverless email reporting system with App Runner and SES.
"""

import setuptools

with open("README.md", encoding="utf-8") as fp:
    long_description = fp.read()

# Read requirements from requirements.txt
def parse_requirements():
    """Parse requirements.txt file and return list of requirements."""
    requirements = []
    try:
        with open("requirements.txt", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    requirements.append(line)
    except FileNotFoundError:
        # Fallback to hardcoded requirements if file not found
        requirements = [
            "aws-cdk-lib>=2.161.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "cdk-nag>=2.29.0,<3.0.0"
        ]
    return requirements

setuptools.setup(
    name="scheduled-email-reports",
    version="1.0.0",
    description="CDK Python application for scheduled email reports with App Runner and SES",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="your-email@example.com",
    packages=setuptools.find_packages(),
    install_requires=parse_requirements(),
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Environment :: Console",
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
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "infrastructure",
        "email",
        "reports",
        "app-runner",
        "ses",
        "eventbridge",
        "scheduler",
        "serverless"
    ],
    project_urls={
        "Source": "https://github.com/your-username/scheduled-email-reports-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Bug Reports": "https://github.com/your-username/scheduled-email-reports-cdk/issues",
    },
)