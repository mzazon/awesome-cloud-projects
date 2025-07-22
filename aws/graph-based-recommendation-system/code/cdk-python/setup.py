"""
Setup configuration for Neptune Graph Database CDK Application

This setup file configures the Python package for the Neptune recommendation
engine CDK application, including all dependencies and metadata.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="neptune-graph-recommendations-cdk",
    version="1.0.0",
    
    description="AWS CDK application for Neptune graph database recommendation engine",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk-dev@amazon.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=[
        "aws-cdk-lib>=2.114.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "gremlinpython>=3.7.0",
        "boto3>=1.28.0",
        "requests>=2.28.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-requests>=2.28.0",
        ]
    },
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
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
    
    keywords="aws cdk neptune graph database recommendation engine gremlin",
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
)