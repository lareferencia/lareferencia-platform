#!/usr/bin/env bats
# Wizard: before starting, a Solr schema the existing index cannot take is
# offered for migration — keep (default) or migrate after starting — like the
# PostgreSQL upgrade. Also `docker.sh solr status`, which shares the check.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup()      { sandbox::create; }

# --- solr status ----------------------------------------------------------------------

@test "solr status: nothing pending on a fresh installation" {
  docker_sh solr status
  assert_success
  assert_output_contains "No schema migration pending."
}

@test "solr status: an indexed Trie oai core with a Point schema staged → migration pending" {
  with_solr_trie_index
  docker_sh solr status
  assert_success
  assert_output_contains "oai: incompatible fieldType:long"
}

@test "solr status: an empty core can take any schema → nothing pending" {
  with_solr_trie_index
  rm "${SANDBOX_ROOT}/Docker/volume/solr/data/oai/data/index/_0.cfs"
  docker_sh solr status
  assert_output_contains "No schema migration pending."
}

@test "solr status: external Solr → no local check" {
  with_solr_trie_index
  env_set SOLR_EXTERNAL_URL http://solr.example.org:8983/solr
  docker_sh solr status
  assert_success
  assert_output_contains "External Solr: http://solr.example.org:8983/solr"
}

# --- wizard: Start Platform -------------------------------------------------------------

@test "wizard start, nothing pending: no Solr question, platform started" {
  wizard "🚀"
  assert_success
  ! grep -q "Keep the current Solr schema" "${GUM_LOG}"
  assert_called " up -d --remove-orphans"
}

@test "wizard start, migration pending, keep (default choice): starts without migrating" {
  with_solr_trie_index
  wizard "🚀" "📌"
  assert_success
  grep -q "choose: 📌 Keep the current Solr schema for now" "${GUM_LOG}"
  assert_called " up -d --remove-orphans"
  refute_called "solr migrate"
}

@test "wizard start, migration pending, migrate + confirm: starts, then migrates" {
  with_solr_trie_index
  wizard "🚀" "⬆️" "yes"
  assert_success
  grep -q "choose: ⬆️  Migrate oai after starting" "${GUM_LOG}"
  grep -q "confirm: Empty the index of oai and migrate after starting? → yes" "${GUM_LOG}"
  local up migrate
  up="$(call_line " up -d --remove-orphans")"
  migrate="$(call_line "run --rm --no-deps -T solr migrate")"
  [ "${up}" -gt 0 ] && [ "${migrate}" -gt "${up}" ]
}

@test "wizard start, migrate chosen but not confirmed: starts keeping the schema" {
  with_solr_trie_index
  wizard "🚀" "⬆️" "no"
  assert_success
  assert_called " up -d --remove-orphans"
  refute_called "solr migrate"
}

@test "wizard start, migration pending, cancel: nothing is started" {
  with_solr_trie_index
  wizard "🚀" "❌"
  assert_success
  refute_called " up -d"
}

@test "wizard start fails: the chosen migration is not run" {
  with_solr_trie_index
  export FAKE_FAIL=" up -d --remove-orphans"
  wizard "🚀" "⬆️" "yes"
  refute_called "solr migrate"
}

@test "wizard rebuild & start asks the same question" {
  with_solr_trie_index
  wizard "🔄" "📌"
  assert_success
  grep -q "choose: 📌 Keep the current Solr schema for now" "${GUM_LOG}"
}

# --- wizard: 🔎 Solr menu ------------------------------------------------------------------

@test "wizard menu: the Solr entry shows the available migration and migrates on request" {
  with_solr_trie_index
  wizard "🔎" "⬆️" "yes"
  assert_success
  grep -q "choose: 🔎 Solr \[schema migration available: oai\]" "${GUM_LOG}"
  assert_called "run --rm --no-deps -T solr migrate"
}

@test "wizard menu: without pending migrations the Solr screen only offers verify" {
  wizard "🔎" "🔍"
  assert_success
  grep -q "choose: 🔎 Solr$" "${GUM_LOG}"
  assert_called "stage-cores.sh --check"
  refute_called "solr migrate"
}
