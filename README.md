# PsychoPy on macOS — simple installer

`Install-PsychoPy-macOS.sh` is a small interactive installer. It asks two things —
**what** to install and **which version** — and installs it. If a matching install
already exists, it offers to delete it first.

## Run it

Open Terminal, `cd` to the folder with the script, then:

```bash
bash Install-PsychoPy-macOS.sh
```

Run it directly (not piped) since it's interactive.

## What it asks

1. **What to install:**
   - **PsychoPy Studio** — the newer Electron app (`PsychoPy_Studio_<ver>.dmg`).
   - **PsychoPy Standalone** — the classic app (`StandalonePsychoPy-<ver>-macOS-<arch>-<pyver>.dmg`).
   - **PsychoPy in a Conda environment** — a per-user `psychopy` env; installs a per-user
     Miniconda first if you don't already have conda (no admin needed).
2. **Which version** — type one like `2026.2.0`, or leave blank for the latest.

If a matching install is found (the Studio app, the Standalone app, or the `psychopy`
conda env), you're asked whether to delete it before installing. For the apps, declining
just lets the new copy overwrite it; for conda, declining reuses the existing env.

## Notes

- **No admin needed for conda.** Copying an app into `/Applications` may prompt for your
  password if that folder isn't user-writable.
- **Architecture-aware.** On Apple Silicon the Standalone picks the `arm64` build and conda
  installs an `arm64` Miniconda; on Intel it picks `x86_64`. Studio's macOS dmg is universal.
- **Conda uses conda-forge** (`--override-channels`, with `pip` added) to avoid Anaconda's
  default-channel Terms-of-Service gate and large-org licensing.
- After a **conda** install, open a new terminal and `conda activate psychopy` (the script
  runs `conda init` for zsh and bash), or run experiments directly with the env's Python.
