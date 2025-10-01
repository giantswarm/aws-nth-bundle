# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.3] - 2025-10-01

### Changed

- Upgrade aws-nth-crossplane-resources to v1.1.1, supporting multiple OIDC providers in the NTH IAM role as required for cleanup of migrated vintage clusters

## [1.2.2] - 2025-07-03

### Changed

- Upgrade Node Termination Handler to 1.21.0.

## [1.2.1] - 2025-01-23

### Added

- Forward proxy settings to `aws-node-termination-handler-app` as environment variables

## [1.2.0] - 2024-12-11

### Added

- Send spot instance interruption and instance state change events to SQS queue so that aws-node-termination-handler can react to them

## [1.1.1] - 2024-12-04

### Changed

- Add dependency for servicemonitors

## [1.1.0] - 2024-12-04

### Changed

- Move to default catalog

## [1.0.0] - 2024-10-30

- First release

[Unreleased]: https://github.com/giantswarm/aws-nth-bundle/compare/v1.2.3...HEAD
[1.2.3]: https://github.com/giantswarm/aws-nth-bundle/compare/v1.2.2...v1.2.3
[1.2.2]: https://github.com/giantswarm/aws-nth-bundle/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/giantswarm/aws-nth-bundle/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/giantswarm/aws-nth-bundle/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/giantswarm/aws-nth-bundle/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/giantswarm/aws-nth-bundle/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/giantswarm/aws-nth-bundle/releases/tag/v1.0.0
