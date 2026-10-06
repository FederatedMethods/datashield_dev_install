###############################################################################
# DataSHIELD demo of docker installation
# This R script is intended as a validation/demonstration of the DataSHIELD
# installation from the docker compose file at docker/docker-compose.yml.
###############################################################################

# This will need to be installed locally.
# library(DSI)
# library(DSOpal)
# library(dsBaseClient)

# Can be useful for debugging SSL issues
# library(curl)
# curl::curl_version()

################################################################################
# Set all the options.

# Defaults target a local docker compose install (http://localhost:8880).
# Override with environment variables, e.g. DS_URL=https://my.host Rscript client.R
# Behind the nginx reverse proxy this should be a proper https URL; from within
# the VM, https://localhost:8843 also works (self-signed certificate, see options below).
#url <- "https://datashield2.liv.ac.uk"
url <- Sys.getenv("DS_URL", "http://localhost:8880")

# As defined in the docker-compose file (OPAL_DEMO_USER_NAME / OPAL_DEMO_USER_PASSWORD)
user <- Sys.getenv("DS_USER", "dsuser")
password <- Sys.getenv("DS_PASSWORD", "P@ssw0rd")

# When developing with self signed certificates, you may need to set these as
# strict verification is the default. Do not use in production.
options <- "list(ssl_verifyhost = 0L, ssl_verifypeer = 0L)"
################################################################################

################################################################################
# Now log into the server for the DEMO.CNSIM1 table
## Needed to define the OpalDriver class in the current environment
DSOpal::Opal()
builder <- DSI::newDSLoginBuilder()
builder$append(
  server = "server1",
  url = url,
  user = user,
  password = password,
  options = options,
  table = "CNSIM.CNSIM1"
)
logindata <- builder$build()
connections <- DSI::datashield.login(
  logins = logindata,
  assign = TRUE,
  symbol = "D"
)

# Check what packages are available. I would expect to see dsBase and resourcer
DSI::datashield.pkg_status(connections)

# Check what data is available.
DSI::datashield.tables(connections)

###############################################################################
# Now start doing stuff with the data in the table linked to 'D'
dsBaseClient::ds.colnames(x = 'D', datasources = connections)
dsBaseClient::ds.dim(x = 'D', datasources = connections)
dsBaseClient::ds.summary(x = 'D$LAB_HDL', datasources = connections)
dsBaseClient::ds.mean(x = 'D$LAB_HDL', datasources = connections)
DSI::datashield.errors()

# Close the server-side R sessions cleanly.
DSI::datashield.logout(connections)
