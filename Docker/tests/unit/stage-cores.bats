#!/usr/bin/env bats
# Docker/solr/stage-cores.sh: cores come unchanged from their modules, from the
# VuFind checkout the deployment selects, and nothing is staged on doubt.

load ../helpers/unit

setup() {
  ROOT="${BATS_TEST_TMPDIR}/root"
  UPSTREAM="${BATS_TEST_TMPDIR}/upstream-vufind"
  mkdir -p "${ROOT}/Docker/solr"
  cp "${PROJECT_DIR}/Docker/solr/stage-cores.sh" "${PROJECT_DIR}/Docker/solr/Dockerfile" "${ROOT}/Docker/solr/"

  # lareferencia-oai-pmh: its own checkout, owner of the oai core.
  local oai="${ROOT}/lareferencia-oai-pmh"
  mkdir -p "${oai}/solr.core/oai/conf"
  echo "name=oai" > "${oai}/solr.core/oai/core.properties"
  echo '<config><luceneMatchVersion>9.11</luceneMatchVersion></config>' > "${oai}/solr.core/oai/conf/solrconfig.xml"
  echo '<schema><fieldType name="plong" class="solr.LongPointField"/></schema>' > "${oai}/solr.core/oai/conf/schema.xml"
  unit::git init -q "${oai}"
  unit::git -C "${oai}" remote add origin https://github.com/lareferencia/lareferencia-oai-pmh.git
  unit::commit "${oai}" "oai core"

  # VuFind "upstream": tag v-test (deployed) and a later commit tagged v-next.
  mkdir -p "${UPSTREAM}/solr/vufind/biblio/conf/xslt" "${UPSTREAM}/solr/vufind/jars" "${UPSTREAM}/import"
  echo '{}' > "${UPSTREAM}/composer.json"
  echo "# use defaults for biblio core" > "${UPSTREAM}/solr/vufind/biblio/core.properties"
  echo '<config/>' > "${UPSTREAM}/solr/vufind/biblio/conf/solrconfig.xml"
  cat > "${UPSTREAM}/solr/vufind/biblio/conf/schema.xml" <<'EOF'
<schema>
  <fieldType name="knn_vector" class="solr.DenseVectorField" vectorDimension="384"/>
  <field name="vector" type="knn_vector" indexed="true" stored="false"/>
</schema>
EOF
  echo '<xsl/>' > "${UPSTREAM}/solr/vufind/biblio/conf/xslt/example.xsl"
  echo "jar v-test" > "${UPSTREAM}/solr/vufind/jars/MarcImporter.jar"
  echo "solr.hosturl=http://solr:8983/solr/biblio/update" > "${UPSTREAM}/import/import.properties"
  unit::git init -q "${UPSTREAM}"
  unit::commit "${UPSTREAM}" "v-test"
  unit::git -C "${UPSTREAM}" tag v-test
  echo "jar v-next" > "${UPSTREAM}/solr/vufind/jars/MarcImporter.jar"
  unit::commit "${UPSTREAM}" "v-next"
  unit::git -C "${UPSTREAM}" tag v-next

  unit::git clone -q --branch v-test "file://${UPSTREAM}" "${ROOT}/vufind"
  export VUFIND_REPO_URL="file://${UPSTREAM}" VUFIND_REF=v-test
  # Most checks below are about refusing: pinned (strict) deployments.
  export LR_SOLR_VUFIND_CHECK=strict
}

stage() {
  run bash "${ROOT}/Docker/solr/stage-cores.sh" "$@"
}

# Fixture of a previous successful staging, to prove a failure leaves it alone.
previous_staging() {
  mkdir -p "${ROOT}/Docker/solr/cores/oai"
  echo "previous" > "${ROOT}/Docker/solr/cores/oai/core.properties"
}

assert_previous_staging_kept() {
  [ "$(cat "${ROOT}/Docker/solr/cores/oai/core.properties")" = "previous" ]
  [ ! -e "${ROOT}/Docker/solr/cores/biblio" ]
}

# --- what is staged --------------------------------------------------------------

