<div align="center">
  <h1>Mole</h1>
  <p><em>Dig deep like a mole to clean your Mac.</em></p>
</div>

<p align="center">
  <a href="https://github.com/tw93/mole/stargazers"><img src="https://img.shields.io/github/stars/tw93/mole?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/tw93/mole/releases"><img src="https://img.shields.io/github/v/tag/tw93/mole?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/tw93/mole/commits"><img src="https://img.shields.io/github/commit-activity/m/tw93/mole?style=flat-square" alt="Commits"></a>
  <a href="https://twitter.com/HiTw93"><img src="https://img.shields.io/badge/follow-Tw93-red?style=flat-square&logo=Twitter" alt="Twitter"></a>
  <a href="https://t.me/+GclQS9ZnxyI2ODQ1"><img src="https://img.shields.io/badge/chat-Telegram-blueviolet?style=flat-square&logo=Telegram" alt="Telegram"></a>
</p>

<p align="center">
  <img src="https://cdn.tw93.fun/img/mole.jpeg" alt="Mole - 95.50GB freed" width="800" />
  <p align="center">由于 Mole 还在中级版本，如果这台 Mac 对你非常重要，建议再等等。</p>
</p>

## Features

- **Deep System Cleanup** - Cleans way more junk than CleanMyMac/Lemon - caches, logs, temp files
- **Thorough Uninstall** - Scans 22+ locations to remove app leftovers, not just the .app file
- **System Optimization** - Rebuilds caches, resets services, and trims swap/network cruft with one run
- **Interactive Disk Analyzer** - Navigate folders with arrow keys, find and delete large files quickly
- **Fast & Lightweight** - Terminal-based with arrow-key navigation, pagination, and Touch ID support

## Quick Start

**Install:**

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash
```

Or via Homebrew:

```bash
brew install tw93/tap/mole
```

**Run:**

```bash
mo                      # Interactive menu
mo clean                # System cleanup
mo clean --dry-run      # Preview mode
mo clean --whitelist    # Manage protected caches
mo uninstall            # Uninstall apps
mo optimize             # System optimization
mo analyze              # Disk analyzer

mo touchid              # Configure Touch ID for sudo
mo update               # Update Mole
mo remove               # Remove Mole from system
mo --help               # Show help
mo --version            # Show installed version

```

## Tips

- Safety first, if your Mac is mission-critical, wait for Mole to mature before full cleanups.
- Preview the cleanup by running `mo clean --dry-run` and reviewing the generated list.
- Protect caches with `mo clean --whitelist`; defaults cover Playwright, HuggingFace, Maven, and Surge Mac paths.
- Use `mo touchid` to approve sudo with Touch ID instead of typing your password.

## Quick Launchers

One command sets up Raycast + Alfred shortcuts for `mo clean` and `mo uninstall`:

```bash
curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/integrations/setup-quick-launchers.sh | bash
```

Done! Use `mo` search to quickly find them. See [integrations/README.md](integrations/README.md) for details.

## Features in Detail

### Deep System Cleanup

```bash
$ mo clean

Scanning cache directories...

  ✓ User app cache                                           45.2GB
  ✓ Browser cache (Chrome, Safari, Firefox)                  10.5GB
  ✓ Developer tools (Xcode, Node.js, npm)                    23.3GB
  ✓ System logs and temp files                                3.8GB
  ✓ App-specific cache (Spotify, Dropbox, Slack)              8.4GB
  ✓ Trash                                                     12.3GB

====================================================================
Space freed: 95.5GB | Free space now: 223.5GB
====================================================================
```

### Smart App Uninstaller

```bash
$ mo uninstall

Select Apps to Remove
═══════════════════════════
▶ ☑ Adobe Creative Cloud      (12.4G) | Old
  ☐ WeChat                    (2.1G) | Recent
  ☐ Final Cut Pro             (3.8G) | Recent

Uninstalling: Adobe Creative Cloud

  ✓ Removed application
  ✓ Cleaned 52 related files across 12 locations
    - Application Support, Caches, Preferences
    - Logs, WebKit storage, Cookies
    - Extensions, Plugins, Launch daemons

====================================================================
Space freed: 12.8GB
====================================================================
```

### System Optimization

```bash
$ mo optimize

System: 5/32 GB RAM | 333/460 GB Disk (72%) | Uptime 6d

  ✓ Rebuild system databases and flush caches
  ✓ Reset network services
  ✓ Refresh Finder and Dock
  ✓ Clean diagnostic and crash logs
  ✓ Purge swap files and restart dynamic pager
  ✓ Rebuild launch services and spotlight index

====================================================================
System optimization completed
====================================================================
```

### Disk Space Analyzer

```bash
$ mo analyze

Analyze Disk  ~/Documents  |  Total: 156.8GB

 ▶  1. ███████████████████  48.2%  |  📁 Library                     75.4GB  >6mo
    2. ██████████░░░░░░░░░  22.1%  |  📁 Downloads                   34.6GB
    3. ████░░░░░░░░░░░░░░░  14.3%  |  📁 Movies                      22.4GB
    4. ███░░░░░░░░░░░░░░░░  10.8%  |  📁 Documents                   16.9GB
    5. ██░░░░░░░░░░░░░░░░░   5.2%  |  📄 backup_2023.zip              8.2GB

  ↑↓←→ Navigate  |  O Open  |  F Reveal  |  ⌫ Delete  |  L Large(24)  |  Q Quit
```

## Support

- If Mole reclaimed storage for you, consider starring the repo or sharing it with friends needing a cleaner Mac.
- Have ideas or fixes? Open an issue or PR and help shape Mole's roadmap together with the community.
- Love cats? Treat Tangyuan and Cola to canned food via <a href="https://miaoyan.app/cats.html?name=Mole" target="_blank">this link</a> and keep the mascots purring.

## License

MIT License - feel free to enjoy and participate in open source.
