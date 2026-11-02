#!/usr/bin/env bats
# Cleanup after build and `prune`: ONLY La Referencia artifacts of this
# installation — never other projects sharing the same Docker.

load ../helpers/sandbox

setup_file() { sandbox::build_template; }
setup() {
  sandbox::create
  H="$(sandbox_hash)"
  CUR="$(current_image_tag)"
  # Images on the host: current build, two previous builds of this installation,
  # another installation (other checkout hash) and a manual tag.
  export FAKE_IMAGE_LIST="\
lareferencia/harvester:${CUR}
lareferencia/solr:${CUR}
lareferencia/harvester:lareferencia-${H}-aaaaaaa
lareferencia/solr:lareferencia-${H}-aaaaaaa
lareferencia/harvester:lareferencia-${H}-bbbbbbb
lareferencia/solr:lareferencia-${H}-bbbbbbb
lareferencia/harvester:lareferencia-0ther00-ccccccc
lareferencia/harvester:my-manual-tag"
  # Build history, oldest first: bbbbbbb, then aaaaaaa (names do not tell the order).
  printf '%s\n' "lareferencia-${H}-bbbbbbb" "lareferencia-${H}-aaaaaaa" > "${SANDBOX_ROOT}/Docker/.image-tags"
}

removed_images() { calls | sed -n 's/^docker rmi //p' | sort; }

# Nothing global, ever: image prunes are filtered by project, and the build
# cache (shared by every project on the host) is never pruned.
refute_global_prune() {
  if calls | grep -E 'docker (image|system|volume|container) prune' | grep -v -- '--filter label=com.docker.compose.project=' ; then
    echo "global prune found"; return 1
  fi
  if calls | grep -E 'docker (builder|buildx) prune'; then
    echo "build cache prune found"; return 1
  fi
  return 0
}

@test "after build: keeps current + the most recent previous build (from the history)" {
  docker_sh build solr
  assert_success
  run removed_images
  [ "${output}" = "lareferencia/harvester:lareferencia-<HASH>-bbbbbbb
lareferencia/solr:lareferencia-<HASH>-bbbbbbb" ] || { echo "${output}"; false; }
  refute_global_prune
}

@test "after build: other installations and manual tags are never removed" {
  env_set LR_IMAGE_KEEP_PREVIOUS 0
  docker_sh build solr
  assert_success
  refute_called "0ther00"
  refute_called "my-manual-tag"
  refute_called "docker rmi lareferencia/harvester:$(current_image_tag)"
}

@test "LR_IMAGE_KEEP_PREVIOUS=0: only the current build remains" {
  env_set LR_IMAGE_KEEP_PREVIOUS 0
  docker_sh build solr
  assert_success
  run removed_images
  [ "$(printf '%s\n' "${output}" | wc -l | tr -d ' ')" = 4 ] || { echo "${output}"; false; }
}

@test "an image used by a container is kept and reported" {
  env_set LR_IMAGE_KEEP_PREVIOUS 0
  export FAKE_IN_USE="lareferencia/harvester:lareferencia-${H}-aaaaaaa"
  docker_sh build solr
  assert_success
  assert_output_contains "kept lareferencia/harvester:lareferencia-${H}-aaaaaaa (in use by a container)"
}

@test "dangling images: only those labelled with this compose project" {
  export FAKE_DANGLING=1
  docker_sh build solr
  assert_success
  assert_called "docker image prune -f --filter label=com.docker.compose.project=lareferencia-<HASH>"
  refute_global_prune
}

@test "prune: every previous build of this installation, nothing else" {
  export FAKE_BUILDER_EXISTS=1 FAKE_DANGLING=1
  docker_sh prune
  assert_success
  run removed_images
  [ "$(printf '%s\n' "${output}" | wc -l | tr -d ' ')" = 4 ] || { echo "${output}"; false; }
  refute_called "0ther00"
  refute_called "docker rmi lareferencia/solr:$(current_image_tag)"
  refute_global_prune
  assert_snapshot prune
}

@test "history decides, not the tag name: newest previous build is kept" {
  printf '%s\n' "lareferencia-${H}-aaaaaaa" "lareferencia-${H}-bbbbbbb" > "${SANDBOX_ROOT}/Docker/.image-tags"
  docker_sh build solr
  assert_success
  run removed_images
  [ "${output}" = "lareferencia/harvester:lareferencia-<HASH>-aaaaaaa
lareferencia/solr:lareferencia-<HASH>-aaaaaaa" ] || { echo "${output}"; false; }
}

@test "no history yet (first build after the update): nothing removed, history created" {
  rm -f "${SANDBOX_ROOT}/Docker/.image-tags"
  docker_sh build solr
  assert_success
  assert_output_contains "previous images are kept this time"
  refute_called "docker rmi"
  [ "$(cat "${SANDBOX_ROOT}/Docker/.image-tags")" = "${CUR}" ]
}

@test "history records each build once and stays bounded" {
  docker_sh build solr
  docker_sh build solr
  assert_success
  [ "$(tail -n 1 "${SANDBOX_ROOT}/Docker/.image-tags")" = "${CUR}" ]
  [ "$(grep -c "^${CUR}$" "${SANDBOX_ROOT}/Docker/.image-tags")" = 1 ]
  seq 1 80 | sed 's/^/old-/' > "${SANDBOX_ROOT}/Docker/.image-tags"
  docker_sh build solr
  [ "$(wc -l < "${SANDBOX_ROOT}/Docker/.image-tags" | tr -d ' ')" = 50 ]
}

@test "failed build: history and images untouched" {
  export FAKE_FAIL="build solr"
  docker_sh build solr
  assert_failure
  refute_called "docker rmi"
  [ "$(wc -l < "${SANDBOX_ROOT}/Docker/.image-tags" | tr -d ' ')" = 2 ]
}

@test "builds use Docker's default builder (no dedicated builder is created)" {
  docker_sh build solr
  assert_success
  refute_called "buildx create"
  [ -z "$(calls | grep -E '^docker compose .* build' | grep -v '\[builder: default\]')" ]
  refute_global_prune
}

@test "builder 'lareferencia' left by a previous version is removed after the build" {
  export FAKE_BUILDER_EXISTS=1
  docker_sh build solr
  assert_success
  assert_output_contains "Removing the unused 'lareferencia' buildx builder"
  assert_called "docker buildx rm lareferencia"
}

@test "no legacy builder → nothing to remove" {
  docker_sh build solr
  assert_success
  refute_called "buildx rm"
}

@test "prune also removes the legacy builder" {
  export FAKE_BUILDER_EXISTS=1
  docker_sh prune
  assert_success
  assert_called "docker buildx rm lareferencia"
}