@test "stages both cores, jars and import byte for byte from their modules" {
  stage
  assert_success
  diff -r "${ROOT}/lareferencia-oai-pmh/solr.core/oai" "${ROOT}/Docker/solr/cores/oai"
  diff -r "${ROOT}/vufind/solr/vufind/biblio" "${ROOT}/Docker/solr/cores/biblio"
  diff -r -x .gitkeep "${ROOT}/vufind/solr/vufind/jars" "${ROOT}/Docker/solr/jars"
  diff -r -x .gitkeep "${ROOT}/vufind/import" "${ROOT}/Docker/solr/import"
}

@test "the vector support of the VuFind schema reaches the staging unchanged" {
  stage
  assert_success
  grep -q 'solr.DenseVectorField' "${ROOT}/Docker/solr/cores/biblio/conf/schema.xml"
  grep -q 'name="vector"' "${ROOT}/Docker/solr/cores/biblio/conf/schema.xml"
}

@test "jars come from the selected VuFind revision, not from another one" {
  stage
  assert_success
  [ "$(cat "${ROOT}/Docker/solr/jars/MarcImporter.jar")" = "jar v-test" ]
}

@test "records Solr version, repository, revision and state of each source" {
  stage
  assert_success
  local info="${ROOT}/Docker/solr/cores/build-info.properties"
  grep -qx "solr.version=9.11.0" "${info}"
  grep -qx "core.oai.repository=https://github.com/lareferencia/lareferencia-oai-pmh.git" "${info}"
  grep -qx "core.oai.revision=$(unit::git -C "${ROOT}/lareferencia-oai-pmh" rev-parse HEAD)" "${info}"
  grep -qx "core.oai.dirty=false" "${info}"
  grep -qx "core.biblio.repository=file://${UPSTREAM}" "${info}"
  grep -qx "core.biblio.revision=$(unit::git -C "${UPSTREAM}" rev-parse v-test)" "${info}"
  grep -qx "core.biblio.dirty=false" "${info}"
  grep -qx "core.biblio.expected.ref=v-test" "${info}"
}

@test "a core.properties missing in the module is an error, never synthesized" {
  previous_staging
  rm "${ROOT}/lareferencia-oai-pmh/solr.core/oai/core.properties"
  stage
  assert_failure
  assert_output_contains "core.properties is missing; lareferencia-oai-pmh must provide it"
  assert_output_contains "Nothing was staged"
  assert_previous_staging_kept
}

@test "cores no longer provided are removed; the directories themselves (bind mounts) are kept" {
  mkdir -p "${ROOT}/Docker/solr/cores/old-core/conf" "${ROOT}/Docker/solr/jars"
  touch "${ROOT}/Docker/solr/cores/.gitkeep" "${ROOT}/Docker/solr/jars/stale.jar"
  local cores_inode jars_inode
  cores_inode="$(inode_of "${ROOT}/Docker/solr/cores")"
  jars_inode="$(inode_of "${ROOT}/Docker/solr/jars")"
  stage
  assert_success
  [ ! -e "${ROOT}/Docker/solr/cores/old-core" ]
  [ ! -e "${ROOT}/Docker/solr/jars/stale.jar" ]
  [ -f "${ROOT}/Docker/solr/cores/.gitkeep" ]
  [ "$(inode_of "${ROOT}/Docker/solr/cores")" = "${cores_inode}" ]
  [ "$(inode_of "${ROOT}/Docker/solr/jars")" = "${jars_inode}" ]
}

# --- the VuFind checkout must be the one the deployment selects ----------------------

@test "VuFind at another revision than VUFIND_REF → nothing staged (strict)" {
  previous_staging
  unit::git -C "${ROOT}/vufind" fetch -q origin tag v-next
  unit::git -C "${ROOT}/vufind" checkout -q v-next
  stage
  assert_failure
  assert_output_contains "but VUFIND_REF 'v-test' (environment) is"
  assert_previous_staging_kept
}

