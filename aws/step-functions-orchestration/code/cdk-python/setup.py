"""
Setup configuration for the Microservices Step Functions CDK application.

This package provides Infrastructure as Code (IaC) for deploying a complete
microservices orchestration solution using AWS Step Functions, Lambda, and EventBridge.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Microservices orchestration with AWS Step Functions"

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file."""
    try:
        with open(filename, "r", encoding="utf-8") as f:
            return [
                line.strip()
                for line in f
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        return []

setup(
    name="microservices-stepfunctions-cdk",
    version="1.0.0",
    description="AWS CDK application for microservices orchestration with Step Functions",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architecture",
    author_email="solutions@example.com",
    url="https://github.com/aws/recipes",
    packages=find_packages(exclude=["tests*"]),
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
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
    ],
    
    python_requires=">=3.8",
    install_requires=parse_requirements("requirements.txt"),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-microservices=app:main",
        ],
    },
    
    # Package metadata
    keywords=[
        "aws",
        "cdk",
        "stepfunctions",
        "lambda",
        "eventbridge",
        "microservices",
        "orchestration",
        "serverless",
        "infrastructure",
        "cloud",
    ],
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/step-functions/",
        "Source": "https://github.com/aws/recipes",
        "Bug Reports": "https://github.com/aws/recipes/issues",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/latest/guide/",
        "Step Functions Guide": "https://docs.aws.amazon.com/step-functions/latest/dg/",
    },
    
    # License information
    license="MIT",
    
    # Zip safety
    zip_safe=False,
)