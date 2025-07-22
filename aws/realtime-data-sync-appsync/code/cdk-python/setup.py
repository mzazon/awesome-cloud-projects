"""
Setup configuration for Real-Time Data Synchronization CDK Python Application
Real-Time Data Synchronization with AppSync
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python application for building real-time data synchronization 
    with AWS AppSync and DynamoDB Streams. This solution provides automatic 
    real-time updates across all connected clients using GraphQL subscriptions.
    """

setup(
    name="real-time-data-sync-cdk",
    version="1.0.0",
    author="AWS CDK Recipe",
    author_email="developer@example.com",
    description="Real-Time Data Synchronization with AWS AppSync and DynamoDB Streams",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/real-time-data-sync-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    python_requires=">=3.9",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.10.0",
            "flake8>=6.1.0",
            "mypy>=1.7.0",
            "isort>=5.12.0",
            "pre-commit>=3.5.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "testing": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # Mock AWS services for testing
            "boto3-stubs>=1.34.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-real-time-sync=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.graphql", "*.yaml", "*.yml", "*.json"],
    },
    keywords=[
        "aws",
        "cdk",
        "appsync",
        "dynamodb",
        "real-time",
        "graphql",
        "serverless",
        "streams",
        "lambda",
        "subscriptions",
        "websockets",
        "infrastructure",
        "iac",
    ],
    project_urls={
        "Bug Reports": "https://github.com/your-org/real-time-data-sync-cdk/issues",
        "Source": "https://github.com/your-org/real-time-data-sync-cdk",
        "Documentation": "https://your-org.github.io/real-time-data-sync-cdk",
    },
    license="MIT",
    zip_safe=False,
)