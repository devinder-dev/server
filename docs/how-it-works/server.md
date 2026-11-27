# The server

The shared VM needs repeatable cloud resources and a predictable first boot. Terraform asks Oracle for the network, VM, and buckets. Cloud-init sets up Ubuntu inside the VM.

```text
Mac -> Terraform -> OCI compartment
                     |-- VCN -> public subnet -> apps VM -> cloud-init
                     |-- photos bucket <- photos app user (S3 key) -> group -> policy
                     `-- backups bucket

Browser -> internet gateway -> OCI security list -> Ubuntu / Docker -> Traefik
```

## What Terraform creates

- A **tenancy** is the Oracle account boundary. A **compartment** is a folder for resources inside it. Use a dedicated existing compartment, such as `shared-server`. An **OCID** is Oracle's unique identifier for either one.
- A **VCN** is a private cloud network. The **subnet** is a smaller address range in it, such as `10.11.1.0/24`. A VM has a private address there and a public IPv4 for incoming connections.
- An **internet gateway** links the VCN to the internet. The **route table** sends IPv4 traffic for destinations outside the VCN to that gateway.
- The **security list** is the subnet's cloud firewall. It accepts new inbound TCP connections on 22 (SSH), 80 (HTTP), and 443 (HTTPS). ICMP type 3/code 4 tells a sender a packet is too large and needs to be split into smaller packets. Stateful rules allow replies to permitted traffic.
- An **availability domain** is a group of data centers in a region. `availability_domain_index = 0` selects the first one Oracle returns. Use `1` for the second if the home region has one. Terraform checks the index against the list Oracle returns. The **image** is a stock disk template, such as a Canonical Ubuntu 24.04 LTS Arm build. Terraform looks up the newest standard image in that family for the A1 shape at plan time. Existing VMs keep their original image when the catalog changes.
- A **bucket** is a container for files in Object Storage. **Lifecycle rules** expire photos after two days and previous backup versions after 14 days. **Versioning** keeps the old contents when the same backup key is overwritten. A fresh backup under a new key stays current, so these rules alone do not cap backup size. The **namespace** identifies the tenancy in the S3-compatible URL. Use path-style addressing and the OCI region in the S3 client. The lifecycle service gets permission to delete in the dedicated compartment.
- The **photos app user** (`shared-server-photos-app`) is an account for the application, not a person. An app's **S3 customer secret key** (an access key ID and a secret, like an AWS access key) belongs to a user and can do whatever that user may do. So this user can't log in to the Console or use API keys, auth tokens, or SMTP credentials. Terraform's capabilities resource can't switch off database or OAuth2 client credentials. Only an administrator could create those, and the S3 key reaches Object Storage only. It is in a **group** of the same name, and one **policy** lets that group create, read, and delete objects in the photos bucket and nothing else. Photo names are new random IDs, so overwrite isn't granted. HEAD needs only read. A leaked key can't reach the backups bucket or any other resource. The identity domain requires an email on every user. It goes in `photos_app_email` in the private `terraform.tfvars`. Terraform creates the user but never its key, because a key made by Terraform would be stored in plain text in the state file.

- The **backups app user** (`shared-server-backups-app`) has its own group and email (`backups_app_email` in private tfvars). It can create and overwrite a backup object and read or list its versions in the backups bucket. For example, uploading to `snap/postgres.dump` again keeps the older copy as a previous version. The policy grants `OBJECT_CREATE`, `OBJECT_OVERWRITE`, `OBJECT_READ`, and `OBJECT_INSPECT`. Neither `OBJECT_DELETE` nor `OBJECT_VERSION_DELETE` is granted. Create the S3 customer secret key in the Console for the user identified by `terraform -chdir=terraform output -raw backups_app_user`, and store it in the private backup settings on the VM. Count backup versions against the same shared 20 GB. The 14-day lifecycle applies to previous versions, and the current one stays until an administrator removes it.

[OCI Object Storage permissions](https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/objectstoragepolicyreference.htm)

## The free limits

| Resource | Starts with | Always Free allowance |
| --- | --- | --- |
| A1 compute | 1 OCPU and 4 GB RAM | 1,500 OCPU-hours and 9,000 GB-hours monthly, equivalent to 2 OCPUs and 12 GB running all month |
| A1 boot disk | 50 GB at Balanced performance | 200 GB total across boot and block volumes in the home region |
| Object Storage | Two private Standard buckets | 20 GB total and 50,000 API requests a month across the tenancy |
| VCN, subnet, route table, security list, gateway and VM IPv4 | One of each | Uses the tenancy's networking limits and the shared outbound transfer allowance of 10 TB per month |

An **OCPU** on Ampere A1 is one Arm CPU core. The `vms` map gives each VM a named entry, such as `apps`. Terraform adds the CPU, memory, and boot disks and rejects totals above 2 OCPUs, 12 GB RAM, or 200 GB. With `apps` at 1 OCPU and 4 GB, a later Relay entry can use at most 1 OCPU and 8 GB if the rest of the tenancy has no A1 usage. Relay's k3s stack can then own ports 80 and 443 on its own IP. Before applying, include existing VMs, retained boot disks, block volumes and storage outside this project in the quota check. Stay inside the free limits during the trial, too.

Oracle can reclaim idle A1 instances. Its seven-day test looks at CPU and memory utilization at the 95th percentile and network utilization. A1 can qualify when all three are below 20%. On a 4 GB VM, 0.8 GB is 20%. If Ubuntu, Docker, and Snap use 1.2 GB, that's about 30%. Treat that as a sizing estimate and check Oracle's memory graph after a week of normal use.

[Oracle Always Free limits](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) · [OCI lifecycle rules](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/usinglifecyclepolicies.htm) · [OCI S3 endpoint](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/s3compatibleapi.htm)

## The first boot

**Cloud-init** is Ubuntu's first-boot setup runner. Oracle provides the public SSH key as **metadata**, which is information about the VM available to Ubuntu at boot. Cloud-init installs it for the default user `deploy`. The private key stays on the Mac. Root, password, and keyboard-interactive SSH logins are disabled.

The **Docker group** lets `deploy` run `docker ps` without sudo. Access to Docker is equivalent to root on this host. The same key can also use passwordless sudo for host administration, such as editing a root-only settings file. Treat it as an administrator key.

On OCI, **iptables** is Ubuntu's host firewall. Cloud-init inserts web-port accepts above the image's catch-all reject in both the running rules and `/etc/iptables/rules.v4`. Ubuntu restores the file at boot. On Multipass that file is absent, so the step exits cleanly. Docker sends published ports to containers through its own packet rules. Only Traefik should publish ports.

Ubuntu runs unattended security updates. Docker Engine and the Compose plugin come from Docker's APT repository. **APT** is Ubuntu's package installer. The `Signed-By` setting tells APT which downloaded public key may verify that repository's package index.

Docker's **log driver** stores what containers print. The `local` driver rotates
logs by default. It keeps up to five files of 20 MB each per container and
compresses old files. For example, a busy API keeps about 100 MB of logs before
compression. Cloud-init writes this setting before Docker is installed. It
applies to new containers, so an older VM needs its containers recreated to pick
up a changed driver.

[Docker local log driver](https://docs.docker.com/engine/logging/drivers/local/)

**DuckDNS** keeps a hostname such as `example.duckdns.org` pointed at the public IPv4. The **systemd timer** is Ubuntu's scheduler. It calls DuckDNS every five minutes. DuckDNS detects the public IPv4 of the outbound connection, so the updater works even when Ubuntu sees only its private IP. With no settings file it skips the update.

On OCI, create the settings file as `deploy` after boot. Use an editor so the token stays out of shell history.

```sh
sudo install -m 600 /dev/null /etc/duckdns.env  # First setup only
sudoedit /etc/duckdns.env
sudo systemctl start duckdns.service
systemctl status duckdns.timer
```

Add `DUCKDNS_DOMAIN` (the lowercase name before `.duckdns.org`) and `DUCKDNS_TOKEN` (the account token) as `NAME=value` lines in that file.

[Docker's Ubuntu repository](https://docs.docker.com/engine/install/ubuntu/) · [DuckDNS API](https://www.duckdns.org/spec.jsp)

## Try it yourself

Run the Terraform checks from the repository root. They use the provider package and require no Oracle credentials.

```sh
terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
terraform -chdir=terraform providers lock -platform=linux_amd64 -platform=darwin_arm64
```

For Multipass, render a copy of cloud-init with your public key. This keeps Multipass's `ubuntu` management user and attaches your key only to `deploy`. Run from the repository root and adjust the `.pub` path if needed.

```sh
vm=zzt-server-11a
rendered=$(mktemp)
pub="$HOME/.ssh/id_ed25519.pub"
ruby -ryaml -e '
  config = YAML.safe_load_file("cloud-init.yaml")
  deploy = config.delete("system_info").fetch("default_user")
  deploy["ssh_authorized_keys"] = [File.read(ARGV.fetch(0)).strip]
  config.fetch("users") << deploy
  File.write(ARGV.fetch(1), "#cloud-config\n" + YAML.dump(config))
