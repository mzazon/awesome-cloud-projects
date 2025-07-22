"""
Setup configuration for AWS CDK Python Video Workflow Orchestration Application

This setup.py file defines the package configuration, dependencies, and metadata
for the automated video workflow orchestration CDK application. It enables
proper packaging, distribution, and dependency management for the CDK project.

The application deploys a comprehensive video processing pipeline using:
- AWS Step Functions for workflow orchestration
- AWS MediaConvert for video transcoding
- AWS Lambda for custom processing logic
- Amazon S3 for storage and content delivery
- Amazon DynamoDB for job tracking
- Amazon API Gateway for REST API endpoints
- Amazon SNS for notifications
- Amazon CloudWatch for monitoring

Author: AWS CDK Generator
Version: 1.0.0
License: MIT
"""

import os
import re
from typing import List, Dict, Any

from setuptools import setup, find_packages


def get_version() -> str:
    """
    Extract version from the package __init__.py or use default.
    
    Returns:
        str: Package version string
    """
    version_file = os.path.join(os.path.dirname(__file__), 'video_workflow', '__init__.py')
    if os.path.exists(version_file):
        with open(version_file, 'r', encoding='utf-8') as f:
            version_match = re.search(r"^__version__ = ['\"]([^'\"]*)['\"]", f.read(), re.M)
            if version_match:
                return version_match.group(1)
    return "1.0.0"


def get_long_description() -> str:
    """
    Get long description from README file.
    
    Returns:
        str: Long description for package
    """
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    
    return """
    Automated Video Workflow Orchestration with AWS CDK Python
    
    This CDK application deploys a comprehensive serverless video processing pipeline
    that automatically transcodes, validates, and publishes video content using AWS
    Step Functions for orchestration.
    
    Key Features:
    - Automated video transcoding with MediaConvert
    - Quality control validation with Lambda functions
    - Parallel processing for optimal performance
    - S3 event-driven workflow triggering
    - RESTful API for programmatic access
    - Real-time monitoring and notifications
    - Cost-optimized Express Workflows
    """


def get_requirements() -> List[str]:
    """
    Parse requirements from requirements.txt file.
    
    Returns:
        List[str]: List of package requirements
    """
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Handle conditional requirements
                    if ';' in line:
                        requirement, condition = line.split(';', 1)
                        requirements.append(f"{requirement.strip()};{condition.strip()}")
                    else:
                        requirements.append(line)
    
    return requirements


def get_dev_requirements() -> List[str]:
    """
    Get development-specific requirements.
    
    Returns:
        List[str]: List of development requirements
    """
    dev_requirements_path = os.path.join(os.path.dirname(__file__), 'requirements-dev.txt')
    if os.path.exists(dev_requirements_path):
        with open(dev_requirements_path, 'r', encoding='utf-8') as f:
            return [line.strip() for line in f if line.strip() and not line.startswith('#')]
    
    # Default development requirements if file doesn't exist
    return [
        'pytest>=7.4.0',
        'pytest-cov>=4.1.0',
        'black>=23.0.0',
        'flake8>=6.0.0',
        'mypy>=1.0.0',
        'bandit>=1.7.5',
        'safety>=2.3.0',
        'sphinx>=7.0.0',
        'sphinx-rtd-theme>=1.3.0'
    ]


# Package metadata
PACKAGE_NAME = "video-workflow-orchestration-cdk"
PACKAGE_VERSION = get_version()
AUTHOR = "AWS CDK Generator"
AUTHOR_EMAIL = "aws-cdk@example.com"
DESCRIPTION = "Automated Video Workflow Orchestration with AWS CDK Python"
LONG_DESCRIPTION = get_long_description()
LONG_DESCRIPTION_CONTENT_TYPE = "text/markdown"
URL = "https://github.com/aws-samples/video-workflow-orchestration-cdk"
PROJECT_URLS = {
    "Documentation": "https://docs.aws.amazon.com/cdk/",
    "Source": "https://github.com/aws-samples/video-workflow-orchestration-cdk",
    "Tracker": "https://github.com/aws-samples/video-workflow-orchestration-cdk/issues",
}

# Package classification
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "Intended Audience :: Information Technology",
    "Intended Audience :: System Administrators",
    "License :: OSI Approved :: MIT License",
    "Operating System :: OS Independent",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Internet :: WWW/HTTP",
    "Topic :: Multimedia :: Video",
    "Topic :: Multimedia :: Video :: Conversion",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Distributed Computing",
    "Topic :: System :: Systems Administration",
    "Typing :: Typed",
]

# Keywords for package discovery
KEYWORDS = [
    "aws", "cdk", "cloud", "infrastructure", "video", "processing", "transcoding",
    "mediaconvert", "stepfunctions", "lambda", "s3", "dynamodb", "apigateway",
    "orchestration", "workflow", "automation", "serverless", "media", "streaming"
]

# Python version requirements
PYTHON_REQUIRES = ">=3.8"

# Entry points for command-line tools
ENTRY_POINTS = {
    "console_scripts": [
        "video-workflow-deploy=video_workflow.cli:deploy",
        "video-workflow-destroy=video_workflow.cli:destroy",
        "video-workflow-status=video_workflow.cli:status",
    ]
}

# Package data to include
PACKAGE_DATA = {
    "video_workflow": [
        "templates/*.json",
        "templates/*.yaml",
        "config/*.yaml",
        "config/*.json",
        "schemas/*.json",
    ]
}

# Additional setup arguments
SETUP_KWARGS: Dict[str, Any] = {
    "zip_safe": False,
    "include_package_data": True,
    "install_requires": get_requirements(),
    "extras_require": {
        "dev": get_dev_requirements(),
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "requests>=2.31.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
            "sphinx-autodoc-typehints>=1.24.0",
        ],
        "security": [
            "bandit>=1.7.5",
            "safety>=2.3.0",
            "pip-audit>=2.6.0",
        ]
    },
    "platforms": ["any"],
    "project_urls": PROJECT_URLS,
    "package_data": PACKAGE_DATA,
    "entry_points": ENTRY_POINTS,
}


def main():
    """Main setup function."""
    setup(
        name=PACKAGE_NAME,
        version=PACKAGE_VERSION,
        author=AUTHOR,
        author_email=AUTHOR_EMAIL,
        description=DESCRIPTION,
        long_description=LONG_DESCRIPTION,
        long_description_content_type=LONG_DESCRIPTION_CONTENT_TYPE,
        url=URL,
        packages=find_packages(exclude=["tests", "tests.*"]),
        classifiers=CLASSIFIERS,
        keywords=KEYWORDS,
        python_requires=PYTHON_REQUIRES,
        **SETUP_KWARGS
    )


if __name__ == "__main__":
    main()