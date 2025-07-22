"""
Setup configuration for webhook processing CDK Python application.

This setup file configures the Python package for the webhook processing system
CDK application, including all necessary dependencies and metadata.
"""

from setuptools import setup, find_packages

# Read the requirements file
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read the README file if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Webhook processing system built with AWS CDK Python"

setup(
    name="webhook-processing-system",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="devops@example.com",
    description="Webhook processing system with API Gateway, SQS, and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/webhook-processing-system",
    project_urls={
        "Bug Tracker": "https://github.com/your-org/webhook-processing-system/issues",
        "Documentation": "https://github.com/your-org/webhook-processing-system/wiki",
        "Source Code": "https://github.com/your-org/webhook-processing-system",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: System :: Monitoring",
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
            "pre-commit>=2.20.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "webhook-processing-deploy=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "webhook",
        "api-gateway",
        "sqs",
        "lambda",
        "dynamodb",
        "serverless",
        "cloudformation",
        "infrastructure",
        "devops",
        "microservices",
        "event-driven",
        "asynchronous",
    ],
    platforms=["any"],
    license="MIT",
    maintainer="DevOps Team",
    maintainer_email="devops@example.com",
)