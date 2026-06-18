# world-cup-pool image

The `public-applications/world-cup-pool` service runs a locally-built image.

- Upstream source: https://github.com/oyvhov/world-cup-pool (based on
  https://github.com/floholz/wm-pickems)
- Binary entrypoint: `wm-pickems`, default command `serve --http=0.0.0.0:8090 --dir=/pb_data`
- Built originally by Portainer; the image is tagged locally as
  `public-applications-world-cup-pool` (no registry).

## Pass-2 plan
Set up a Komodo **Build** that clones the upstream repo, builds, and pushes to a
registry (GHCR or local), then point the stack `image:` at that tag. For now the
compose uses the existing local image with `pull_policy: never`.
