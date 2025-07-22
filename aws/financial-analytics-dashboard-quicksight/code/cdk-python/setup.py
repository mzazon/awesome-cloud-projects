"""
Setup configuration for Advanced Financial Analytics Dashboard CDK Application

This setup.py file configures the Python package for the CDK application
that deploys a comprehensive financial analytics platform using Amazon
QuickSight, Cost Explorer APIs, Lambda functions, and S3 data lakes.
"""

from setuptools import setup, find_packages

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Advanced Financial Analytics Dashboard CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib>=2.151.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
            "pandas>=2.0.0",
            "pyarrow>=14.0.0",
            "numpy>=1.24.0"
        ]

setup(
    name="financial-analytics-dashboard-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS CDK Team",
    author_email="aws-cdk-team@example.com",
    description="CDK application for deploying advanced financial analytics dashboard",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/financial-analytics-dashboard-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "isort>=5.12.0",
            "bandit>=1.7.5",
            "safety>=2.3.0"
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0"
        ]
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-financial-analytics=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: Financial and Insurance Industry",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Office/Business :: Financial",
        "Topic :: System :: Monitoring",
        "Framework :: AWS CDK",
        "Environment :: Console",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "financial-analytics", "quicksight", "cost-explorer",
        "lambda", "s3", "athena", "glue", "eventbridge", "infrastructure",
        "cloud", "analytics", "dashboard", "reporting", "cost-management"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/financial-analytics-dashboard-cdk/issues",
        "Source": "https://github.com/aws-samples/financial-analytics-dashboard-cdk",
        "Documentation": "https://github.com/aws-samples/financial-analytics-dashboard-cdk/blob/main/README.md",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS QuickSight": "https://aws.amazon.com/quicksight/",
        "AWS Cost Explorer": "https://aws.amazon.com/aws-cost-management/aws-cost-explorer/"
    },
    
    # Package data files
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Exclude development files from distribution
    exclude_package_data={
        "": ["tests/*", "*.pyc", "__pycache__/*", ".git/*", ".pytest_cache/*"]
    },
    
    # Zip safe configuration
    zip_safe=False,
    
    # Platform requirements
    platforms=["any"],
    
    # License
    license="MIT",
    
    # Maintainer information
    maintainer="AWS CDK Team",
    maintainer_email="aws-cdk-team@example.com",
)