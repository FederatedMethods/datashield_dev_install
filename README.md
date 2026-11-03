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

Run one of the client scripts, then open <http://localhost:16686> and select the service `opal-local`. The override defaults to the `obiba/opal:snapshot` image; if no traces appear, set `OPAL_IMAGE` in `.env` to a build that includes the PR. Without the override nothing is exported. Override files can be combined, e.g. `-f docker-compose.yml -f docker-compose.jaeger.yml -f docker-compose.dsgeospatial.yml`.

## Adding server-side packages (dsGeospatial and others)

The default stack only has the standard DataSHIELD packages. Extra server-side R packages (such as [dsGeospatial](https://github.com/FederatedMethods/dsGeospatial)) live in a **Rock image of their own**, added to the stack with a Compose override file, the same way as the Jaeger override above.

How it fits together:

- Opal talks to one or more Rock R servers (`ROCK_HOSTS`). Each Rock reports a **cluster** name, and each cluster is a **DataSHIELD profile** in Opal. The stock Rock is profile `default`; the dsGeospatial Rock is profile `ds-geospatial`.
- The image is built from the package's own repo (its `docker/Dockerfile`), not from this one. The Dockerfile installs the package from GitHub, and a build argument chooses the branch, tag or commit.
- This repo only contains the override (`docker/docker-compose.dsgeospatial.yml`) that starts that image and registers it with Opal.

### dsGeospatial: one command

This clones both repos side by side, builds the image and starts Opal with the extra Rock (needs `git` and Docker; the first build compiles the spatial libraries and takes a while):

    mkdir -p datashield && cd datashield \
      && git clone https://github.com/FederatedMethods/datashield_dev_install \
      && git clone https://github.com/FederatedMethods/dsGeospatial \
      && docker build --platform linux/amd64 -t ds-geospatial-rock:0.0.0.9000 dsGeospatial/docker \
      && cd datashield_dev_install/docker \
      && docker compose -f docker-compose.yml -f docker-compose.dsgeospatial.yml up -d

The image tag must match `DSGEOSPATIAL_ROCK_IMAGE` (default `ds-geospatial-rock:0.0.0.9000`). The `--platform` flag matches the override; the Rock base image is amd64 only, so on Apple Silicon it runs under emulation (slower, but works).

### Updating or changing the version

`docker/deploy-dsgeospatial.sh` repeats the whole sequence and is safe to re-run. It pulls the latest `dsGeospatial` Dockerfile, rebuilds the image with the newest commit of the chosen version, and recreates only the containers whose image changed. Opal and MongoDB data are kept.

    cd datashield_dev_install/docker
    ./deploy-dsgeospatial.sh                               # latest main
    DSGEOSPATIAL_REF=dev-MoransI ./deploy-dsgeospatial.sh  # a branch, tag or commit SHA

The script expects the repos side by side. Set `WORKDIR` (parent folder) or `GEO_DIR` (the dsGeospatial clone) if yours are elsewhere. Other settings are environment variables too: `DSGEOSPATIAL_ROCK_IMAGE`, `ROCK_PLATFORM`, `GEO_URL`.

Note that `DSGEOSPATIAL_REF` chooses which version of the **R package** goes into the image. The Dockerfile itself comes from whatever branch of the dsGeospatial clone is checked out.

### Set up the profile in Opal

Do this once, and again after rebuilding with a new version, because Opal remembers a profile's published methods in its data volume (no `down -v` needed).

1. Open <http://localhost:8880> and log in as `administrator`.
2. Go to **Administration > DataSHIELD**. A profile for the `ds-geospatial` cluster should be listed; if not, add one and choose that cluster. (Menu labels can differ slightly between Opal versions.)
3. Make sure the profile is started and **initialised**, so Opal publishes the package's methods (for dsGeospatial: `MeanSdGpDS`, `groupcorDS`, `asFactorDS3`, `MoransI`, `Localmoran`).
4. If `dsuser` is refused on the new profile, check the profile's permissions. `customise.sh` grants the DataSHIELD use permission globally, not per profile.

### Use it within R

Select the profile at login. The `{dsGeospatial}` analyst package, `{dsGeospatialClient}`, must be installed on the client side as well.

```r
DSOpal::Opal()
builder <- DSI::newDSLoginBuilder()
builder$append(
  server = "study1", url = "http://localhost:8880", user = "administrator",
  password = "password", driver = "OpalDriver", profile = "ds-geospatial"
)

logindata <- builder$build()
conns <- DSI::datashield.login(logins = logindata)
DSI::datashield.pkg_status(conns)   # dsBase and dsGeospatial should both be listed
```

### Adding another package

Use the same pattern for any server-side package:

1. In the package's repo, create a `docker/Dockerfile` that starts `FROM datashield/rock-base:<tag>`, installs the system libraries the package needs, and installs the package (for GitHub packages, `remotes::install_github(repo, ref = ...)` with a build argument for `ref`). Use the dsGeospatial Dockerfile as a template.
2. Build it: `docker build --platform linux/amd64 -t my-package-rock:local path/to/repo/docker`.
3. Copy `docker/docker-compose.dsgeospatial.yml` to `docker/docker-compose.<name>.yml` and change the service name, image and cluster. Give each Rock a **unique** service name and `ROCK_ID`, and a unique `ROCK_CLUSTER`. Add the new host to `ROCK_HOSTS`:

        services:
          opal:
            environment:
              - ROCK_HOSTS=rock:8085,rock-mypackage:8085
            depends_on:
              rock-mypackage:
                condition: service_started
          rock-mypackage:
            image: my-package-rock:local
            pull_policy: never
            platform: linux/amd64
            environment:
              ROCK_ID: my-package-rock-01
              ROCK_CLUSTER: my-package

4. Start with the extra file and set up the new profile in Opal as above:

        docker compose -f docker-compose.yml -f docker-compose.<name>.yml up -d

Each additional override file replaces the `ROCK_HOSTS` line, so if you combine several, list **all** the hosts in the last file you pass, or put a single `ROCK_HOSTS` in `.env`. Packages that are always used together can instead share one image and one profile.

## Troubleshooting

- **No project or user after start-up:** read the set-up log with `docker compose exec opal cat /srv/customisation.log`. Re-run set-up without wiping data using `docker compose exec -e FORCE=1 opal bash /customise.sh`.
- **Container logs:** `docker compose logs opal` (or `rock`, `mongodb`).
- **Fresh start:** `docker compose down -v`, then `docker compose up -d`. If a container was stopped uncleanly (e.g. Ctrl-C on `docker compose up`), check `docker ps -a` for leftovers; `docker compose up` restarts old containers rather than creating new ones.
- **`post_start` errors on `up`:** your Docker Compose is older than 2.30; upgrade it.
- **`image ... not found` for the dsGeospatial Rock:** the image has not been built yet (the override never pulls from a registry). Build it, or run `docker/deploy-dsgeospatial.sh`.
- **No `ds-geospatial` profile in Opal:** check the Rock is running (`docker compose -f docker-compose.yml -f docker-compose.dsgeospatial.yml logs rock-geospatial`) and that Opal was started with the override, so `ROCK_HOSTS` lists it. Then add the profile for the `ds-geospatial` cluster.
- **Package methods missing in the profile:** initialise the profile again in Opal after rebuilding the image. Confirm the package is in the container: `docker compose -f docker-compose.yml -f docker-compose.dsgeospatial.yml exec rock-geospatial R -q -e 'library(dsGeospatial)'`.
- **Build fails or is very slow on Apple Silicon:** the Rock base image is amd64, so the build runs under emulation. Give Docker more CPU and memory, or build on an amd64 machine.
- **Image still has an old version of the package:** Docker reused a cached layer. Rebuild with `--build-arg CACHEBUST=$(date +%s)` (the script does this for you).

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
- [FederatedMethods/dsGeospatial](https://github.com/FederatedMethods/dsGeospatial): the server-side geospatial package, with the Dockerfile for its Rock image
- [Jaeger documentation](https://www.jaegertracing.io/docs/): for exploring traces
