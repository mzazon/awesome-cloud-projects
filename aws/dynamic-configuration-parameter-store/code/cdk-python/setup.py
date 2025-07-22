"""
Dynamic Configuration Management CDK Package Setup

This package provides AWS CDK constructs for implementing dynamic configuration 
management using AWS Systems Manager Parameter Store, Lambda, and EventBridge.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="dynamic-config-management-cdk",
    version="1.0.0",
    author="AWS Recipes",
    author_email="recipes@example.com",
    description="CDK constructs for Dynamic Configuration with Parameter Store",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-recipes/dynamic-configuration-management",
    project_urls={
        "Bug Tracker": "https://github.com/aws-recipes/dynamic-configuration-management/issues",
        "Documentation": "https://github.com/aws-recipes/dynamic-configuration-management/wiki",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.9",
    install_requires=[
        "aws-cdk-lib>=2.170.0",
        "constructs>=10.0.0,<11.0.0",
        "cdk-nag>=2.28.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.12.0",
            "isort>=5.13.0",
            "mypy>=1.8.0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-synth=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)