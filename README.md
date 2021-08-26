
# Continuous Deployment with NixOps and Hercules CI

A state-of-the-art deployment with [cloud state and locking](https://github.com/hercules-ci/nixops-hercules-ci) and deployment via hercules-ci-agent.

Status: experimental because NixOps 2 is.

## First deployment

Use the flake's `nix develop` shell.

Copy the repo and follow the steps in [cloud state and locking](https://github.com/hercules-ci/nixops-hercules-ci)

## Run NixOps

Add your AWS credentials in a profile named `nixops-example`. In `~/.aws/credentials`, add:

```ini
[nixops-example]
aws_access_key_id = AK...
aws_secret_access_key = ...
```

## Run CD

Add a secret to your agent(s):

```json
  "nixops-example-aws": {
    "kind": "Secret",
    "data": {
      "aws_secret_access_key": "...",
      "aws_access_key_id": "AK..."
    }
  }
```

Push to the `main` branch to trigger a deployment.

Other branches will only pre-build the deployment, not run it. Look for `effects.runIf`.

## Run CD effect locally without hercules-ci-agent

Use the `nix develop` shell.

First time, run `hci secret init-local` and add your AWS credentials to the path.

```json
{
  "nixops-example-aws": {
    "kind": "Secret",
    "data": {
      "aws_secret_access_key": "...",
      "aws_access_key_id": "AK..."
    }
  }
}
```

Then run

```
hci effect run deployments.production.run
```
