"""
Setup configuration for Simple Website Uptime Monitoring CDK Application

This setup.py file configures the Python package for the CDK application
that creates an automated uptime monitoring system using Route53 health
checks, CloudWatch alarms, and SNS email notifications.

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import setuptools

# Read the long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Simple Website Uptime Monitoring with Route53 and SNS"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh 
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="uptime-monitoring-cdk",
    version="1.0.0",
    
    author="AWS CDK Recipe Generator",
    author_email="admin@example.com",
    
    description="CDK application for automated website uptime monitoring",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/recipes",
    
    packages=setuptools.find_packages(),
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: System :: Networking :: Monitoring",
    ],
    
    python_requires=">=3.8",
    install_requires=requirements,
    
    # Entry points for command-line tools (if needed)
    entry_points={
        "console_scripts": [
            "uptime-monitoring=app:main",
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "requirements.txt"],
    },
    
    # Development dependencies (extras_require)
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=23.0.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.0.0,<2.0.0",
            "types-requests>=2.31.0",
        ],
        "test": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "moto>=4.2.0,<5.0.0",  # AWS service mocking for tests
        ],
    },
    
    # Project URLs for PyPI
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "Source": "https://github.com/aws-samples/recipes",
        "Documentation": "https://github.com/aws-samples/recipes/blob/main/aws/simple-uptime-monitoring-route53-sns/simple-uptime-monitoring-route53-sns.md",
    },
    
    # Keywords for PyPI search
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "route53",
        "sns",
        "cloudwatch",
        "monitoring",
        "uptime",
        "health-check",
        "alerting",
        "infrastructure-as-code",
        "devops",
    ],
    
    # License
    license="MIT",
    
    # Zip safe
    zip_safe=False,
)