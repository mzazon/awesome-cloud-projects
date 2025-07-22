"""
Setup configuration for Fine-Grained API Authorization CDK Python Application
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="fine-grained-api-authorization",
    version="1.0.0",
    author="AWS CDK Python",
    author_email="",
    description="Fine-Grained API Authorization with Amazon Verified Permissions and Cognito",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "PyJWT>=2.8.0,<3.0.0",
        "cryptography>=41.0.7,<42.0.0",
    ],
    python_requires=">=3.8",
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "mypy>=1.5.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
        ]
    },
)