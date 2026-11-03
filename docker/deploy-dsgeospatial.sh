#!/usr/bin/env bash
# Build the dsGeospatial Rock image from the dsGeospatial repo, then (re)start
# the local Opal stack with it. Safe to re-run: it pulls the latest Dockerfile,
# rebuilds the image with the newest commit of DSGEOSPATIAL_REF, and recreates
# only the containers whose image changed. Data volumes are left alone.
#
#   ./deploy-dsgeospatial.sh                              # latest main
#   DSGEOSPATIAL_REF=dev-MoransI ./deploy-dsgeospatial.sh # a branch, tag or commit
#
# Expects the two repos side by side:
#   <WORKDIR>/datashield_dev_install
#   <WORKDIR>/dsGeospatial        (cloned here if missing)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-$(cd "$HERE/../.." && pwd)}"
GEO_DIR="${GEO_DIR:-$WORKDIR/dsGeospatial}"
GEO_URL="${GEO_URL:-https://github.com/FederatedMethods/dsGeospatial}"

# Version of the R package to install inside the image (branch, tag or commit)
export DSGEOSPATIAL_REF="${DSGEOSPATIAL_REF:-main}"
export DSGEOSPATIAL_ROCK_IMAGE="${DSGEOSPATIAL_ROCK_IMAGE:-ds-geospatial-rock:0.0.0.9000}"
export ROCK_PLATFORM="${ROCK_PLATFORM:-linux/amd64}"

echo "==> dsGeospatial repo: $GEO_DIR"
if [ -d "$GEO_DIR/.git" ]; then
git -C "$GEO_DIR" pull --ff-only
else
  git clone "$GEO_URL" "$GEO_DIR"
fi

echo "==> Building $DSGEOSPATIAL_ROCK_IMAGE (dsGeospatial @ $DSGEOSPATIAL_REF)"
docker build \
--platform "$ROCK_PLATFORM" \
--build-arg DSGEOSPATIAL_REF="$DSGEOSPATIAL_REF" \
--build-arg CACHEBUST="$(date +%s)" \
-t "$DSGEOSPATIAL_ROCK_IMAGE" \
"$GEO_DIR/docker"

echo "==> Starting Opal with the dsGeospatial Rock"
cd "$HERE"
docker compose -f docker-compose.yml -f docker-compose.geospatial.yml up -d

cat <<MSG

Done. Opal: http://localhost:8880
Next: in Opal, Administration > DataSHIELD, make sure the "ds-geospatial"
profile exists and is initialised (see README), then log in from R with
profile = "ds-geospatial".
MSG
