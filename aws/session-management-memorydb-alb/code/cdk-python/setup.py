"""
Setup configuration for Distributed Session Management CDK Application

This setup.py file configures the Python package for the CDK application that deploys
a distributed session management solution using Amazon MemoryDB for Redis and 
Application Load Balancer.

The application includes:
- Infrastructure as Code using AWS CDK Python
- Production-ready security and networking configurations
- Auto-scaling and high availability features
- Comprehensive monitoring and logging
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = (
        "Distributed Session Management CDK Application\n\n"
        "A production-ready AWS CDK Python application for deploying distributed "
        "session management infrastructure using Amazon MemoryDB for Redis and "
        "Application Load Balancer."
    )

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "typing-extensions>=4.0.0"
    ]

# Development dependencies
dev_requirements = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "black>=23.0.0",
    "flake8>=6.0.0",
    "mypy>=1.0.0",
    "moto[all]>=4.2.0",
    "bandit>=1.7.0",
    "safety>=2.0.0",
    "pre-commit>=3.0.0"
]

# Testing dependencies
test_requirements = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "moto[all]>=4.2.0",
    "freezegun>=1.2.0",
    "coverage>=7.0.0"
]

# Documentation dependencies
docs_requirements = [
    "sphinx>=5.0.0",
    "sphinx-rtd-theme>=1.0.0"
]

setup(
    # Package Metadata
    name="distributed-session-management-cdk",
    version="1.0.0",
    author="AWS Cloud Recipe",
    author_email="support@example.com",
    description="CDK application for distributed session management with MemoryDB and ALB",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/distributed-session-management",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/distributed-session-management/issues",
        "Source": "https://github.com/aws-samples/distributed-session-management",
        "Documentation": "https://aws.amazon.com/memorydb/",
    },

    # Package Configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python Version Requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Optional Dependencies
    extras_require={
        "dev": dev_requirements,
        "test": test_requirements,
        "docs": docs_requirements,
        "all": dev_requirements + test_requirements + docs_requirements
    },

    # Package Classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: Internet :: WWW/HTTP :: Session",
        "Topic :: Database :: Database Engines/Servers",
        "Framework :: AWS CDK",
        "Environment :: Console",
        "Natural Language :: English"
    ],

    # Keywords for discovery
    keywords=[
        "aws", "cdk", "session-management", "memorydb", "redis", 
        "load-balancer", "ecs", "fargate", "infrastructure", 
        "distributed-systems", "scalability", "high-availability"
    ],

    # Entry Points
    entry_points={
        "console_scripts": [
            "deploy-session-management=app:main",
        ],
    },

    # Package Data
    package_data={
        "": [
            "*.json",
            "*.yaml",
            "*.yml",
            "*.md",
            "*.txt",
            "*.cfg",
            "*.ini"
        ]
    },

    # Additional Metadata
    license="Apache License 2.0",
    platforms=["any"],
    
    # Test Configuration
    test_suite="tests",
    tests_require=test_requirements,
    
    # Build Configuration
    cmdclass={},
    
    # Distutils Configuration
    options={
        "bdist_wheel": {
            "universal": False
        }
    }
)


# Additional setup for CDK-specific requirements
def _post_install():
    """
    Post-installation setup for CDK environment
    
    This function handles CDK-specific setup that may be needed
    after package installation.
    """
    import subprocess
    import sys
    import os
    
    try:
        # Check if CDK CLI is available
        subprocess.run(
            ["cdk", "--version"], 
            check=True, 
            capture_output=True, 
            text=True
        )
        print("✅ AWS CDK CLI is available")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("⚠️  AWS CDK CLI not found. Please install it using:")
        print("   npm install -g aws-cdk")
        print("   or visit: https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html")
    
    # Check for AWS CLI
    try:
        subprocess.run(
            ["aws", "--version"], 
            check=True, 
            capture_output=True, 
            text=True
        )
        print("✅ AWS CLI is available")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("⚠️  AWS CLI not found. Please install it using:")
        print("   pip install awscli")
        print("   or visit: https://aws.amazon.com/cli/")
    
    # Check for Docker (needed for CDK asset bundling)
    try:
        subprocess.run(
            ["docker", "--version"], 
            check=True, 
            capture_output=True, 
            text=True
        )
        print("✅ Docker is available")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("⚠️  Docker not found. Some CDK features may not work.")
        print("   Please install Docker from: https://www.docker.com/get-started")

    print("\n🚀 Setup completed! You can now deploy the CDK application using:")
    print("   cdk bootstrap  # First time only")
    print("   cdk deploy")


# Run post-install checks if this is being installed
if __name__ == "__main__":
    import sys
    if "install" in sys.argv or "develop" in sys.argv:
        try:
            _post_install()
        except Exception as e:
            print(f"⚠️  Post-install setup encountered an issue: {e}")
            print("   You can continue with manual setup if needed.")