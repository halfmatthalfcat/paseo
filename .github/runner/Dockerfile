# Custom ARC self-hosted runner image: adds a C toolchain to the stock actions-runner image so
# native-dependency builds (anything invoking cc/ld) work out of the box, without requiring every
# consuming project's CI to install one per job.
#
# Built + published to ghcr by .github/workflows/runner-image.yml. Which ARC scale set consumes it
# is a cluster-side configuration, not tracked in this repo.
#
# The base is pinned by digest, not by a moving tag: this image runs every job dispatched to it, so
# "what executes a job" must be a fact recorded in the diff. Dependabot (docker ecosystem, see
# .github/dependabot.yml) proposes the digest bumps.
FROM ghcr.io/actions/actions-runner:2.336.0@sha256:0cfdcc701ce933c6d243c6b0b2da767366dc9f2e99961d4c3754b0b78084cdda
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential pkg-config git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*
USER runner
