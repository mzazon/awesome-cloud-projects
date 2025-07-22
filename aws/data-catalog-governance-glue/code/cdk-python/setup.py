"""
Setup configuration for Data Catalog Governance CDK Python application.

This package implements a comprehensive data governance solution using AWS Glue
Data Catalog, Lake Formation, CloudTrail, and CloudWatch for automated data
classification, access control, and audit logging.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [
        line.strip() 
        for line in f 
        if line.strip() and not line.startswith("#")
    ]

# Read long description from README (if exists)
long_description = """
AWS CDK Python Application for Data Catalog Governance

This application implements a comprehensive data governance solution using:

- AWS Glue Data Catalog for metadata management
- AWS Glue Crawler for automated data discovery
- Custom PII classifiers for sensitive data identification
- Lake Formation for fine-grained access control
- CloudTrail for comprehensive audit logging
- CloudWatch for monitoring and alerting

Features:
- Automated PII detection and classification
- Role-based access control with Lake Formation
- Comprehensive audit trails for compliance
- Real-time monitoring dashboards
- Scalable architecture for enterprise use

The solution follows AWS Well-Architected Framework principles and
implements security best practices for data governance.
"""

setup(
    name="data-catalog-governance-cdk",
    version="1.0.0",
    description="AWS CDK Python application for comprehensive data governance with AWS Glue",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="noreply@amazonaws.com",
    python_requires=">=3.8",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=22.0.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.0.0,<2.0.0",
            "isort>=5.0.0,<6.0.0",
        ],
        "test": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "moto>=4.0.0,<5.0.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "data-catalog-governance=app:main",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Database",
        "Topic :: Security",
        "Topic :: System :: Monitoring",
    ],
    
    # Keywords for PyPI
    keywords=[
        "aws",
        "cdk",
        "glue",
        "data-catalog",
        "governance",
        "lake-formation",
        "cloudtrail",
        "pii",
        "compliance",
        "security",
        "data-classification",
        "audit",
        "monitoring",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/glue/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Additional metadata
    license="MIT",
    platforms=["any"],
)