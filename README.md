# 📚 Kindle-Disk-Filler

A small utility that fills up the storage on your Kindle (or any USB device) with harmless dummy files — leaving just enough free space for normal use. This prevents Amazon's automatic over-the-air (OTA) firmware updates from downloading, which is especially useful if you want to keep a jailbroken Kindle on its current firmware.

Works on **Windows** (PowerShell), **Linux**, and **macOS** (Bash). No installation required.

---

## ⚠️ Warning

> **Jailbreaking your Kindle may void its warranty and is done entirely at your own risk.**
> This tool does not jailbreak your device — it only fills storage space. However, it is intended to support the jailbreaking workflow by blocking firmware updates.
>
> The authors are not responsible for any damage to your device, loss of data, or other consequences resulting from the use of this tool.

---

## 🗂️ Table of Contents

1. [How it works](#-how-it-works)
2. [Download](#-download)
3. [Prerequisites](#-prerequisites)
4. [Windows instructions (PowerShell)](#-windows-instructions-powershell)
5. [Linux / macOS instructions (Bash)](#-linux--macos-instructions-bash)
6. [Recommended settings](#-recommended-settings)
7. [Freeing up space again](#-freeing-up-space-again)
8. [FAQ / Troubleshooting](#-faq--troubleshooting)
9. [License](#-license)

---

## 💡 How it works

When run, the script:

1. Shows you how much free space is currently available on the device.
2. Asks how many megabytes (MB) you want to keep free (we recommend 20–50 MB).
3. Creates a `filler_chunks/` folder on the device and fills it with dummy files (chunks of 100 MB, 10 MB, and 1 MB).
4. Displays a live progress bar so you can see exactly how far along it is.

The dummy files are named clearly (e.g. `filler_chunk_0001_100MB.bin`) so you always know their size at a glance and can delete individual ones later to reclaim exactly as much space as you need.

---

## ⬇️ Download

You only need **one file** — either `filler.ps1` (Windows) or `filler.sh` (Linux/macOS). Here are two ways to get it:

### Option A — Download a single file (recommended for most users)

1. Click the file you need:
   - Windows: [`filler.ps1`](filler.ps1)
   - Linux / macOS: [`filler.sh`](filler.sh)
2. On the file page, click the **download button** (the arrow pointing downward ⬇, in the top-right corner of the code view, right next to the "Raw" button).  
   The file will be saved directly to your Downloads folder with the correct filename.
3. Copy the saved file to the root of your Kindle (see [Prerequisites](#-prerequisites) below).

### Option B — Clone the whole repository (if you have Git installed)

```bash
git clone https://github.com/tobiwein/Kindle-Disk-Filler.git
```

Then copy the relevant script to your Kindle.

---

## ✅ Prerequisites

Before you start, make sure you have the following ready:

- **A Kindle connected to your computer via USB.** When you plug it in, your Kindle should appear as a USB drive (like a USB stick) in your file explorer.
- **The script file copied to the root directory of your Kindle.** The root directory is the top-level folder you see when you open the Kindle drive — the one that contains folders like `documents`, `music`, etc.
  - For **Windows**, copy `filler.ps1` there.
  - For **Linux / macOS**, copy `filler.sh` there.
- **No special software** needs to be installed.

> 💡 **How do I find the Kindle drive?**
> - **Windows:** Open File Explorer (`Win + E`). Your Kindle will appear under "This PC" or "Devices and drives", usually with a drive letter like `E:` or `F:`.
> - **macOS:** Open Finder. Your Kindle appears in the left sidebar under "Locations".
> - **Linux:** Your Kindle is usually mounted automatically under `/media/your-username/Kindle` or similar.

---

## 🪟 Windows Instructions (PowerShell)

### Step 1 — Open PowerShell in the right folder

1. Open **File Explorer** and navigate to your Kindle drive (e.g. `E:\`).
2. Click in the address bar at the top (where it shows the path), type `powershell`, and press **Enter**.

   A blue PowerShell window will open, already pointed at your Kindle.

   > 💡 Alternatively, press `Win + X` and choose **"Windows PowerShell"** or **"Terminal"**, then navigate to the drive manually:
   > ```powershell
   > cd E:\
   > ```
   > *(Replace `E:` with the actual drive letter of your Kindle.)*

### Step 2 — Allow the script to run

Windows blocks scripts from running by default as a security measure. You need to allow it just for this session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

> This only applies to the current PowerShell window and resets automatically when you close it. It does **not** change any permanent system settings.

### Step 3 — Run the script

```powershell
.\filler.ps1
```

The script will start, show you the available space, and ask how much you want to keep free. Follow the on-screen prompts.

> 💡 **Want to run it on a different folder?** Pass the path as an argument:
> ```powershell
> .\filler.ps1 -TargetPath "E:\"
> ```

### Step 4 — Wait for it to finish

A progress bar will appear, showing the overall progress:

```
  [████████████░░░░░░░░░░░░░░░░░░░░]  130 MB / 326 MB (40%)  — chunk 2/5
```

Once it reaches 100%, you're done. You can safely close PowerShell and disconnect your Kindle.

> 🛑 **Need to stop early?** Press `Ctrl + C` at any time. The script will safely remove the partially written file so nothing is left in a broken state.

---

## 🐧🍎 Linux / macOS Instructions (Bash)

### Step 1 — Open a terminal

- **macOS:** Press `Cmd + Space`, type **Terminal**, and press Enter.
- **Linux:** Press `Ctrl + Alt + T`, or search for "Terminal" in your app launcher.

### Step 2 — Navigate to your Kindle

Find out where your Kindle is mounted and navigate there:

```bash
# macOS example:
cd /Volumes/Kindle

# Linux example:
cd /media/$USER/Kindle
```

> 💡 Not sure of the path? On **macOS**, open Finder, right-click your Kindle in the sidebar, and choose "Get Info" — the path is shown at the bottom. On **Linux**, run `lsblk` or check your file manager's address bar.

### Step 3 — Make the script executable

You only need to do this once:

```bash
chmod +x filler.sh
```

### Step 4 — Run the script

```bash
./filler.sh
```

The script will show available space and ask how much to keep free. Follow the on-screen prompts.

> 💡 **Want to run it on a specific path without navigating there first?**
> ```bash
> ./filler.sh /Volumes/Kindle
> ```

### Step 5 — Wait for it to finish

A progress bar will appear and update continuously until the drive is filled:

```
  [████████████░░░░░░░░░░░░░░░░░░░░]  130 MB / 326 MB (40%)  — chunk 2/5
```

> 🛑 **Need to stop early?** Press `Ctrl + C` at any time. The script will safely clean up any partially written file.

---

## ⚙️ Recommended Settings

When the script asks **"How much space should remain free?"**, we recommend choosing between **20 and 50 MB**.

| Free space left | When to use it |
|---|---|
| **20 MB** | You want to block updates as aggressively as possible. Leaves minimal room for Kindle's own internal operations. |
| **50 MB** | A safer buffer. Recommended for most users. |
| **Custom** | Choose any value. Make sure to leave at least 10–20 MB so your Kindle doesn't run into issues with its normal operations. |

> ⚠️ **Do not leave 0 MB free.** A completely full device can cause unexpected behaviour on the Kindle. Always leave a small buffer.

---

## 🗑️ Freeing up space again

The dummy files exist only to take up space — they contain no important data and can be deleted at any time.

### When would I want to do this?

- You want to **allow a specific firmware update** (e.g. a security patch you trust).
- You want to **free up space temporarily** for a large book or document transfer.

### How to delete the files

All dummy files are stored in the `filler_chunks/` folder inside your Kindle's root directory. They are named `filler_chunk_XXXX_SIZEMB.bin`.

**Windows (File Explorer):**
1. Open your Kindle in File Explorer.
2. Open the `filler_chunks` folder.
3. Select the files you want to delete and press `Delete`.  
   To delete all of them at once, press `Ctrl + A` to select all, then `Delete`.

**Windows (PowerShell):**
```powershell
# Delete individual files to reclaim a specific amount of space:
Remove-Item E:\filler_chunks\filler_chunk_0001_100MB.bin

# Delete all chunk files at once:
Remove-Item E:\filler_chunks\filler_chunk_*.bin
```
*(Replace `E:` with your Kindle's drive letter.)*

**macOS / Linux (Terminal):**
```bash
# Delete individual files to reclaim a specific amount of space:
rm /Volumes/Kindle/filler_chunks/filler_chunk_0001_100MB.bin

# Delete all chunk files at once:
rm /Volumes/Kindle/filler_chunks/filler_chunk_*.bin
```
*(Replace the path with your actual Kindle mount point.)*

> 💡 **Want to free only a little bit of space?** Delete just one or two files. For example, deleting one `100MB` chunk frees exactly 100 MB. This is why the files are split into chunks with their size in the name.

---

## ❓ FAQ / Troubleshooting

**Q: The script won't start / I get a "permission denied" error on macOS or Linux.**

Make sure you made the script executable first:
```bash
chmod +x filler.sh
```
Also make sure you're running it with `./filler.sh` (with the `./` prefix), not just `filler.sh`.

---

**Q: On Windows, I get an error saying "running scripts is disabled".**

Run this command first in your PowerShell window to allow scripts for this session:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
Then try running the script again.

---

**Q: My Kindle is not showing up as a drive.**

- Make sure you're using a **data-capable USB cable**. Some cables are charge-only and cannot transfer files.
- On your Kindle, you may see a prompt asking what to do when connected — choose **"Transfer files"** (or "File Transfer" / "USB drive" depending on your model).
- Try a different USB port or cable.

---

**Q: The script says "Nothing to do" right away.**

The available space is already at or below the amount you chose to keep free. Either you have already run the script before, or the drive is already nearly full. Check what files are on the device and delete some if needed, then run the script again.

---

**Q: Can I run the script multiple times?**

Yes! The script is designed to be run repeatedly. It detects any previously created chunks and starts numbering new ones from where it left off, so nothing is overwritten or duplicated.

---

**Q: How do I know if the update was blocked successfully?**

On a Kindle, OTA updates require a certain amount of free space to download. As long as your Kindle's storage is kept full (with only your chosen buffer remaining), updates cannot be downloaded. You can verify by going to **Settings → Device Options → Advanced Options → Update Your Kindle**: if it is greyed out or says "Your Kindle is up to date", no update is queued.

---

**Q: Will this delete my books or documents?**

No. The script only creates new files in the location you point it to. It never reads, modifies, or deletes any existing files.

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

You are free to use, modify, and distribute this tool for personal or commercial purposes. No warranty is provided.
