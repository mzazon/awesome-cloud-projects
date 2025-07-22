"""
Setup configuration for AWS CDK Python Chaos Engineering Application.

This setup.py file configures the Python package for the chaos engineering
infrastructure deployment using AWS CDK, FIS, and EventBridge.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Returns:
        List[str]: List of package requirements
    """
    try:
        with open("requirements.txt", "r", encoding="utf-8") as file:
            requirements = file.read().splitlines()
        # Filter out comments and empty lines
        return [
            req.strip() 
            for req in requirements 
            if req.strip() and not req.strip().startswith("#")
        ]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.100.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0"
        ]


def read_long_description() -> str:
    """
    Read the long description from README.md if available.
    
    Returns:
        str: Long description for the package
    """
    try:
        with open("README.md", "r", encoding="utf-8") as file:
            return file.read()
    except FileNotFoundError:
        return """
        AWS CDK Python Application for Chaos Engineering with FIS and EventBridge
        
        This CDK application deploys a complete chaos engineering solution using AWS Fault 
        Injection Service (FIS) integrated with EventBridge for automated scheduling and 
        monitoring. The infrastructure includes CloudWatch alarms for safety mechanisms, 
        SNS notifications, and monitoring dashboards.
        """


setuptools.setup(
    name="chaos-engineering-fis-eventbridge",
    version="1.0.0",
    
    description="AWS CDK Python application for chaos engineering with FIS and EventBridge",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    
    url="https://github.com/aws-samples/chaos-engineering-fis-eventbridge",
    
    packages=setuptools.find_packages(),
    
    install_requires=read_requirements(),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Monitoring",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "chaos-engineering",
        "fault-injection",
        "fis",
        "eventbridge",
        "cloudwatch",
        "resilience",
        "testing",
        "infrastructure"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/chaos-engineering-fis-eventbridge/issues",
        "Source": "https://github.com/aws-samples/chaos-engineering-fis-eventbridge",
        "Documentation": "https://docs.aws.amazon.com/fis/",
    },
    
    # Entry points for command line tools (if any)
    entry_points={
        "console_scripts": [
            # "chaos-deploy=app:main",  # Uncomment if you want CLI tools
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Include package data
    include_package_data=True,
    
    # Zip safe
    zip_safe=False,
    
    # Test suite
    test_suite="tests",
    
    # Testing requirements
    tests_require=[
        "pytest>=6.2.4",
        "pytest-cov>=2.12.1",
        "moto>=4.0.0",  # For mocking AWS services in tests
    ],
    
    # Development requirements
    extras_require={
        "dev": [
            "pytest>=6.2.4",
            "pytest-cov>=2.12.1",
            "black>=21.0.0",
            "flake8>=3.9.0",
            "mypy>=0.812",
            "bandit>=1.7.0",
            "safety>=1.10.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=0.5.0",
        ],
    },
)