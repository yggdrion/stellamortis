## Downloads

| File | Platform |
|---|---|
| `stellamortis-<version>-windows.zip` | Windows x86_64 |
| `stellamortis-<version>-linux.zip` | Linux x86_64 |
| `stellamortis-<version>-macos.zip` | macOS, universal: Intel (x86_64) and Apple Silicon (arm64) |

### macOS

The app is ad-hoc signed but not notarized, so Gatekeeper blocks the first start. Either
right-click `stellamortis.app` and choose **Open**, or remove the quarantine flag once:

```bash
xattr -dr com.apple.quarantine stellamortis.app
```

### Discord

Rich Presence on Linux and macOS needs `nc`, `ncat` or `socat` installed.
