"""
Setup configuration for CDK Python application for automated multi-account resource discovery.
"""

import setuptools


with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()


setuptools.setup(
    name="multi-account-resource-discovery",
    version="1.0.0",
    
    description="CDK Python application for automated multi-account resource discovery with Resource Explorer and Config",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
        "boto3>=1.26.0",
        "python-dateutil>=2.8.0",
    ],
    
    python_requires=">=3.7",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    keywords="aws cdk python resource-explorer config multi-account discovery compliance automation",
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
)