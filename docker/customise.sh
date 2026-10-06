#!/usr/bin/env bash

# Run inside the opal container after start (docker compose `post_start`).
# Creates the demo user, DataSHIELD permission, the CNSIM project and its tables.
#
# Output is also written to /srv/customisation.log (inside the opal-data volume):
#   docker compose exec opal cat /srv/customisation.log
# Re-run by hand (ignoring any earlier success):
#   docker compose exec -e FORCE=1 opal bash /customise.sh
#
# https://opaldoc.obiba.org/en/latest/python-user-guide/index.html

exec > >(tee -a /srv/customisation.log) 2>&1
echo "=== customise.sh started $(date) ==="

MARKER=/srv/.local_customisation_done
if [ -f "$MARKER" ] && [ -z "$FORCE" ]; then
    echo "Customisation: already done, skipping (use FORCE=1 to run again)."
    exit 0
fi

ADMIN_USER=administrator
OPAL_URL=http://localhost:8080 # must match port on docker-compose.yml

# wget is not installed in the base docker image (also used below for checks)
if ! command -v wget >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq wget
fi

# Run an opal client command as administrator, retrying a few times because
# Opal can still be initialising shortly after it first answers.
# usage: opalc <description> <opal subcommand and args...>
opalc() {
    local desc="$1"; shift
    local i
    for i in 1 2 3; do
        if opal "$1" --user "$ADMIN_USER" --password "$OPAL_ADMINISTRATOR_PASSWORD" "${@:2}"; then
            echo "OK: $desc"
            return 0
        fi
        echo "RETRY $i/3: $desc"
        sleep 5
    done
    echo "FAILED: $desc"
    return 1
}

# Does this Opal web service path answer for the administrator?
ws_exists() {
    wget -q -O /dev/null --user "$ADMIN_USER" --password "$OPAL_ADMINISTRATOR_PASSWORD" \
        --auth-no-challenge "$OPAL_URL/ws$1"
}

echo "Waiting for Opal to answer..."
until opal system --user "$ADMIN_USER" --password "$OPAL_ADMINISTRATOR_PASSWORD" --version
do
    echo "Customisation: Opal not up yet, sleeping..."
    sleep 5
done
# Opal answers before it has finished initialising (first-login home folder,
# DataSHIELD profile); give it a moment.
sleep 15

# Get the verion of opal
echo "Opal version:"
opal system --user administrator --password "$OPAL_ADMINISTRATOR_PASSWORD" --version

# Adding something that already exists fails; that is fine, the checks at the end decide.
opalc "add user $OPAL_DEMO_USER_NAME" user --add --name "$OPAL_DEMO_USER_NAME" --upassword "$OPAL_DEMO_USER_PASSWORD"

# Lets the user run DataSHIELD functions. Does not grant access to any data.
opalc "DataSHIELD use permission for $OPAL_DEMO_USER_NAME" perm-datashield --type USER --subject "$OPAL_DEMO_USER_NAME" --permission use --add

###########################################################################
# CNSIM PROJECT: one table per name in CNSIM_TABLES, downloaded from
# $CNSIM_BASE_URL/<table>.csv (e.g. CNSIM.CNSIM1 and CNSIM.CNSIM2)
###########################################################################

opalc "add project $CNSIM_PROJECT" project --add --name "$CNSIM_PROJECT" --database mongodb

for table in $CNSIM_TABLES
do
    mkdir -p /tmp/opal-config-temp
    cd /tmp/opal-config-temp || exit 1
    rm -f "$table.csv"
    wget -q "$CNSIM_BASE_URL/$table.csv" || echo "FAILED: download $CNSIM_BASE_URL/$table.csv"

    opalc "upload $table.csv" file -up "$table.csv" /home/administrator
    opalc "import $CNSIM_PROJECT.$table" import-csv --destination "$CNSIM_PROJECT" --path "/home/administrator/$table.csv" --tables "$table" --separator , --type Participant --valueType decimal
    # Demo user can use the table in DataSHIELD, but not see the data in the web interface.
    opalc "view permission on $CNSIM_PROJECT.$table" perm-table --type USER --project "$CNSIM_PROJECT" --subject "$OPAL_DEMO_USER_NAME" --permission view --add --tables "$table"

    cd / && rm -rf /tmp/opal-config-temp
done

###########################################################################
# Check the result; only mark as done if everything is really there
###########################################################################
ok=1
ws_exists "/project/$CNSIM_PROJECT" && echo "CHECK OK: project $CNSIM_PROJECT" || { echo "CHECK FAILED: project $CNSIM_PROJECT"; ok=0; }
for table in $CNSIM_TABLES
do
    ws_exists "/datasource/$CNSIM_PROJECT/table/$table" && echo "CHECK OK: table $CNSIM_PROJECT.$table" || { echo "CHECK FAILED: table $CNSIM_PROJECT.$table"; ok=0; }
done

if [ "$ok" = 1 ]; then
    touch /finished_local_customisation.txt "$MARKER"
    echo "=== customise.sh finished OK ==="
else
    echo "=== customise.sh finished WITH FAILURES: see messages above; run again with FORCE=1 ==="
    exit 1
fi
