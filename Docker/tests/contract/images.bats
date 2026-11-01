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

# Nothing global, ever: every prune is filtered or bound to the dedicated builder.
refute_global_prune() {
  if calls | grep -E 'docker (image|system|volume|container|builder) prune' | grep -v -- '--filter label=com.docker.compose.project=' ; then
    echo "global prune found"; return 1
  fi
  if calls | grep 'docker buildx prune' | grep -v -- '--help' | grep -v -- '--builder lareferencia'; then
    echo "buildx prune without the dedicated builder"; return 1
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

@test "build cache: dedicated builder capped at 5GB by default" {
  docker_sh build solr
  assert_success
  assert_called "docker buildx create --name lareferencia --driver docker-container"
  assert_called "build solr   [builder: lareferencia]"
  assert_called "docker buildx prune --builder lareferencia -f --max-used-space 5GB"
}

@test "build cache: existing builder is reused" {
  export FAKE_BUILDER_EXISTS=1
  docker_sh build solr
  assert_success
  refute_called "buildx create"
  assert_called "build solr   [builder: lareferencia]"
}

@test "build cache: older buildx uses --keep-storage" {
  export FAKE_BUILDX_OLD=1
  docker_sh build solr
  assert_success
  assert_called "docker buildx prune --builder lareferencia -f --keep-storage 5GB"
}

@test "build cache: LR_BUILD_CACHE_MAX_SIZE=off → no cap" {
  env_set LR_BUILD_CACHE_MAX_SIZE off
  docker_sh build solr
  assert_success
  refute_called "buildx prune --builder"
}

@test "LR_DEDICATED_BUILDER=false: default builder, cache untouched" {
  env_set LR_DEDICATED_BUILDER false
  docker_sh build solr
  assert_success
  refute_called "buildx create"
  assert_called "build solr   [builder: default]"
  refute_called "buildx prune"
}

@test "builder cannot be created: falls back to the default builder and still builds" {
  export FAKE_FAIL="buildx create"
  docker_sh build solr
  assert_success
  assert_output_contains "using Docker's default builder"
  assert_called "build solr   [builder: default]"
  refute_called "buildx prune --builder"
}

@test "prune: every previous build of this installation + La Referencia cache only" {
  export FAKE_BUILDER_EXISTS=1 FAKE_DANGLING=1
  docker_sh prune
  assert_success
  run removed_images
  [ "$(printf '%s\n' "${output}" | wc -l | tr -d ' ')" = 4 ] || { echo "${output}"; false; }
  refute_called "0ther00"
  refute_called "docker rmi lareferencia/solr:$(current_image_tag)"
  assert_called "docker buildx prune --builder lareferencia -af"
  refute_global_prune
  assert_snapshot prune
}

@test "build cache: custom cap from .env" {
  env_set LR_BUILD_CACHE_MAX_SIZE 12GB
  docker_sh build solr
  assert_success
  assert_called "docker buildx prune --builder lareferencia -f --max-used-space 12GB"
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
