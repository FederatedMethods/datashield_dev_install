# ============================================================================ #
# DataSHIELD sandbox
#
# Generates a small but varied DataSHIELD analysis (assign tables, derive
# symbols, summaries, correlations, a frequency table) against Opal.
# Defaults target the local docker compose install in ../docker
# (project CNSIM with tables CNSIM1 and CNSIM2, user dsuser).
#
# Override with environment variables, e.g.
#   DS_URL=https://opal-demo.obiba.org Rscript sandbox.R
# ============================================================================ #
SERVER <- Sys.getenv("DS_URL", "http://localhost:8880")
DSUSER <- Sys.getenv("DS_USER", "dsuser")
## NOTE: only used to simulate an analysis; this is the public demo-server account
DSUSERPASS <- Sys.getenv("DS_PASSWORD", "P@ssw0rd")

# ============================================================================ #
# 1. Connect ------------------------------------------------------------------
# ============================================================================ #
## Needed to define the OpalDriver class in the current environment
DSOpal::Opal()
builder <- DSI::newDSLoginBuilder()
builder$append(
  server = "study1",
  url = SERVER,
  user = DSUSER,
  password = DSUSERPASS,
  driver = "OpalDriver"
)

logindata <- builder$build()
conns <- DSI::datashield.login(logins = logindata)

# ============================================================================ #
# 2. Check the available CNSIM datasets ---------------------------------------
# ============================================================================ #
dsBaseClient::ds.ls(datasources = conns["study1"])

# ============================================================================ #
# 3. Assign variables from CNSIM1 ---------------------------------------------
#
# D becomes a local DataSHIELD symbol representing:
#
#     CNSIM.CNSIM1
#
# but only the selected variables are brought into the analysis.
# ============================================================================ #
DSI::datashield.assign.table(
  conns,
  symbol = "D",
  table = "CNSIM.CNSIM1",
  variables = list(
    "GENDER",
    "LAB_GLUC_ADJUSTED",
    "PM_BMI_CONTINUOUS",
    "LAB_TSC"
  )
)

# ============================================================================ #
# 4. Create derived symbols from D --------------------------------------------
# ============================================================================ #
## G depends on D
# G <- D$GENDER
DSI::datashield.assign.expr(
  conns,
  symbol = "G",
  expr = quote(as.numeric(D$GENDER))
)

## BMI depends on D
DSI::datashield.assign.expr(
  conns,
  symbol = "BMI",
  expr = quote(D$PM_BMI_CONTINUOUS)
)

# ============================================================================ #
# 5. Basic operations on D and derived symbols --------------------------------
# ============================================================================ #
dsBaseClient::ds.summary("D", datasources = conns["study1"])
dsBaseClient::ds.summary("G", datasources = conns["study1"])
dsBaseClient::ds.summary("BMI", datasources = conns["study1"])

# ============================================================================ #
# 6. Assign a second dataset --------------------------------------------------
#
# E represents CNSIM2.
# ============================================================================ #
DSI::datashield.assign.table(
  conns,
  symbol = "E",
  table = "CNSIM.CNSIM2",
  variables = list(
    "GENDER",
    "LAB_GLUC_ADJUSTED",
    "PM_BMI_CONTINUOUS",
    "LAB_TRIG",
    "LAB_HDL"
  )
)

# ============================================================================ #
# 7. Operate on both D and E --------------------------------------------------
#
# A single command can have multiple symbol dependencies.
# ============================================================================ #
dsBaseClient::ds.summary("E", datasources = conns["study1"])
dsBaseClient::ds.class("D", datasources = conns["study1"])
dsBaseClient::ds.class("E", datasources = conns["study1"])

# ============================================================================ #
# 8. Create a derived expression using E --------------------------------------
# ============================================================================ #
DSI::datashield.assign.expr(
  conns,
  symbol = "E_GENDER",
  expr = quote(as.numeric(E$GENDER))
)

dsBaseClient::ds.summary("E_GENDER", datasources = conns["study1"])

# ============================================================================ #
# 9. Multiple-symbol operations -----------------------------------------------
# ============================================================================ #
dsBaseClient::ds.cor(
  "D$LAB_GLUC_ADJUSTED",
  "E$LAB_GLUC_ADJUSTED",
  datasources = conns["study1"]
)

# ============================================================================ #
# 10. Additional commands using derived symbols -------------------------------
# ============================================================================ #
dsBaseClient::ds.cor("BMI", "E_GENDER", datasources = conns["study1"])

# ============================================================================ #
# 11. Inspect the server-side workspace ---------------------------------------
# ============================================================================ #
dsBaseClient::ds.ls(datasources = conns["study1"])

# ============================================================================ #
# 12. Higher-risk analysis examples -------------------------------------------
#
# Set to FALSE to skip.
# ============================================================================ #

run_high_risk_examples <- TRUE

if (run_high_risk_examples) {
  message("Running higher-risk analysis examples...")

  # Frequency table example
  high_risk_table <- dsBaseClient::ds.table(
    "D$GENDER",
    datasources = conns
  )
}

# ============================================================================ #
# 13. Clean up ----------------------------------------------------------------
# ============================================================================ #
DSI::datashield.logout(conns)
