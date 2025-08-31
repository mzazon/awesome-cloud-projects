"""
Setup configuration for the URL Shortener CDK Python application.

This file defines the package metadata and dependencies for the CDK application.
It enables proper packaging and distribution of the CDK code.
"""

import setuptools

# Read the README file for the long description
with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setuptools.setup(
    name="url-shortener-cdk",
    version="1.0.0",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="AWS CDK Python application for a serverless URL shortener",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/your-username/url-shortener-cdk",
    
    project_urls={
        "Bug Tracker": "https://github.com/your-username/url-shortener-cdk/issues",
        "Documentation": "https://github.com/your-username/url-shortener-cdk/blob/main/README.md",
        "Source": "https://github.com/your-username/url-shortener-cdk",
    },
    
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: System :: Systems Administration",
    ],
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    python_requires=">=3.8",
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "boto3-stubs[essential]>=1.26.0",
            "mypy>=1.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "pylint>=2.15.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "moto>=4.0.0",
            "requests>=2.28.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "url-shortener-cdk=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "serverless",
        "url-shortener",
        "api-gateway",
        "lambda",
        "dynamodb",
        "infrastructure-as-code",
    ],
    
    zip_safe=False,
    include_package_data=True,
)