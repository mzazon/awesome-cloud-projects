"""
Setup configuration for Real-Time Collaborative Task Management CDK Application

This setup.py file configures the Python package for the CDK application that
deploys a serverless task management system using Aurora DSQL, EventBridge,
Lambda, and CloudWatch services.
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    """Read README.md file for package description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Real-Time Collaborative Task Management System using AWS CDK"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements.txt file for dependencies."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="real-time-task-management-cdk",
    version="1.0.0",
    description="CDK application for real-time collaborative task management system",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Recipe Generator",
    author_email="recipes@example.com",
    
    # Project URLs
    url="https://github.com/aws-samples/task-management-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/task-management-cdk",
        "Bug Reports": "https://github.com/aws-samples/task-management-cdk/issues",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_dir={"": "."},
    
    # Python version requirement
    python_requires=">=3.8,<4.0",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.3.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "aws-cdk.assertions>=2.162.1",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
            "myst-parser>=2.0.0",
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "task-management-deploy=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Framework :: AWS CDK",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Office/Business :: Groupware",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "serverless",
        "task-management",
        "collaboration",
        "aurora-dsql",
        "eventbridge",
        "lambda",
        "cloudwatch",
        "distributed-database",
        "event-driven",
        "real-time",
        "multi-region",
    ],
    
    # License information
    license="Apache-2.0",
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # CDK specific configuration
    options={
        "build": {
            "build_base": "build",
        },
    },
    
    # Platform compatibility
    platforms=["any"],
    
    # Project maturity
    download_url="https://github.com/aws-samples/task-management-cdk/archive/v1.0.0.tar.gz",
    
    # Metadata for PyPI
    maintainer="AWS CDK Community",
    maintainer_email="cdk-community@aws.amazon.com",
    
    # Testing configuration
    test_suite="tests",
    tests_require=[
        "pytest>=7.4.0",
        "pytest-cov>=4.1.0",
        "moto>=4.2.0",
    ],
    
    # Command line tools
    scripts=[],
    
    # Data files
    data_files=[
        ("docs", ["README.md"]),
        ("config", []),
    ],
)

# Additional setup configuration for CDK applications
if __name__ == "__main__":
    print("Setting up Real-Time Collaborative Task Management CDK Application")
    print("=" * 60)
    print("This CDK application deploys:")
    print("• Aurora DSQL multi-region cluster")
    print("• EventBridge custom event bus") 
    print("• Lambda functions for task processing")
    print("• CloudWatch monitoring and dashboards")
    print("• IAM roles with least privilege access")
    print("=" * 60)
    print("Installation completed successfully!")
    print("Run 'cdk deploy' to deploy the infrastructure.")