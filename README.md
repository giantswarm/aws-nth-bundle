[![CircleCI](https://dl.circleci.com/status-badge/img/gh/giantswarm/aws-nth-bundle/tree/main.svg?style=svg)](https://dl.circleci.com/status-badge/redirect/gh/giantswarm/aws-nth-bundle/tree/main)

# AWS Node Termination Handler Bundle

This app is a bundle that contains 2 Apps:

### Node Termination Handler
Deployment running on the Workload cluster that will react to Termination events on SQS and drain nodes before sending a signal to continue the Termination.

[Repository](https://github.com/giantswarm/aws-node-termination-handler-app)

### Node Termination Handler Crossplane Resources
Contains AWS resources needed for the Node Termination Handler including IAM Roles, IAM Policies and SQS queue.

[Repository](https://github.com/giantswarm/aws-nth-crossplane-resources)

