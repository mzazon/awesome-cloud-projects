"""
Setup configuration for AWS CDK Python Security Hub Incident Response application.
"""

from setuptools import setup, find_packages

# Read README for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Security Hub Incident Response"

# Read requirements
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0"
    ]

setup(
    name="security-incident-response-cdk",
    version="1.0.0",
    author="AWS CDK Security Team",
    author_email="security@example.com",
    description="AWS CDK Python application for automated Security Hub incident response",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/security-incident-response-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/your-org/security-incident-response-cdk/issues",
        "Documentation": "https://github.com/your-org/security-incident-response-cdk/blob/main/README.md",
        "Source Code": "https://github.com/your-org/security-incident-response-cdk",
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
        "Topic :: Security",
        "Topic :: System :: Monitoring",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-security-hub=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "security",
        "security-hub",
        "incident-response",
        "automation",
        "lambda",
        "eventbridge",
        "sns",
        "cloudformation",
        "infrastructure-as-code"
    ],
    include_package_data=True,
    zip_safe=False,
)