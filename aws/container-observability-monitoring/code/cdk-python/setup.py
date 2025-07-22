"""
Setup configuration for the Container Observability CDK Python application.

This setup.py file configures the Python package for the comprehensive container
observability and performance monitoring CDK application.
"""

from setuptools import setup, find_packages

# Read the requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "CDK Python application for comprehensive container observability and performance monitoring"

setup(
    name="container-observability-cdk",
    version="1.0.0",
    description="CDK Python application for comprehensive container observability and performance monitoring",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    packages=find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "cfn-lint>=0.77.0",
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "container-observability-cdk=app:main",
        ],
    },
    package_data={
        "": ["*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "container",
        "observability",
        "monitoring",
        "performance",
        "eks",
        "ecs",
        "cloudwatch",
        "prometheus",
        "grafana",
        "x-ray",
        "opensearch",
        "infrastructure",
        "devops",
        "cloud",
        "kubernetes",
        "docker",
        "microservices",
        "logging",
        "metrics",
        "tracing",
        "alerting",
        "analytics",
    ],
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
)