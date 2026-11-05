<div align="center">

# GKI KernelSU SUSFS

**Automated GKI Kernel Builds | SukiSU / BakaSU / FinaSU + SUSFS Integration**

[![Release](https://img.shields.io/github/v/release/LingLuo17/AnyKernel3?label=Release&style=flat-square&logo=github&logoColor=white&color=2ea44f)](https://github.com/LingLuo17/AnyKernel3/releases)
[![Coolapk](https://img.shields.io/badge/Follow-Coolapk-3DDC84?style=flat-square&logo=android&logoColor=white)](http://www.coolapk.com/u/38407386)
[<img src="https://img.shields.io/badge/Join-QQ%20Group-blue?style=flat-square&logo=github&logoColor=white">](https://qm.qq.com/q/PZIFvlcbqU)
[![SukiSU](https://img.shields.io/badge/SukiSU-Supported-5AA300?style=flat-square)](https://sukisu.org/)
[![BakaSU](https://img.shields.io/badge/BakaSU-Supported-5AA300?style=flat-square)](https://bakasu.org/)
[![FinaSU](https://img.shields.io/badge/FinaSU-Supported-5AA300?style=flat-square)](https://github.com/LyraVoid/FinaSU)
[![SUSFS](https://img.shields.io/badge/SUSFS-Integrated-E67E22?style=flat-square)](https://gitlab.com/simonpunk/susfs4ksu)

**English** | [简体中文](#chinese)

</div>

## 📖 Introduction

Built upon [AnyKernel3](https://github.com/osm0sis/AnyKernel3), this repository uses GitHub Actions to automatically compile Android GKI kernels. It integrates multiple KernelSU variants and SUSFS kernel-level spoofing solutions Add practical patches such as ZRAM and BBG.

- The build workflows are adapted from [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS) and [Wild Kernels](https://github.com/WildKernels/GKI_KernelSU_SUSFS)
- Flashing rule: ***It can be flashed as long as the kernel version matches.***

## 📦 Supported Kernel Versions

| Android | Kernel Version | Manual Workflow |
|:---:|:---:|:---:|
| 12 | 5.10 | `kernel-a12-5-10.yml` |
| 13 | 5.10 | `kernel-a13-5-10.yml` |
| 13 | 5.15 | `kernel-a13-5-15.yml` |
| 14 | 5.15 | `kernel-a14-5-15.yml` |
| 14 | 6.1 | `kernel-a14-6-1.yml` |
| 15 | 6.6 | `kernel-a15-6-6.yml` |
| 16 | 6.12 | `kernel-a16-6-12.yml` |
| 17 | 6.18 | `kernel-a17-6-18.yml` |
| Custom | Any | `kernel-custom.yml` |

## ✨ Features

| Feature | Description |
|:---|:---|
| 🔐 KernelSU Variants | Supports SukiSU / BakaSU / FinaSU variants, selectable at build time |
| 🔀 Build Channel | Release: latest **stable** upstream Release (tag commit + same-version manager), falls back to the newest official default-branch build when the upstream only ships pre-releases; Latest: pins the default-branch HEAD and picks the newest manager build matching that version |
| 🙈 SUSFS | Kernel-level hiding working with KSU to complete environment spoofing |
| 💾 ZRAM LZ4 | ZRAM Compression Algorithm Patch |
| 🛡️ BBG (Baseband Guard) | BBG patch to protect the baseband partitions from accidental wipe |
| 🌐 Network enhancement | Optional network stack upgrade: BBRv3 backport where available (defaults to BBR v1 otherwise), full IPSet types up to 65534 sets, fq/fq_codel/cake qdisc, connmark, IPv6 NAT/masquerade, TTL/HopLimit match, WireGuard, CIFS |
| ⚡ KPM | Optional KPM feature / build-time patching |
| 🔔 Re-Kernel | Optional Re-Kernel driver integration |
| 🩹 CVE-2026-43499 | Optional automatic application of the rtmutex fix |
| 📱 OnePlus Snapdragon 8 Elite / Gen5 Support | Optional: Add support for OnePlus Snapdragon 8 Elite / Gen5 processor |
| 🐳 Droidspaces | Optional container support with NTSync kernel compatibility patch |
| 🧩 Skip Incompatible | Optional: auto-skip incompatible or unusable features (except SUSFS and OnePlus 8 Elite/Gen5 support) instead of failing the build |

## 🚀 Usage

1. **Fork this repository** (or use it directly)
2. Go to the **Actions** page and pick the workflow for your kernel version
3. Click **Run workflow** and fill in the parameters as needed:
   - `android_version` / `kernel_version` / `sub_level` / `os_patch_level`
   - `ksu_variant`: KernelSU variant (SukiSU / BakaSU / FinaSU)
   - `build_channel`: build channel
     - `正式 (Release)`: manager APK taken from the latest **stable** upstream Release (`prerelease=false`) and the kernel pinned to that release tag commit, so manager and kernel versions match exactly; when the upstream only ships rc/pre-releases (e.g. BakaSU), the newest official default-branch build is used and pinned instead
     - `最新 (HEAD)`: kernel pinned to the default-branch HEAD, and the manager is the newest build whose version matches HEAD (any branch; SukiSU / BakaSU use official CI builds, FinaSU uses the latest Release), so kernel and manager never drift apart
     - Both channels print the selected channel, pinned commit and manager version in the logs and the run summary
   - Feature switches: `enable_susfs`, `use_zram`, `use_bbg`, `use_net_enhance`, `use_kpm`, `skip_incompatible`, etc.
4. Once the build finishes, download the **Artifacts** from the run page:
   - `AnyKernel3.zip` — flashable zip (recommended; flash via custom Recovery or KSU)
   - `boot.img` / `boot-gz.img` / `boot-lz4.img` — boot images for each compression format

> 💡 Artifacts are uploaded as Actions Artifacts by default and are not auto-published as Releases. Failed runs additionally upload build logs (`Build-Logs`) and patch conflict records (`Rejects`) for troubleshooting.

## 🔧 Custom Commit Configuration

The [`config/config`](config/config) file lets you pin specific commits for SUSFS and SukiSU.

**What is a commit?**

A commit is a hash string representing the state of a repository at a certain point in time. For example, setting SukiSU to `4b8644515fe6d87a109129e590ccd9d33a855dca` means the kernel will be built with the SukiSU version from January 30.

**Why pin a commit?**

- Roll back to a stable version when upstream updates introduce bugs or compatibility issues
- Manually specify a compatible version when SUSFS and SukiSU are out of sync and the build fails

**How to get a commit hash?**

- SUSFS: [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) (GitLab → Repository → Commits)
- SukiSU: [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra/commits) (GitHub commit history page)

## 🛠️ Recommended After Installation
### 🔧 Xposed Modules
| Module | Description |
|:---:|:---|
| **FuseFixer** | [Unicode zero-width character fix module](https://github.com/5ec1cff/FuseFixer) |

## 🙏 Acknowledgments

- [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS) / [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS)
- [SukiSU](https://sukisu.org/) / [BakaSU](https://bakasu.org/) / [FinaSU](https://github.com/LyraVoid/FinaSU)
- [SUSFS](https://gitlab.com/simonpunk/susfs4ksu)

<div align="center">

## ⚠️ Disclaimer

</div>

- Flashing this kernel will not void your warranty, but there is always a risk of bricking your device. Please make sure to:
- 💾 Back up your data
- 🧠 Understand the risks before proceeding

- Please make sure to back up the original boot image of this system in advance.

- If flashing AnyKernel3 causes your device to enter an infinite boot loop or fail to boot, enter BootLoader and flash the original boot image back.

- I take no responsibility for any issues caused by flashing this kernel.

<div align="center">
  
# **🚨 Proceed at your own risk!**

</div>

---

<div align="center">

<a id="chinese"></a>

# GKI KernelSU SUSFS

**自动化构建 GKI 内核 | 集成 SukiSU/BakaSU/FinaSU + SUSFS**

[English](#gki-kernelsu-susfs) | **简体中文**

</div>

## 📖 简介

本仓库基于 [AnyKernel3](https://github.com/osm0sis/AnyKernel3) 构建，通过 GitHub Actions 自动编译 **Android GKI 内核**，集成多种 KernelSU 变体与 SUSFS 内核级隐藏方案并附加 ZRAM、BBG等实用补丁。

- 构建工作流修改自 [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS) 与 [Wild Kernels](https://github.com/WildKernels/GKI_KernelSU_SUSFS)
- 刷入规则：***只要内核版本匹配即可刷入***

## 📦 支持的内核版本

| Android | 内核版本 | 手动触发工作流 |
|:---:|:---:|:---:|
| 12 | 5.10 | `kernel-a12-5-10.yml` |
| 13 | 5.10 | `kernel-a13-5-10.yml` |
| 13 | 5.15 | `kernel-a13-5-15.yml` |
| 14 | 5.15 | `kernel-a14-5-15.yml` |
| 14 | 6.1 | `kernel-a14-6-1.yml` |
| 15 | 6.6 | `kernel-a15-6-6.yml` |
| 16 | 6.12 | `kernel-a16-6-12.yml` |
| 17 | 6.18 | `kernel-a17-6-18.yml` |
| 自定义 | 任意 | `kernel-custom.yml` |

## ✨ 功能特性

| 特性 | 说明 |
|:---|:---|
| 🔐 KernelSU 变体 | 支持 SukiSU / BakaSU / FinaSU 变体，构建时按需选择 |
| 🔀 构建通道 | 正式：上游最新**正式版** Release（标签提交 + 同版本管理器），上游只有预发布版时改用官方默认分支最新上传构建；最新：锁定默认分支 HEAD，管理器取与 HEAD 版本一致的最新构建 |
| 🙈 SUSFS | 内核级隐藏，配合 KSU 完成环境伪装 |
| 💾 ZRAM LZ4 | ZRAM 压缩算法补丁 |
| 🛡️ BBG 基带保护 | BBG（BaseBand Guard）补丁，保护基带分区，防止基带被意外擦除 |
| 🌐 网络增强 | 可选网络栈增强：可用版本回移 BBRv3（无 backport 时退回 BBR v1）+ IPSet 全类型（集合上限 65534）+ fq/fq_codel/cake 队列 + connmark + IPv6 NAT/伪装 + TTL/HopLimit 匹配 + WireGuard + CIFS |
| ⚡ KPM | 可选开启 KPM 功能 / 构建期修补 |
| 🔔 Re-Kernel | 可选集成 Re-Kernel 驱动 |
| 🩹 CVE-2026-43499 | 可选自动应用 rtmutex 修复补丁 |
| 📱 一加 骁龙8 Elite/Gen5 支持 | 可选添加一加 骁龙8 Elite/Gen5 处理器支持 |
| 🐳 Droidspaces | 可选容器支持及 NTSync 内核兼容补丁 |
| 🧩 兼容跳过 | 可选：功能不兼容或无法使用时自动跳过该功能（SUSFS 与 一加 骁龙8 Elite/Gen5 支持除外，二者失败仍会中断构建），不中断构建 |

## 🚀 使用方法

1. **Fork 本仓库**（或直接使用本仓库）
2. 进入 **Actions** 页面，选择对应内核版本的工作流
3. 点击 **Run workflow**，按需填写参数：
   - `android_version` / `kernel_version` / `sub_level` / `os_patch_level`
   - `ksu_variant`：KernelSU 变体（SukiSU / BakaSU / FinaSU）
   - `build_channel`：构建通道
     - `正式 (Release)`：使用上游最新**正式版** Release（`prerelease=false`）的管理器 APK，内核检出该 Release 标签的同一提交，版本严格一致；上游只有 rc/预发布版时（如 BakaSU），改用官方默认分支最新上传构建并锁定该提交
     - `最新 (HEAD)`：内核锁定默认分支 HEAD，管理器取与 HEAD 版本号一致的最新构建（不限分支，SukiSU / BakaSU 用官方 CI 构建，FinaSU 用最新 Release），避免内核与管理器版本错位
     - 两个通道的日志与运行摘要（Summary）都会打印实际选用的通道、提交与管理器版本
   - 功能开关：`enable_susfs`、`use_zram`、`use_bbg`、`use_net_enhance`、`use_kpm`、`skip_incompatible` 等 
4. 构建完成后，在本次运行页面下载 **Artifacts**：
   - `AnyKernel3.zip` —— 卡刷包（推荐，配合自定义 Recovery 或 KSU 刷入）
   - `boot.img` / `boot-gz.img` / `boot-lz4.img` —— 每种压缩格式的 boot 镜像

> 💡 产物默认上传为 Actions Artifacts，不自动发布 Release；失败时会额外上传构建日志（`Build-Logs`）与补丁冲突记录（`Rejects`）供排查。

## 🔧 自定义提交配置

通过 [`config/config`](config/config) 文件可以指定 SUSFS 和 SukiSU 使用特定的 commit。

**什么是提交 (commit)？**

提交是一串哈希字符串，代表仓库在某个时间点的状态。例如将 SukiSU 设为 `4b8644515fe6d87a109129e590ccd9d33a855dca`，即使用 1 月 30 日的 SukiSU 版本编译内核。

**为什么要指定提交？**

- 当上游仓库更新引入 bug 或兼容性问题时，可回退到稳定版本
- 当 SUSFS 与 SukiSU 版本不同步导致编译失败时，可手动指定兼容的版本

**如何获取提交哈希？**

- SUSFS：[susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)（GitLab → Repository → Commits）
- SukiSU：[SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra/commits)（GitHub 提交历史页面）

## 🛠️ 安装后推荐
### 🔧 Xposed 模块

| 模块 | 说明 |
|:---:|:---|
| **FuseFixer** | [Unicode零宽修复模块](https://github.com/5ec1cff/FuseFixer) |

## 🙏 致谢

- [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS) / [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS)
- [SukiSU](https://sukisu.org/) / [BakaSU](https://bakasu.org/) / [FinaSU](https://github.com/LyraVoid/FinaSU)
- [SUSFS](https://gitlab.com/simonpunk/susfs4ksu)

<div align="center">

## ⚠️ 免责声明

</div>

- 刷入内核不会使保修失效，但总有设备变砖的风险请务必:
- 💾 备份你的数据
- 🧠 在继续之前，了解风险

- 请务必提前备份该系统的原Boot镜像。

- 如果刷入 AnyKernel3 导致设备进入无限启动循环或无法启动，请进入 BootLoader 并重新刷入原Boot镜像。

- 我不对刷写该内核所引发的任何问题负责。

<div align="center">
  
# **🚨  请自行承担风险！**

</div>