@test "default check (warn): a checkout that differs from Docker/.env never blocks an upgrade" {
  unset LR_SOLR_VUFIND_CHECK VUFIND_REPO_URL
  unit::git -C "${ROOT}/vufind" remote set-url origin https://github.com/LA-Referencia-IOI/vufind
  echo "VUFIND_REPO_URL=https://github.com/vufind-org/vufind" > "${ROOT}/Docker/.env"
  stage
  assert_success
  assert_output_contains "Warning: vufind/ comes from https://github.com/LA-Referencia-IOI/vufind"
  # what Solr gets is what VuFind web runs: the checkout itself, recorded
  grep -qx "core.biblio.repository=https://github.com/LA-Referencia-IOI/vufind" "${ROOT}/Docker/solr/cores/build-info.properties"
  grep -qx "core.biblio.check=warn" "${ROOT}/Docker/solr/cores/build-info.properties"
}

@test "default check (warn) still refuses a missing source (nothing to stage from)" {
  unset LR_SOLR_VUFIND_CHECK
  rm "${ROOT}/vufind/solr/vufind/biblio/core.properties"
  stage
  assert_failure
  assert_output_contains "core 'biblio'"
}

@test "LR_SOLR_VUFIND_CHECK=warn → mismatch reported, staging done" {
  unit::git -C "${ROOT}/vufind" fetch -q origin tag v-next
  unit::git -C "${ROOT}/vufind" checkout -q v-next
  LR_SOLR_VUFIND_CHECK=warn stage
  assert_success
  assert_output_contains "Warning: vufind/ is at"
  grep -qx "core.biblio.check=warn" "${ROOT}/Docker/solr/cores/build-info.properties"
}

@test "VuFind cloned from another repository than VUFIND_REPO_URL → nothing staged" {
  previous_staging
  VUFIND_REPO_URL=https://github.com/LA-Referencia-IOI/vufind stage
  assert_failure
  assert_output_contains "but VUFIND_REPO_URL (environment) is https://github.com/LA-Referencia-IOI/vufind"
  assert_previous_staging_kept
}

@test "equivalent spellings of the repository URL are accepted (.git, trailing /, case)" {
  unit::git -C "${ROOT}/vufind" remote set-url origin "https://GitHub.com/LA-Referencia-IOI/vufind.git"
  VUFIND_REPO_URL="https://github.com/la-referencia-ioi/vufind/" stage
  assert_success
  unit::git -C "${ROOT}/vufind" remote set-url origin "git@github.com:LA-Referencia-IOI/vufind.git"
  VUFIND_REPO_URL="https://github.com/LA-Referencia-IOI/vufind" stage
  assert_success
}

@test "VUFIND_REF unknown to the checkout → explained, nothing staged" {
  VUFIND_REF=v-missing stage
  assert_failure
  assert_output_contains "VUFIND_REF 'v-missing' (environment) is unknown to vufind/"
}

@test "local changes to the VuFind biblio core → nothing staged (would not match the revision)" {
  echo "<!-- local patch -->" >> "${ROOT}/vufind/solr/vufind/biblio/conf/schema.xml"
  stage
  assert_failure
  assert_output_contains "vufind/ has local changes"
}

@test "settings are read from Docker/.env, quotes removed" {
  unset VUFIND_REF VUFIND_REPO_URL
  printf 'VUFIND_REPO_URL="file://%s"\nVUFIND_REF='"'"'v-test'"'"'\n' "${UPSTREAM}" > "${ROOT}/Docker/.env"
  stage
  assert_success
  grep -qx "core.biblio.expected.ref=v-test" "${ROOT}/Docker/solr/cores/build-info.properties"
}

@test "VUFIND_REPO_URL/VUFIND_REF not configured: the fork in vufind/ is used as it is (no built-in default comparison)" {
  # Clean instance whose Docker/.env has no VuFind settings, vufind/ cloned from a fork.
  unset VUFIND_REPO_URL VUFIND_REF
  unit::git -C "${ROOT}/vufind" remote set-url origin https://github.com/LA-Referencia-IOI/vufind
  echo "LR_PORT_SOLR=8983" > "${ROOT}/Docker/.env"
  stage
  assert_success
  refute_output_contains "but VUFIND_REPO_URL"
  assert_output_contains "VUFIND_REPO_URL is not configured; using vufind/ as it is (origin https://github.com/LA-Referencia-IOI/vufind)"
  assert_output_contains "VUFIND_REF is not configured"
  local info="${ROOT}/Docker/solr/cores/build-info.properties"
  grep -qx "core.biblio.repository=https://github.com/LA-Referencia-IOI/vufind" "${info}"
  grep -qx "core.biblio.expected.repository=" "${info}"
  grep -qx "core.biblio.expected.ref=" "${info}"
}

