"""
Setup configuration for AWS CDK Python IoT Greengrass application

This setup.py file configures the Python package for the IoT Greengrass
edge computing CDK application, including all dependencies and metadata.
"""

import setuptools

# Read the long description from README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for IoT Greengrass edge computing infrastructure"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setuptools.setup(
    name="iot-greengrass-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS Cloud Developer",
    author_email="developer@example.com",
    description="AWS CDK Python application for IoT Greengrass edge computing",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/iot-greengrass-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(),
    
    # Dependencies
    install_requires=requirements,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package classifiers
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "deploy-greengrass=app:main",
        ],
    },
    
    # Include package data
    include_package_data=True,
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "iot",
        "greengrass",
        "edge-computing",
        "lambda",
        "infrastructure",
        "cloud",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/iot-greengrass-cdk/issues",
        "Source": "https://github.com/aws-samples/iot-greengrass-cdk",
        "Documentation": "https://docs.aws.amazon.com/greengrass/",
    },
)