# Shared server

This repository describes the Oracle Cloud VM that will host Snap first. Terraform defines the cloud resources, cloud-init sets up Ubuntu on first boot, and Traefik routes HTTPS to project containers.

## Free-only rule

Use Oracle Always Free in the tenancy's home region. Keep the tenancy on the free tier and check the available quota in Oracle before applying, including resources outside this repository. The starting VM uses 1 of 2 OCPUs, 4 of 12 GB RAM, and 50 of 200 GB block storage. The two private buckets share the tenancy's 20 GB of Object Storage and 50,000 monthly requests. Keep those limits during the trial too.

The Oracle API signing key and the S3 customer secret key are created by hand. Keep the signing key in the local OCI configuration, the customer secret key in the application environment, and Terraform state local. The repository tracks the provider lock file.

## How it works

- [The server](docs/how-it-works/server.md) covers Terraform, first boot, network rules, quota, and private storage.
- [The edge](docs/how-it-works/edge.md) shows how Traefik routes traffic and how a project joins it.