@test "VUFIND_REPO_URL explicitly set in Docker/.env to another repo: still refused, says where and how to fix" {
  unset VUFIND_REPO_URL
  unit::git -C "${ROOT}/vufind" remote set-url origin https://github.com/LA-Referencia-IOI/vufind
  echo "VUFIND_REPO_URL=https://github.com/vufind-org/vufind" > "${ROOT}/Docker/.env"
  stage
  assert_failure
  assert_output_contains "but VUFIND_REPO_URL (Docker/.env) is https://github.com/vufind-org/vufind"
  assert_output_contains "Set VUFIND_REPO_URL=https://github.com/LA-Referencia-IOI/vufind in Docker/.env"
}

@test "only VUFIND_REF configured: the revision is still enforced" {
  unset VUFIND_REPO_URL
  unit::git -C "${ROOT}/vufind" fetch -q origin tag v-next
  unit::git -C "${ROOT}/vufind" checkout -q v-next
  stage
  assert_failure
  assert_output_contains "VUFIND_REF 'v-test' (environment)"
}

@test "an invalid LR_SOLR_VUFIND_CHECK is rejected" {
  LR_SOLR_VUFIND_CHECK=maybe stage
  assert_failure
  assert_output_contains "LR_SOLR_VUFIND_CHECK must be strict, warn or off"
}

# --- missing checkouts ------------------------------------------------------------------

@test "VuFind missing (web service disabled) → the configured repo/ref is cloned, vufind/local kept" {
  rm -rf "${ROOT}/vufind"
  mkdir -p "${ROOT}/vufind/local/docker"
  echo "site config" > "${ROOT}/vufind/local/docker/config.ini"
  stage
  assert_success
  assert_output_contains "cloning file://${UPSTREAM} (ref: v-test)"
  [ "$(cat "${ROOT}/vufind/local/docker/config.ini")" = "site config" ]
  [ "$(cat "${ROOT}/Docker/solr/jars/MarcImporter.jar")" = "jar v-test" ]
  grep -qx "core.biblio.revision=$(unit::git -C "${UPSTREAM}" rev-parse v-test)" "${ROOT}/Docker/solr/cores/build-info.properties"
}

@test "VuFind clone fails → error, nothing staged" {
  rm -rf "${ROOT}/vufind"
  previous_staging
  VUFIND_REF=v-missing stage
  assert_failure
  assert_output_contains "could not clone VuFind v-missing"
  assert_previous_staging_kept
}

@test "lareferencia-oai-pmh missing → githelper asked to clone it; still missing → nothing staged" {
  rm -rf "${ROOT}/lareferencia-oai-pmh"
  previous_staging
  printf '#!/usr/bin/env bash\necho "githelper $*" >> "%s/githelper.log"\n' "${BATS_TEST_TMPDIR}" > "${ROOT}/githelper"
  chmod +x "${ROOT}/githelper"
  stage
  assert_failure
  grep -qx "githelper init --depth 1 --modules lareferencia-oai-pmh" "${BATS_TEST_TMPDIR}/githelper.log"
  assert_output_contains "core 'oai': lareferencia-oai-pmh/solr.core/oai not found"
  assert_previous_staging_kept
}

# --- --check ------------------------------------------------------------------------------

@test "--check: OK right after staging" {
  stage
  assert_success
  stage --check
  assert_success
  assert_output_contains "OK              oai"
  assert_output_contains "OK              biblio"
}

@test "--check: a module change not yet staged is reported, staging untouched" {
  stage
  echo '<!-- new field -->' >> "${ROOT}/lareferencia-oai-pmh/solr.core/oai/conf/schema.xml"
  stage --check
  assert_failure
  assert_output_contains "DIFFERENT       oai"
  ! grep -q 'new field' "${ROOT}/Docker/solr/cores/oai/conf/schema.xml"
}
