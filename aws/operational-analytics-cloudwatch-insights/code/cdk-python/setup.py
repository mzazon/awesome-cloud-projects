"""
Setup configuration for Operational Analytics CDK Python Application

This setup.py file configures the CDK Python application for operational analytics
with CloudWatch Insights. It defines package metadata, dependencies, and entry points
for the CDK application.

The application provides a comprehensive solution for operational monitoring including:
- CloudWatch Logs for log aggregation and analysis
- Lambda functions for log generation and alert processing
- SNS topics for notification delivery
- CloudWatch Dashboards for visualization
- Automated anomaly detection and alerting
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read README file for package description"""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, encoding="utf-8") as f:
            return f.read()
    return "Operational Analytics with CloudWatch Insights CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    requirements.append(line)
    
    return requirements

# Package metadata
PACKAGE_NAME = "operational-analytics-cdk"
VERSION = "1.0.0"
DESCRIPTION = "CDK Python application for operational analytics with CloudWatch Insights"
AUTHOR = "AWS CDK Generator"
AUTHOR_EMAIL = "developer@example.com"
URL = "https://github.com/example/operational-analytics-cdk"

# Development status classifiers
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "Intended Audience :: System Administrators",
    "License :: OSI Approved :: MIT License",
    "Operating System :: OS Independent",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Topic :: Software Development :: Libraries :: Application Frameworks",
    "Topic :: System :: Monitoring",
    "Topic :: System :: Logging",
    "Typing :: Typed",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk", 
    "cloudwatch",
    "insights",
    "operational",
    "analytics",
    "monitoring",
    "logging",
    "observability",
    "lambda",
    "sns",
    "dashboards",
    "alerts",
    "anomaly-detection"
]

setup(
    # Basic package information
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author and project information
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    
    # Package discovery and structure
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0", 
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.26.0"
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # Mock AWS services for testing
            "aws-cdk-lib",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0"
        ]
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-operational-analytics=app:main",
        ],
    },
    
    # Package classification
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    
    # Project URLs for PyPI
    project_urls={
        "Documentation": f"{URL}/docs",
        "Source": URL,
        "Tracker": f"{URL}/issues",
        "Changelog": f"{URL}/blob/main/CHANGELOG.md",
    },
    
    # Package options
    options={
        "bdist_wheel": {
            "universal": False,  # This package is not universal
        },
    },
)

# CDK-specific configuration
CDK_VERSION = "2.168.0"

# Validate CDK version compatibility
def validate_cdk_version():
    """Validate that the CDK version is compatible"""
    try:
        import aws_cdk as cdk
        current_version = cdk.__version__
        
        # Simple version check (could be enhanced for more sophisticated comparison)
        if current_version != CDK_VERSION:
            print(f"Warning: CDK version mismatch. Expected {CDK_VERSION}, found {current_version}")
            print("Consider updating your CDK installation for optimal compatibility.")
    except ImportError:
        print("CDK not installed. Run 'pip install -r requirements.txt' to install dependencies.")

# Run validation if this file is executed directly
if __name__ == "__main__":
    validate_cdk_version()
    print(f"Setup configuration for {PACKAGE_NAME} v{VERSION}")
    print(f"Description: {DESCRIPTION}")
    print("Run 'pip install -e .' to install in development mode")
    print("Run 'pip install .' to install the package")