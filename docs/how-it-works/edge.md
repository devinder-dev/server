# The edge

Only one process can publish ports 80 and 443 on the same IP. Traefik shares those ports between projects. It acts as a **reverse proxy**. For example, it receives a request for `snap-demo.duckdns.org` and forwards it to Snap's container.

```text
Client -> :80 (redirect) -> :443 Traefik -> edge network -> project container
                                    |
                         private docker-api network
                                    |
                          HAProxy -> Docker socket
```

## How traffic gets in

- An **entry point** is a listening port. Traffic goes from host port 80 to Traefik's internal port 8080, or from host port 443 to 8443. The redirect sends the browser to public port 443.
- A **router** matches the request. A **label** is a setting on a container that Traefik reads from Docker. For example, ``Host(`whoami.test`)`` matches requests for that name and a service label selects port 80 inside whoami.
- The **edge network** is a Docker bridge shared by Traefik and project containers. `external: true` tells Compose the network already exists. A project joins it and leaves its app port unpublished. Keep databases and internal services on their own project networks.
- A **certificate** proves the hostname belongs to the server during TLS setup. For local testing Traefik generates a self-signed certificate. A browser displays a trust error unless you choose to trust it.
- **ACME** is the protocol Traefik uses to get public certificates from Let's Encrypt. With **HTTP-01**, Let's Encrypt fetches a short challenge from the public hostname on port 80. Traefik serves that challenge alongside its HTTP-to-HTTPS redirect.

## Request handling at the edge

Both entry points reject header names with alias characters. For example,
`X_User` is rejected so another service cannot mistake it for `X-User`.
The edge also rejects encoded slash, backslash, NUL, semicolon, percent,
question mark and hash in paths. For example, `/snaps/a%2Fb` cannot arrive
at a backend as a different route after decoding. Ordinary URL query
parameters are separate. Snap restricts new usernames to URL-safe characters
because they appear in routes such as `/messages/alex-2`. A name containing
`%` would need an escape that the edge rejects. A project that needs them should test the proxy and
backend together before changing the shared policy.

[Traefik entry-point path and header settings](https://doc.traefik.io/traefik/v3.7/reference/install-configuration/entrypoints/)

## How discovery works

The **Docker socket** is the file at `/var/run/docker.sock` through which Docker accepts commands. HAProxy is the **socket proxy**. It accepts only GET and HEAD on the paths Traefik needs: ping and version for startup, the container list and inspection for routing, and events for container changes. For example, a start event prompts Traefik to refresh its routes. The proxy listens on the private `docker-api` network and publishes no ports. Only the proxy mounts the socket. Its allowlist is what blocks write requests at the API level. The read-only mount alone would still allow commands over the socket. Container inspection can reveal environment variables, so the private network is an important part of this setup.

[Traefik Docker provider](https://doc.traefik.io/traefik/providers/docker/) · [Let's Encrypt HTTP-01](https://letsencrypt.org/docs/challenge-types/#http-01-challenge)

## Try it yourself

Copy `edge/` to the VM. Run these commands as `deploy`, from that copy of `edge/`.

```sh
docker network create edge
docker compose config --quiet
docker compose up -d
docker run -d --name zzt-whoami --network edge \
  --label traefik.enable=true \
  --label 'traefik.http.routers.whoami.rule=Host(`whoami.test`)' \
  --label traefik.http.routers.whoami.entrypoints=websecure \
  --label traefik.http.services.whoami.loadbalancer.server.port=80 \
  traefik/whoami:v1.11.0
```

From your Mac, replace the example IP with the VM's IP.

```sh
ip=192.0.2.10
curl -I --resolve "whoami.test:80:$ip" http://whoami.test/
curl -kfsS --resolve "whoami.test:443:$ip" https://whoami.test/
```

Expect a redirect to `https://whoami.test/` and then a reply containing `Hostname:`. The `--resolve` option sends the request to the VM while keeping the hostname. `-k` is for this local self-signed test. Remove the example container with `docker rm -f zzt-whoami` when finished.

## Use a public DuckDNS name

After the account owner sets up DuckDNS, use that hostname in your project's router label. Check that the public record resolves to your IPv4 before enabling ACME. In `edge/`, copy `.env.example` to `.env`, set the contact email, and start with staging.

```sh
docker compose -f compose.yml -f compose.acme.yml config --quiet
docker compose -f compose.yml -f compose.acme.yml up -d
```

The staging certificate will show a browser trust error. For production, change `ACME_CA_SERVER` and `ACME_STATE_FILE` to the production values in the example, then run the same Compose command. The named `acme` volume stores certificate and account keys. Separate state filenames keep staging and production certificates separate. Keep these files private and preserve the volume when updating Traefik.

## What can go wrong

- An upload that fails after exactly 60 seconds can hit Traefik's default read timeout. That timeout covers the entire request body. Snap measured an 88-second upload for a 9 MB photo at about 100 KB/s. The edge allows up to 300 seconds on both HTTP and HTTPS.

- `network edge declared as external, but could not be found` means the shared bridge has not been created.
- An HTTP 404 means Traefik received the request but found no matching router. Check the hostname and `traefik.enable` label.
- An HTTP 502 or 504 can mean the container is on the wrong network or its service label points to the wrong port.
- If all project hosts return 404, check `docker compose logs traefik socket-proxy` for a Docker discovery failure. A proxy HTTP 403 means an API request missed the allowlist.
- A public certificate error or ACME timeout can mean DuckDNS has an old IP, port 80 is blocked, or staging is selected. Compare the DNS record with the VM IP and read Traefik's log.
