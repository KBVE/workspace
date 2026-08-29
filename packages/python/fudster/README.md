# fudster

API surface, browser and screen automation, and the CLI that fronts the
[`kbve`](../kbve) core modules.

## Installation

```bash
pip install fudster                  # API, CLI, Claude and gRPC commands
pip install 'fudster[automation]'    # screen and input control (opencv, pyautogui)
pip install 'fudster[browser]'       # SeleniumBase
pip install 'fudster[ocr]'           # pytesseract
pip install 'fudster[vnc]'           # websockify
```

`kbve[server]` is a base dependency — the CLI's `grpc` and `serve` commands
reach `kbve.grpc` and `kbve.health`, which live behind that extra.

**Not installable outside this workspace yet.** `kbve` on PyPI is the old
1.0.13 from the Nx workspace, which has no `server` extra; uv and pip resolve
it, warn, and continue. `kbve-py:build` produces the wheel this is meant to run
against, and `fudster:verify` installs the two together and fails if the
registry copy is what turned up.

## Development

```bash
moon run fudster:test
moon run fudster:lint
moon run fudster:verify
```

Extras are not installed by default — `automation` alone is opencv, pyautogui
and numpy. The suite covers the API and the CLI, neither of which needs them.

## What is not here

The `nx` command group. It rendered the Nx project graph and the security audit
into Starlight MDX through `kbve.nx.graph` and `kbve.nx.security`; neither the
module nor the Nx graph it read exists in this workspace, because moon replaced
both.

`fudster info` used to read a hand-maintained module registry in
`kbve.utils.module_info` — which still advertised `kbve.nx` after that module
was deleted. It walks the `kbve` package now, so it cannot drift, and reports
"missing" for modules whose extra is not installed.
