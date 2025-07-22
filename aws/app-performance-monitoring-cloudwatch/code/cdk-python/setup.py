"""
Setup configuration for AWS CDK Python Application Performance Monitoring application.

This setup.py file configures the Python package for the automated application
performance monitoring system using AWS CDK, CloudWatch Application Signals,
EventBridge, Lambda, and SNS services.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = """
    AWS CDK Python application for automated application performance monitoring 
    with CloudWatch Application Signals and EventBridge.
    """

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            # Skip comments, empty lines, and development dependencies
            if line and not line.startswith("#") and not any(
                dev_pkg in line for dev_pkg in [
                    "pytest", "black", "flake8", "mypy", "sphinx", 
                    "bandit", "safety", "boto3-stubs", "types-"
                ]
            ):
                # Remove version constraints that might cause issues
                if ">=" in line:
                    package = line.split(">=")[0]
                    install_requires.append(package)
                elif "==" in line:
                    install_requires.append(line)
                else:
                    install_requires.append(line)

# Fallback requirements if file doesn't exist or is empty
if not install_requires:
    install_requires = [
        "aws-cdk-lib>=2.100.0",
        "constructs>=10.3.0",
        "boto3>=1.34.0",
    ]

setuptools.setup(
    name="application-performance-monitoring",
    version="1.0.0",
    
    description="AWS CDK Python application for automated application performance monitoring",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="support@example.com",
    url="https://github.com/your-org/application-performance-monitoring",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=install_requires,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cloudwatch",
        "eventbridge",
        "lambda",
        "sns",
        "monitoring",
        "performance",
        "application-signals",
        "automation",
        "devops",
        "infrastructure-as-code",
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/your-org/application-performance-monitoring/issues",
        "Source": "https://github.com/your-org/application-performance-monitoring",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "boto3-stubs[cloudwatch,events,lambda,sns,logs,iam]>=1.34.0",
            "types-requests>=2.31.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "security": [
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "app-monitoring=app:main",
        ],
    },
    
    include_package_data=True,
    zip_safe=False,
)