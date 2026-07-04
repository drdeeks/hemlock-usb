# Ventoy Configuration Reference (localized)

> Curated reference for the Ventoy plugins this project uses or validates.
> Always cross-check against the **upstream docs** for your installed Ventoy
> version: <https://www.ventoy.net/en/plugin.html>.
>
> The `Ventoy.json Doctor` (menu option **12 → 9**) validates a real
> `ventoy.json` against the subset documented here.

---

## 1. Layout

```
<USB-mount>/
├── *.iso                          # any bootable ISOs Ventoy will list
├── persistence/
│   └── <name>.dat                 # ext4 image labeled casper-rw (per ISO)
└── ventoy/
    ├── ventoy.json                # plugins (this file)
    ├── theme/...                  # optional theme assets
    └── (Ventoy bootloader files)
```

- `ventoy.json` lives at **`<mount>/ventoy/ventoy.json`** (NOT the mount root).
- All file paths inside `ventoy.json` are **relative to the USB partition root**
  (so an ISO at `/<mount>/ubuntu.iso` is referenced as `"/ubuntu.iso"`).
- Ventoy reads `ventoy.json` only on boot — changes take effect on next boot.

---

## 2. ventoy.json — top-level shape

```json
{
  "control":          [ { "VTOY_DEFAULT_MENU_MODE": "0" } ],
  "theme":            { "file": "/ventoy/theme/blur/theme.txt" },
  "menu_alias":       [ { "image": "/ubuntu-24.04.iso", "alias": "Ubuntu 24.04 LTS" } ],
  "menu_class":       [ { "key":   "ubuntu",        "class": "ubuntu" } ],
  "menu_extension":   [ { "extension": "vhd",        "class": "vhd" } ],
  "menu_tip":         [ { "image": "/ubuntu-24.04.iso", "tip": "Long-term support" } ],
  "auto_install":     [ { "image": "/ubuntu-24.04.iso", "template": "/ventoy/preseed.cfg" } ],
  "persistence":      [ { "image": "/ubuntu-24.04.iso", "backend": "/persistence/ubuntu.dat" } ],
  "injection":        [ { "image": "/ubuntu-24.04.iso", "archive": "/inject.tar.gz" } ],
  "conf_replace":     [ { "image": "/ubuntu-24.04.iso", "org": "/isolinux/txt.cfg", "new": "/replace/txt.cfg" } ],
  "password":         { "menu_pwd": "txt#myPassword" },
  "image_list":       [ "/ubuntu-24.04.iso", "/debian-12.iso" ],
  "image_blacklist":  [ "/old.iso" ],
  "dud":              [ { "image": "/foo.iso", "dud": ["/x.iso"] } ],
  "auto_memdisk":     [ "/some-tool.iso" ]
}
```

Every plugin is **optional**. With no `ventoy.json`, Ventoy just lists every
ISO it finds and uses its built-in defaults.

---

## 3. Plugins this project uses or validates

### 3.1 `persistence` — the boot router we drive

```json
"persistence": [
  {
    "image":   "/ubuntu-24.04.4-desktop-amd64.iso",
    "backend": "/persistence/ubuntu-persistence.dat",
    "autosel": 1
  }
]
```

| Field     | Required | Notes |
|-----------|---------|-------|
| `image`   | yes | Path to the ISO this rule applies to (relative to mount). |
| `backend` | yes | Path to the persistence image (relative to mount). Must be ext4 with label `casper-rw` for Ubuntu/casper. |
| `autosel` | no  | Auto-select index (1-based) when Ventoy shows the persistence menu; `0` = no persistence; `-1` = always prompt. |

**Multiple backends per ISO** — supply an array on `backend` to give the user a
boot-time menu of overlays (Ventoy displays the names):

```json
"persistence": [
  {
    "image":   "/ubuntu-24.04.iso",
    "backend": [
      "/persistence/tooling.dat",
      "/persistence/models.dat",
      "/persistence/agents.dat"
    ],
    "autosel": 1
  }
]
```

> **Important:** the live ISO can only mount **one** persistence overlay as the
> rootfs at a time. To use several states together, treat one as the primary
> overlay and mount the others as **data volumes** inside the booted system
> (e.g. `/etc/fstab`, `systemd .mount` units, or Docker `data-root`).

### 3.2 `control` — boot-time defaults

```json
"control": [
  { "VTOY_DEFAULT_MENU_MODE": "0" },
  { "VTOY_TREE_VIEW_MENU_STYLE": "0" },
  { "VTOY_FILT_DOT_UNDERSCORE_FILE": "1" },
  { "VTOY_DEFAULT_KBD_LAYOUT": "QWERTY_USA" },
  { "VTOY_MENU_TIMEOUT": "5" },
  { "VTOY_SECONDARY_TIMEOUT": "3" },
  { "VTOY_DEFAULT_IMAGE": "/ubuntu-24.04.iso" },
  { "VTOY_DEFAULT_SEARCH_ROOT": "/iso" }
]
```

Common keys (one entry per object):

