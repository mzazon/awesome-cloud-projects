"""
Setup configuration for AWS CDK Python application for automated
file lifecycle management with Amazon FSx Intelligent-Tiering and Lambda.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

setuptools.setup(
    name="fsx-lifecycle-management",
    version="1.0.0",
    description="AWS CDK Python application for automated file lifecycle management with Amazon FSx and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws/aws-cdk",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    install_requires=[
        "aws-cdk-lib==2.170.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=6.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.950",
        ]
    },
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    entry_points={
        "console_scripts": [
            "fsx-lifecycle=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    keywords=[
        "aws",
        "cdk",
        "fsx",
        "lambda",
        "lifecycle",
        "automation",
        "storage",
        "intelligent-tiering",
        "cost-optimization",
    ],
)