"""
Setup configuration for AWS CDK Python application
GraphQL APIs with AWS AppSync Recipe
"""

from setuptools import setup, find_packages

# Read the contents of README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Real-Time GraphQL API with AppSync"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.166.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.35.0",
        "botocore>=1.35.0",
        "typing-extensions>=4.0.0",
    ]

setup(
    name="graphql-appsync-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Real-Time GraphQL API with AppSync",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Generator",
    author_email="recipes@aws.example.com",
    license="MIT",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "deploy-graphql-api=app:main",
        ],
    },
    
    # Package metadata
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Software Development :: Code Generators",
        "Topic :: System :: Installation/Setup",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "appsync",
        "graphql",
        "dynamodb",
        "cognito",
        "serverless",
        "infrastructure-as-code",
        "cloud-development",
        "api-development",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "AWS AppSync Documentation": "https://docs.aws.amazon.com/appsync/",
        "GraphQL Specification": "https://spec.graphql.org/",
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.graphql", "*.md"],
    },
    
    # Zip safety
    zip_safe=False,
)