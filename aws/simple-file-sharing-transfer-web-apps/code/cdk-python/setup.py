"""
Setup configuration for Simple File Sharing with Transfer Family Web Apps CDK Application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
def read_long_description():
    """Read the long description from README.md if it exists."""
    readme_path = Path(__file__).parent / "README.md"
    if readme_path.exists():
        with open(readme_path, "r", encoding="utf-8") as fh:
            return fh.read()
    return "Simple File Sharing with Transfer Family Web Apps - CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = Path(__file__).parent / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, "r", encoding="utf-8") as fh:
            lines = fh.readlines()
        
        # Filter out comments and development dependencies
        requirements = []
        for line in lines:
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("pytest") and not line.startswith("black") and not line.startswith("flake8") and not line.startswith("mypy") and not line.startswith("bandit") and not line.startswith("types-") and not line.startswith("boto3-stubs"):
                requirements.append(line)
        return requirements
    
    # Fallback to core requirements if file doesn't exist
    return [
        "aws-cdk-lib>=2.150.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ]

setuptools.setup(
    name="simple-file-sharing-transfer-web-apps",
    version="1.0.0",
    
    # Metadata
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="Simple File Sharing with Transfer Family Web Apps - CDK Python Application",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/simple-file-sharing-transfer-web-apps",
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "boto3-stubs[s3,transfer,iam,sso,identitystore,s3control]>=1.34.0",
            "types-setuptools>=65.0.0",
        ]
    },
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    # Keywords for searching
    keywords="aws cdk transfer-family s3 file-sharing web-apps identity-center access-grants",
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "deploy-file-sharing=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/simple-file-sharing-transfer-web-apps/issues",
        "Source": "https://github.com/aws-samples/simple-file-sharing-transfer-web-apps",
        "Documentation": "https://github.com/aws-samples/simple-file-sharing-transfer-web-apps/README.md",
    },
)