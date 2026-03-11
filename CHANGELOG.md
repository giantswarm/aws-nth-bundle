# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Migrate sub-apps from App CRs to Flux HelmRelease CRs.
- Add `io.giantswarm.application.audience: all` annotation to publish the app to the customer Backstage catalog.
- Migrate chart metadata annotations to `io.giantswarm.application.*` format.

## [1.3.0] - 2025-10-07

### Changed

- Upgrade aws-nth-crossplane-resources to v1.3.0, fixing support for multiple OIDC providers in the NTH IAM role as required for cleanup of migrated vintage clusters, and supporting heartbeat sending
- Upgrade aws-node-termination-handler-app to v1.23.0, enabling heartbeats by default and upgrading to upstream application version v1.25.2 which fixes a resource leak bug relevant to heartbeat sending

[Unreleased]: https://github.com/giantswarm/aws-nth-bundle/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/giantswarm/aws-nth-bundle/compare/v1.2.3...v1.3.0
