# Contributing

Report reproducible problems through GitHub Issues. Include your Pocket firmware,
release version, ROM profile and SHA-1, menu route, expected behavior and observed
behavior. A small device recording can help diagnose audio or sprite problems.
Do not attach ROMs, extracted music or other copyrighted game data.

Keep changes focused. Describe the behavior being corrected and use the relevant
component or production-output fixture. Changes to CPU/peripheral semantics,
clock delivery, memory paths or scheduling need new source-bound verification;
do not reuse passing receipts for changed RTL. Keep the known working release
until the replacement passes all checks. See [building](docs/building.md).

Run `make check-release` for packaging, importer and repository checks. These
checks need Python 3.11+ and Git, and do not need commercial ROMs or Quartus.
They do not replace the RTL or hardware qualification suite.

Contributions to the project's own files use ISC; preserve third-party notices
and describe modifications to vendored files. Use original or appropriately
licensed fixtures.
