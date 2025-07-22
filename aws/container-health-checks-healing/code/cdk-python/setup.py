"""
Setup configuration for Container Health Checks and Self-Healing Applications CDK Python project.

This setup.py file configures the Python package for the CDK application,
including metadata, dependencies, and entry points.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as req_file:
    requirements = [
        line.strip() 
        for line in req_file.readlines() 
        if line.strip() and not line.startswith("#")
    ]

# Read README content if available
try:
    with open("README.md", "r", encoding="utf-8") as readme_file:
        long_description = readme_file.read()
except FileNotFoundError:
    long_description = "CDK Python application for Container Health Checks and Self-Healing Applications"

setup(
    name="container-health-checks-self-healing-cdk",
    version="1.0.0",
    description="AWS CDK Python application for implementing container health checks and self-healing applications",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Recipe Generator",
    author_email="recipes@example.com",
    url="https://github.com/aws-samples/container-health-checks-self-healing-cdk",
    license="MIT",
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Dependencies
    install_requires=requirements,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "mypy>=1.0.0",
            "flake8>=6.0.0",
            "cfn-lint>=0.83.0",
            "cfn-flip>=1.3.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # AWS service mocking for tests
        ],
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "cdk-health-check=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "containers",
        "health-checks",
        "self-healing",
        "ecs",
        "fargate",
        "load-balancer",
        "monitoring",
        "auto-scaling",
        "cloudwatch",
        "lambda",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/container-health-checks-self-healing-cdk/issues",
        "Source": "https://github.com/aws-samples/container-health-checks-self-healing-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # Package data
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
)