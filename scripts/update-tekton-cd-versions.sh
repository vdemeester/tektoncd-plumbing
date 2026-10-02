#!/usr/bin/env bash
# scripts/update-tekton-cd-versions.sh
#
# Scans tekton/cd/*/kustomization.yaml files for pinned upstream release
# versions and bumps them to the latest GitHub release when a newer one
# is available. Each component that gets bumped is committed separately.
#
# Requires: git, gh (authenticated), sed
#
# Usage:
#   scripts/update-tekton-cd-versions.sh [--dry-run]
#
# Exit code 0 always; sets no outputs itself. Callers should inspect
# `git log` / `git diff` on the current branch after running.
set -euo pipefail

DRY_RUN="${1:-}"

# display name | repo | file | regex capturing the current version
COMPONENTS=(
  "Tekton Triggers|tektoncd/triggers|tekton/cd/triggers/overlays/oci-ci-cd/kustomization.yaml|releases/download/v([0-9.]+)/"
  "Tekton Chains|tektoncd/chains|tekton/cd/chains/overlays/oci-ci-cd/kustomization.yaml|releases/download/v([0-9.]+)/"
  "Tekton Pipelines|tektoncd/pipeline|tekton/cd/pipeline/overlays/oci-ci-cd/kustomization.yaml|releases/download/v([0-9.]+)/"
  "Pipelines-as-Code|tektoncd/pipelines-as-code|tekton/cd/pipelines-as-code/overlays/oci-ci-cd/kustomization.yaml|releases/download/v([0-9.]+)/"
  "Tekton Results|tektoncd/results|tekton/cd/results/base/kustomization.yaml|results/previous/v([0-9.]+)/"
)

for entry in "${COMPONENTS[@]}"; do
  IFS='|' read -r name repo file regex <<<"$entry"

  if [[ ! -f "$file" ]]; then
    echo "::warning::$file not found, skipping $name"
    continue
  fi

  current=$(grep -oE "$regex" "$file" | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  if [[ -z "$current" ]]; then
    echo "::warning::could not find current version for $name in $file, skipping"
    continue
  fi

  # Use the highest semver among non-draft, non-prerelease releases rather
  # than GitHub's "latest" marker or creation date: some repos cut patch
  # releases on older branches after newer minors, which would otherwise
  # confuse both of those signals.
  latest=$(gh api "repos/${repo}/releases" --paginate \
    --jq '.[] | select(.draft==false and .prerelease==false) | .tag_name' \
    | sed 's/^v//' | sort -V | tail -n1)
  if [[ -z "$latest" ]]; then
    echo "::warning::could not determine latest release for $repo, skipping"
    continue
  fi

  if [[ "$current" == "$latest" ]]; then
    echo "$name: up to date (v$current)"
    continue
  fi

  echo "$name: v$current -> v$latest"
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    continue
  fi

  sed -i "s#/v${current}/#/v${latest}/#g" "$file"

  git add "$file"
  git commit -q -m "Bump ${name} to v${latest}

Update from v${current} to v${latest} on the tekton-oracle deployment."
done
