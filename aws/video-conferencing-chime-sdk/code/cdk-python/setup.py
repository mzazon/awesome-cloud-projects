"""
Setup configuration for Amazon Chime SDK Video Conferencing CDK Python Application.

This package contains the AWS CDK Python infrastructure code for deploying
a complete video conferencing solution using Amazon Chime SDK.
"""

from setuptools import setup, find_packages
import os

# Read the contents of README file
def read_long_description():
    """Read the long description from README.md if it exists."""
    this_directory = os.path.abspath(os.path.dirname(__file__))
    readme_path = os.path.join(this_directory, 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, encoding='utf-8') as f:
            return f.read()
    return "Amazon Chime SDK Video Conferencing CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    if os.path.exists(requirements_path):
        with open(requirements_path, 'r') as f:
            return [
                line.strip() 
                for line in f.readlines() 
                if line.strip() and not line.startswith('#')
            ]
    return []

setup(
    name="chime-sdk-video-conferencing-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Amazon Chime SDK Video Conferencing Solution",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="aws-cdk-generator@example.com",
    url="https://github.com/aws-samples/chime-sdk-video-conferencing-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    package_dir={"": "."},
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "bandit>=1.7.0",
            "safety>=3.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ]
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Communications :: Video Conferencing",
        "Topic :: System :: Systems Administration",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "amazon-chime-sdk",
        "video-conferencing",
        "webrtc",
        "real-time-communication",
        "serverless",
        "lambda",
        "api-gateway",
        "dynamodb",
        "s3",
        "sns",
        "cloudformation",
        "infrastructure-as-code",
        "iac"
    ],
    
    # License
    license="Apache-2.0",
    
    # Include additional files
    include_package_data=True,
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/chime-sdk-video-conferencing-cdk/issues",
        "Source": "https://github.com/aws-samples/chime-sdk-video-conferencing-cdk",
        "Documentation": "https://docs.aws.amazon.com/chime-sdk/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon Chime SDK": "https://aws.amazon.com/chime/chime-sdk/",
    },
)