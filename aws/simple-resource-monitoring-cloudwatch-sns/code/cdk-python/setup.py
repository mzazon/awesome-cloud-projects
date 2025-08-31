"""
Setup configuration for Simple Resource Monitoring CDK Python Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points for deployment.
"""

import os
import setuptools

# Read README for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Simple Resource Monitoring with CloudWatch and SNS - CDK Python Application"

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file"""
    requirements = []
    if os.path.exists(filename):
        with open(filename, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

# Package configuration
setuptools.setup(
    name="simple-resource-monitoring-cdk",
    version="1.0.0",
    author="AWS Recipe Generator",
    author_email="recipes@example.com",
    description="CDK Python application for simple resource monitoring with CloudWatch and SNS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/aws-recipes",
    project_urls={
        "Bug Tracker": "https://github.com/your-org/aws-recipes/issues",
        "Documentation": "https://github.com/your-org/aws-recipes/blob/main/aws/simple-resource-monitoring-cloudwatch-sns/",
    },
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
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=parse_requirements("requirements.txt"),
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
        ],
        "aws-cli": [
            "awscli>=1.32.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "simple-monitoring-deploy=app:main",
        ],
    },
    keywords=[
        "aws", "cdk", "cloudwatch", "sns", "monitoring", "alerts", 
        "ec2", "infrastructure", "python", "devops"
    ],
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    # Ensure Python 3.8+ compatibility
    zip_safe=False,
)