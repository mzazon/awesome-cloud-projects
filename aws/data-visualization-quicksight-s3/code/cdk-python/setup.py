"""
Setup configuration for AWS CDK Python Data Visualization Pipeline application.

This setup.py file configures the Python package for the data visualization pipeline
CDK application, including dependencies, metadata, and entry points.
"""

import setuptools
from typing import List


def get_version() -> str:
    """Get version from VERSION file or default."""
    try:
        with open("VERSION", "r", encoding="utf-8") as version_file:
            return version_file.read().strip()
    except FileNotFoundError:
        return "1.0.0"


def get_long_description() -> str:
    """Get long description from README file."""
    try:
        with open("README.md", "r", encoding="utf-8") as readme_file:
            return readme_file.read()
    except FileNotFoundError:
        return """
        # Data Visualization Pipeline with QuickSight and S3
        
        This CDK Python application creates a comprehensive data visualization pipeline using:
        - Amazon S3 for data storage
        - AWS Glue for data cataloging and ETL
        - Amazon Athena for serverless querying
        - Amazon QuickSight for data visualization
        - AWS Lambda for automation
        
        The pipeline automatically processes data uploads, maintains data catalogs,
        and enables self-service analytics through QuickSight dashboards.
        """


def get_requirements() -> List[str]:
    """Get requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as requirements_file:
            requirements = []
            for line in requirements_file:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback to minimal requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.160.0",
            "constructs>=10.0.0"
        ]


setuptools.setup(
    name="data-visualization-pipeline-cdk",
    version=get_version(),
    
    # Metadata
    description="AWS CDK Python application for Data Visualization Pipelines with QuickSight",
    long_description=get_long_description(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Generator",
    author_email="support@example.com",
    
    # Project URLs
    url="https://github.com/example/data-visualization-pipeline-cdk",
    project_urls={
        "Bug Reports": "https://github.com/example/data-visualization-pipeline-cdk/issues",
        "Source": "https://github.com/example/data-visualization-pipeline-cdk",
        "Documentation": "https://github.com/example/data-visualization-pipeline-cdk/blob/main/README.md",
    },
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    
    # Dependencies
    install_requires=get_requirements(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Operating System :: OS Independent",
    ],
    
    # Keywords for search
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "data-visualization",
        "quicksight",
        "s3",
        "glue",
        "athena",
        "analytics",
        "etl",
        "data-pipeline"
    ],
    
    # Entry points for command-line tools (optional)
    entry_points={
        "console_scripts": [
            "data-viz-pipeline=app:main",
        ],
    },
    
    # Additional data files
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Exclude patterns
    exclude_package_data={
        "": ["tests/*", "*.pyc", "__pycache__/*"],
    },
    
    # Zip safe setting
    zip_safe=False,
    
    # Additional options
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)