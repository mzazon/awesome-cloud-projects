"""
Setup configuration for Computer Vision Applications with Amazon Rekognition
AWS CDK Python Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read README.md file for long description."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "Computer Vision Applications with Amazon Rekognition - CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    requirements.append(line)
    
    return requirements

# Package metadata
PACKAGE_NAME = "computer-vision-rekognition-cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK Python application for computer vision with Amazon Rekognition"
AUTHOR = "AWS Solutions Architect"
AUTHOR_EMAIL = "solutions@amazon.com"
URL = "https://github.com/aws-samples/computer-vision-rekognition-cdk"

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Package classifiers
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: Internet :: WWW/HTTP",
    "Topic :: Scientific/Engineering :: Artificial Intelligence",
    "Topic :: Scientific/Engineering :: Image Recognition",
    "Topic :: System :: Distributed Computing",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "cloud",
    "infrastructure",
    "computer-vision",
    "rekognition",
    "machine-learning",
    "image-analysis",
    "video-analysis",
    "facial-recognition",
    "object-detection",
    "serverless",
    "kinesis",
    "s3",
    "lambda",
    "api-gateway"
]

# Package setup configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    
    # Package discovery
    packages=find_packages(exclude=["tests*", "docs*"]),
    include_package_data=True,
    
    # Python version requirements
    python_requires=PYTHON_REQUIRES,
    
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
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
            "myst-parser>=0.19.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ]
    },
    
    # Package metadata
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    license="MIT",
    
    # Entry points
    entry_points={
        "console_scripts": [
            "deploy-computer-vision=app:main",
        ],
    },
    
    # Package data
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml"
        ]
    },
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/rekognition/",
        "Source": "https://github.com/aws-samples/computer-vision-rekognition-cdk",
        "Tracker": "https://github.com/aws-samples/computer-vision-rekognition-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon Rekognition": "https://aws.amazon.com/rekognition/",
    },
)

# Additional setup information
if __name__ == "__main__":
    print(f"Setting up {PACKAGE_NAME} v{VERSION}")
    print(f"Description: {DESCRIPTION}")
    print(f"Python version requirement: {PYTHON_REQUIRES}")
    print(f"Dependencies: {len(read_requirements())} packages")