| Key | Purpose |
|---|---|
| `VTOY_DEFAULT_IMAGE` | Autoboot this ISO when the menu times out. |
| `VTOY_MENU_TIMEOUT` | Seconds before autoboot (main menu). |
| `VTOY_SECONDARY_TIMEOUT` | Seconds before submenu autoboot. |
| `VTOY_DEFAULT_MENU_MODE` | `0` = list, `1` = tree. |
| `VTOY_TREE_VIEW_MENU_STYLE` | tree variant. |
| `VTOY_FILT_DOT_UNDERSCORE_FILE` | hide macOS `._*` files. |
| `VTOY_DEFAULT_SEARCH_ROOT` | restrict the auto-scan to a subdir. |
| `VTOY_DEFAULT_KBD_LAYOUT` | keyboard layout for the Ventoy menu. |

### 3.3 `menu_alias` / `menu_class` / `menu_extension` / `menu_tip`

Cosmetic / classification:

```json
"menu_alias":     [ { "image": "/ubuntu-24.04.iso", "alias": "Ubuntu 24.04 LTS" } ],
"menu_class":     [ { "key":   "ubuntu",            "class": "ubuntu" } ],
"menu_extension": [ { "extension": "vhd",           "class": "vhd" } ],
"menu_tip":       [ { "image": "/ubuntu-24.04.iso", "tip": "Long-term support — recommended" } ]
```

### 3.4 `auto_install` — unattended installs

```json
"auto_install": [
  {
    "image":    "/ubuntu-24.04.iso",
    "template": [ "/ventoy/preseed.cfg" ],
    "autosel":  1
  }
]
```

Template files live on the USB and follow the distro's preseed/kickstart
syntax (Ubuntu: preseed, Fedora/RHEL: kickstart, Windows: autounattend.xml).

### 3.5 `injection` — inject a tarball into the live initramfs

```json
"injection": [
  { "image": "/ubuntu-24.04.iso", "archive": "/inject/setup.tar.gz" }
]
```

The tarball is extracted under `/ventoy` inside the live system early in boot.

### 3.6 `conf_replace` — replace a file inside the ISO at boot

```json
"conf_replace": [
  {
    "image": "/ubuntu-24.04.iso",
    "org":   "/isolinux/txt.cfg",
    "new":   "/replace/txt.cfg"
  }
]
```

Useful for patching boot params without rebuilding the ISO.

### 3.7 `password`

```json
"password": {
  "menu_pwd":  "txt#myPassword",
  "vtoy_pwd":  "txt#myPassword",
  "bootpwd":   "txt#myPassword"
}
```

Formats:

| Prefix | Meaning |
|---|---|
| `txt#…` | plaintext |
| `md5#…` | MD5 hash |
| `sha256#…` | SHA-256 hash (recommended) |

### 3.8 `image_list` / `image_blacklist`

Whitelist or hide ISOs from the menu (paths relative to mount).

### 3.9 `dud`, `auto_memdisk`

`dud` — supply a "driver update disk" to an installer ISO.
`auto_memdisk` — boot the ISO via memdisk automatically.

---

## 4. Backend (persistence image) requirements

- **Filesystem:** ext4 (or ext2/ext3) — Ventoy mounts the image and the live
  system's overlay driver expects a standard ext fs.
- **Label:** `casper-rw` for **Ubuntu/casper** (Mint, Pop!_OS, etc.).
  Debian/Kali use `persistence` + a `persistence.conf` file at the root with
  `/ union`. Other distros vary.
- **Size:** Ventoy reads the file size as-is; you size it at creation
  (`dd if=/dev/zero of=foo.dat bs=1M count=8192 && mkfs.ext4 -F -L casper-rw foo.dat`).
- **Path in `backend`:** relative to the USB partition root.

This project's Persistence Manager (menu option **12 → 2**) creates these
correctly. The Volume Rename/Relabel actions (**12 → 7/8**) guard the
`casper-rw` label because removing it breaks live-boot persistence.

---

## 5. Hot/cold edits

- `ventoy.json` is read on boot. You can edit it while the USB is mounted on a
  host — the next Ventoy boot picks up the change.
- Updating Ventoy itself preserves user files (ISOs, persistence, `ventoy.json`).
- The doctor (option 12 → 9) does **not** rewrite the file. Any future
  writer must call the convention helper to back up first
  (`_uca_ventoy_json_backup` → writes `ventoy.json.bak.<timestamp>`).

---

## 6. Quick recipes

**Autoboot Ubuntu after 5s, with the configured persistence:**
```json
{
  "control": [
    { "VTOY_DEFAULT_IMAGE": "/ubuntu-24.04.iso" },
    { "VTOY_MENU_TIMEOUT": "5" }
  ],
  "persistence": [
    { "image": "/ubuntu-24.04.iso", "backend": "/persistence/tooling.dat", "autosel": 1 }
  ]
}
```

**Offer a menu of three persistence states for one ISO:**
```json
{
  "persistence": [
    {
      "image": "/ubuntu-24.04.iso",
      "backend": [
        "/persistence/tooling.dat",
        "/persistence/models.dat",
        "/persistence/agents.dat"
      ]
    }
  ]
}
```

**Hide a stale ISO:**
```json
{ "image_blacklist": [ "/old/ubuntu-22.04.iso" ] }
```

---

## 7. Authoritative sources

- Ventoy site: <https://www.ventoy.net>
- Plugin docs: <https://www.ventoy.net/en/plugin.html>
- GitHub: <https://github.com/ventoy/Ventoy>

When this reference and the upstream docs disagree, the **upstream docs win**;
re-curate this file in the same commit as the doctor change that exposed the
divergence.
