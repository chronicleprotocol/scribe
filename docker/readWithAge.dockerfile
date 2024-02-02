# Docker image specification to read price and age from a deployed
# Scribe/ScribeOptimistic instance.
#
# For more information, see docs/Monitoring.md.
#
# Build via:
# ```bash
# $ docker build -t <name of image> -f docker/readWithAge.dockerfile
# ```
#
# Run via:
# ```bash
# $ docker run \
#       -e RPC_URL=$RPC_URL \
#       -e SCRIBE=$SCRIBE \
#       -e SCRIBE_FLAVOUR=$SCRIBE_FLAVOUR \
#       <name of image>
# ```
FROM ghcr.io/foundry-rs/foundry

# Necessary environment variables
ENV RPC_URL=
ENV SCRIBE=
ENV SCRIBE_FLAVOUR=

# Note to compile without --via-ir and optimizations
ENV FOUNDRY_PROFILE=no-via-ir

WORKDIR /app

COPY . .
RUN forge build

ENTRYPOINT forge script --sig $(cast calldata "readWithAge(address)" $SCRIBE) script/${SCRIBE_FLAVOUR}.s.sol:${SCRIBE_FLAVOUR}Script