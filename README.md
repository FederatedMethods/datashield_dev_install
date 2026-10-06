# DataSHIELD development environment

Run a local [Opal](https://www.obiba.org/pages/products/opal/) server with a [Rock](https://github.com/obiba/rock) R server and sample data (`CNSIM`) using Docker Compose, ready for DataSHIELD client testing.

## Quick start

Requires [Docker](https://docs.docker.com/get-started/get-docker/) with Compose >= 2.30 (check with `docker compose version`). Prefix commands with `sudo` on Linux if your user is not in the `docker` group.

    git clone https://github.com/FederatedMethods/datashield_dev_install
    cd datashield_dev_install/docker
    docker compose up -d

The first start downloads the sample data and sets everything up, which takes a few minutes. Follow progress with `docker compose logs -f opal`.

| What | Where / credentials |
|---|---|
| Opal web interface | <http://localhost:8880> (or <https://localhost:8843>, self-signed certificate) |
| Administrator | `administrator` / `password` |
| DataSHIELD user | `dsuser` / `P@ssw0rd` |
| Data | project `CNSIM`, tables `CNSIM.CNSIM1` and `CNSIM.CNSIM2` |

These credentials are for local development only.

## Test from R

Install the client packages:

    install.packages("dsBaseClient", repos = c(getOption("repos"), "https://cran.obiba.org"), dependencies = TRUE)

Then run `client/client.R` (short check) or `client/sandbox.R` (longer analysis using both tables). They connect to `http://localhost:8880` as `dsuser`; override with the `DS_URL`, `DS_USER` and `DS_PASSWORD` environment variables.

## Configuration

Copy `docker/.env.example` to `docker/.env` and uncomment what you want to change: Opal image, passwords, Java memory, project and table names (`CNSIM_PROJECT`, `CNSIM_TABLES`). Each table is downloaded from `<CNSIM_BASE_URL>/<table>.csv`.

Setup (`customise.sh`) runs only once per fresh volume, so after changing users, projects or tables, reset first:

    docker compose down -v
    docker compose up -d

`-v` deletes the `opal-data` and `mongo-data` volumes. Always keep the two together: wipe both or neither.

## Tracing with Jaeger (OpenTelemetry)

`docker/docker-compose.jaeger.yml` adds [Jaeger](https://www.jaegertracing.io/) and turns on Opal's OpenTelemetry trace export ([obiba/opal#4194](https://github.com/obiba/opal/pull/4194)):

    docker compose -f docker-compose.yml -f docker-compose.jaeger.yml up -d

Run one of the client scripts, then open <http://localhost:16686> and select the service `opal-local`. The override defaults to the `obiba/opal:snapshot` image; if no traces appear, set `OPAL_IMAGE` in `.env` to a build that includes the PR. Without the override nothing is exported.

## Troubleshooting

- **No project or user after start-up:** read the set-up log with `docker compose exec opal cat /srv/customisation.log`. Re-run set-up without wiping data using `docker compose exec -e FORCE=1 opal bash /customise.sh`.
- **Container logs:** `docker compose logs opal` (or `rock`, `mongodb`).
- **Fresh start:** `docker compose down -v`, then `docker compose up -d`. If a container was stopped uncleanly (e.g. Ctrl-C on `docker compose up`), check `docker ps -a` for leftovers; `docker compose up` restarts old containers rather than creating new ones.
- **`post_start` errors on `up`:** your Docker Compose is older than 2.30; upgrade it.

## Running on a remote host

To use this on a remote VM, put a reverse proxy with an SSL certificate in front of Opal:

1. Install nginx (`sudo apt install nginx`) and create a certificate. A self-signed one is fine for development: [DigitalOcean guide](https://www.digitalocean.com/community/tutorials/how-to-create-a-self-signed-ssl-certificate-for-nginx-in-ubuntu).
2. Copy `nginx/datashield1.conf` to `/etc/nginx/sites-available/datashield1` and set `server_name` to your host name or IP.
3. Enable it and reload:

        sudo ln -s /etc/nginx/sites-available/datashield1 /etc/nginx/sites-enabled/datashield1
        sudo rm /etc/nginx/sites-enabled/default
        sudo nginx -t && sudo systemctl reload nginx

4. In `docker/docker-compose.yml`, uncomment `CSRF_ALLOWED` and set it to the `host:port` your browser uses (needed because requests through a proxy can look like cross-site requests). Then recreate Opal: `docker compose up -d --force-recreate opal`.
5. If you use UFW, allow HTTPS: `sudo ufw allow 'Nginx HTTPS'`.

Browsers will warn about a self-signed certificate; accept it for development.

## Known limitations

- Group permissions do not work as expected, so permissions are granted to individual users.
- Tables are imported with every variable as `decimal`, so categorical variables (e.g. `GENDER`) are numeric rather than factors. Functions that need factors, such as `ds.table`, need the variable converted first (e.g. with `ds.asFactor`).

## Further resources

- [DataSHIELD wiki](https://wiki.datashield.org) and [datashield.org](https://www.datashield.org): documentation, tutorials, and the list of available packages
- [Opal documentation](https://opaldoc.obiba.org), including the [Python client](https://opaldoc.obiba.org/en/latest/python-user-guide/index.html) used by `customise.sh`
- [obiba/docker-opal](https://github.com/obiba/docker-opal): the official Opal Docker images and examples
- [FederatedMethods/ds_sample_data](https://github.com/FederatedMethods/ds_sample_data): the sample data used here
- [Jaeger documentation](https://www.jaegertracing.io/docs/): for exploring traces
