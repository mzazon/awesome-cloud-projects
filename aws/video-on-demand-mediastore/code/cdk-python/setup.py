"""
Setup configuration for Video-on-Demand Platform CDK Python application.

This setup file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

import setuptools
from pathlib import Path

# Read README for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ]

setuptools.setup(
    name="vod-platform-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Video-on-Demand Platform with MediaStore",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache License 2.0",
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: Information Technology",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Multimedia :: Video",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Distributed Computing",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "video",
        "streaming",
        "mediastore",
        "cloudfront",
        "vod",
        "content-delivery"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.26.0",
            "types-requests>=2.28.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "vod-platform-cdk=app:main",
        ],
    },
    
    include_package_data=True,
    
    zip_safe=False,
)