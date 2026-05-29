# no_eligible_sources fixture

This fixture deliberately contains no eligible Zig source files. It models
failure mode F-006 (`ZNTL_PROJECT_NO_SOURCES`): zentinel must fail project
analysis before mutation generation when a project has no eligible sources.

Only this README and `fixture.toml` live here; there is intentionally no `.zig`
source to mutate.