' "$pub" "$rendered"
multipass launch 24.04 --name "$vm" --cpus 1 --memory 4G --cloud-init "$rendered"
multipass exec "$vm" -- cloud-init status --wait
rm "$rendered"
```

Expect `status: done`. See [The edge](edge.md) for the HTTP test.

When go-live is authorized, the account owner configures the OCI signing key under `~/.oci/`, copies the variables example to `terraform/terraform.tfvars`, and fills in the home region, tenancy, dedicated compartment, and public key. Review `terraform -chdir=terraform plan` and check the Always Free labels and available quota before applying. **State** is Terraform's local record of resource IDs. Keep it private. A **provider lock file** records the downloaded provider version and checksums. Commit `terraform/.terraform.lock.hcl` after generating it. Create the application's S3 customer secret key in the OCI Console for the user named by `terraform -chdir=terraform output photos_app_user`, never for your own user. Oracle shows the secret once. Save it straight into the application's environment file.

### Network and buckets first

Before creating any VMs, replace the VM map in your private `terraform.tfvars`
with `vms = {}`. The SSH key can be omitted for this apply. From the repo root:

```sh
terraform -chdir=terraform plan
terraform -chdir=terraform apply
terraform -chdir=terraform output -json public_ips
```

Review the plan before applying. It should create networking and storage, with
no compute instances or VM image lookup. Expect `{}` for public IPs. Add
`apps` and its public key when ready to boot the VM. On a state that already has
VMs, removing entries is a deletion plan. Use the empty map only for the first
apply or when you intend to remove those VMs.

### Go-live checklist

- After the first OCI boot and once Docker is running, run `sudo iptables -S FORWARD`. Check that Docker's forwarding jumps appear above Oracle's catch-all `REJECT` rule.
- After a reboot, run `sudo iptables -S FORWARD` again and check the same order. If the reject is first, published ports can time out. Multipass uses a different image and cannot verify these Oracle rules.

## What can go wrong

- `Out of host capacity` means the selected availability domain has no A1 capacity. If the home region has another domain, set `availability_domain_index = 1` in `terraform.tfvars` and review the plan before retrying. Changing domains for an existing VM can replace it. If there is only one domain, retry there later.
- `Attempt to index null value` or `Invalid index` at image selection means no matching Arm image was returned. Query Oracle platform images at tenancy scope. A child-compartment lookup returned no images in the live review. If tenancy scope still returns none, check the region, LTS family, and shape.
- An authorization error setting bucket expiry can mean the IAM policy is still propagating. The provider account also needs permission to create the policy at the tenancy level. The policy grants the service access only in the server compartment.
- `400 InvalidParameter` naming `ocid1.compartment.oc1..replace`, or a plan that stops at `compartment_ocid`, means the private `terraform.tfvars` still has the example placeholder. Copy the dedicated compartment's OCID from Oracle.
- `SignatureDoesNotMatch` with "the secret key required to complete authentication could not be found" in the first seconds after generating a customer secret key means Oracle hasn't spread the new key yet. In the live test, the first call failed and later calls with the same key passed. Wait a minute and retry. If it persists, check that the whole secret was saved.
- Oracle answers `404 NoSuchBucket` ("does not exist ... or you are not authorized") when the key lacks permission, so it doesn't reveal which buckets exist. The photos app's key gets that answer for the backups bucket and for listing.
- An S3 `403` with the photos app's key can mean the new policy is still propagating, so retry after a minute. It can also mean an operation needs a permission the policy doesn't grant. Check the bucket name in the policy and the permission list in `app-access.tf`.
- A browser timeout on OCI while SSH works can mean a network or host firewall is blocking web traffic. Check the security list and `sudo iptables -S INPUT`, then check that Traefik is running.
- `Permission denied (publickey)` from the Mac can mean you selected a different private key from the one whose public key was installed.
- A stale DuckDNS record can mean the settings file is missing or the token was rejected. Run `sudo journalctl -u duckdns.service -n 10`. If the token is rejected, the updater logs only a generic failure.
