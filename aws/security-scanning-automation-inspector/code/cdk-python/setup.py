"""
Setup configuration for AWS CDK Python Security Scanning Application

This setup.py file defines the package configuration for the automated
security scanning solution using Amazon Inspector and AWS Security Hub.
"""

from setuptools import setup, find_packages

# Read the README file for long description
with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="aws-security-scanning-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="security@example.com",
    description="AWS CDK Python application for automated security scanning with Inspector and Security Hub",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/security-scanning-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/security-scanning-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/security-scanning-cdk",
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
        "Topic :: Security",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Typing :: Typed",
    ],
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.9.0",
            "flake8>=6.1.0",
            "mypy>=1.6.0",
            "isort>=5.12.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-security-scanning=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    keywords=[
        "aws",
        "cdk",
        "security",
        "inspector",
        "security-hub",
        "vulnerability-scanning",
        "compliance",
        "automation",
        "infrastructure-as-code",
        "cloud-security",
        "devops",
        "lambda",
        "eventbridge",
        "sns",
    ],
    zip_safe=False,
    platforms=["any"],
    license="MIT",
    test_suite="tests",
    tests_require=[
        "pytest>=7.4.0",
        "pytest-cov>=4.1.0",
        "moto>=4.2.0",  # For mocking AWS services in tests
    ],
)