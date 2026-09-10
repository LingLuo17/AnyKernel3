<div align="center">

# GKI KernelSU SUSFS

**Automated GKI Kernel Builds | KernelSU / KernelSU-Next / SukiSU / ReSukiSU + SUSFS Integration**

[![Release](https://img.shields.io/github/v/release/LingLuo17/AnyKernel3?label=Release&style=flat-square&logo=github&logoColor=white&color=2ea44f)](https://github.com/LingLuo17/AnyKernel3/releases)
[![Coolapk](https://img.shields.io/badge/Follow-Coolapk-3DDC84?style=flat-square&logo=android&logoColor=white)](http://www.coolapk.com/u/38407386)
[<img src="https://img.shields.io/badge/Join-QQ%20Group-blue?style=flat-square&logo=github&logoColor=white">](https://qm.qq.com/q/PZIFvlcbqU)
[![KernelSU](https://img.shields.io/badge/KernelSU-Supported-5AA300?style=flat-square)](https://kernelsu.org/)
[![KernelSU Next](https://img.shields.io/badge/KernelSU--Next-Supported-5AA300?style=flat-square)](https://kernelsu-next.github.io/webpage/)
[![SukiSU](https://img.shields.io/badge/SukiSU-Supported-5AA300?style=flat-square)](https://sukisu.org/)
[![ReSukiSU](https://img.shields.io/badge/ReSukiSU-Supported-5AA300?style=flat-square)](https://resukisu.github.io/)
[![SUSFS](https://img.shields.io/badge/SUSFS-Integrated-E67E22?style=flat-square)](https://gitlab.com/simonpunk/susfs4ksu)

**English** | [简体中文](#chinese)

</div>

## 📖 Introduction

Built upon [AnyKernel3](https://github.com/osm0sis/AnyKernel3), this repository uses GitHub Actions to automatically compile Android GKI kernels. It integrates multiple KernelSU variants and SUSFS kernel-level spoofing solutions, with additional practical patches including ZRAM and BBG.

- The build workflows are adapted from [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS) and [Wild Kernels](https://github.com/WildKernels/GKI_KernelSU_SUSFS)
- Flashing rule: ***It can be flashed as long as the kernel version matches.***

## 📦 Supported Kernel Versions

| Android | Kernel Version | Manual Workflow |
|:---:|:---:|:---:|
| 12 | 5.10 | `kernel-a12-5-10.yml` |
| 13 | 5.15 | `kernel-a13-5-15.yml` |
| 14 | 6.1 | `kernel-a14-6-1.yml` |
| 15 | 6.6 | `kernel-a15-6-6.yml` |
| 16 | 6.12 | `kernel-a16-6-12.yml` |
| Custom | Any | `kernel-custom.yml` |

## ✨ Features

| Feature | Description |
|:---|:---|
| 🔐 KernelSU Variants | Supports Official / Next / SukiSU / ReSukiSU variants, selectable at build time |
| 🙈 SUSFS | Kernel-level hiding working with KSU to complete environment spoofing |
| 💾 ZRAM LZ4 | ZRAM compression algorithm enhancement patch stack |
| 🛡️ BBG antiwipe | BBG anti-brick patch to reduce partition corruption risk |
| ⚡ KPM | Optional KPM feature / build-time patching |
| 🔔 Re-Kernel | Optional Re-Kernel driver integration |
| 🩹 CVE-2026-43499 | Optional automatic application of the rtmutex fix |
| 📱 OnePlus Snapdragon 8 Elite | Optional support for OnePlus devices with Snapdragon Elite processors |
| 🐳 Droidspaces | Optional container support with NTSync kernel compatibility patch |

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

## 🚀 Usage

1. **Fork this repository** (or use it directly)
2. Go to the **Actions** page and pick the workflow for your kernel version
3. Click **Run workflow** and fill in the parameters as needed:
   - `android_version` / `kernel_version` / `sub_level` / `os_patch_level` (kernel version quadruplet)
   - `ksu_variant`: KernelSU variant (Official / Next / SukiSU / ReSukiSU)
   - Feature switches: `enable_susfs`, `use_zram`, `use_bbg`, `use_kpm`, etc.
4. [security patch level](https://zzh20188.github.io/GKI_KernelSU_SUSFS/index.html)
5. Once the build finishes, download the **Artifacts** from the run page:
   - `AnyKernel3.zip` — flashable zip (recommended; flash via custom Recovery or KSU)
   - `boot.img` / `boot-gz.img` / `boot-lz4.img` — boot images for each compression format

> 💡 Artifacts are uploaded as Actions Artifacts by default and are not auto-published as Releases. Failed runs additionally upload build logs (`Build-Logs`) and patch conflict records (`Rejects`) for troubleshooting.

## 🛠️ Recommended After Installation
### 🔧 Xposed Modules
| Module | Description |
|:---:|:---|
| **FuseFixer** | [Unicode zero-width character fix module](https://github.com/5ec1cff/FuseFixer) |

## 🙏 Acknowledgments

- [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS) / [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS)
- [KernelSU](https://kernelsu.org/) / [KernelSU-Next](https://kernelsu-next.github.io/webpage/) / [SukiSU](https://sukisu.org/) / [ReSukiSU](https://resukisu.github.io/)
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

**自动化构建 GKI 内核 | 集成 KernelSU/KernelSU-Next/SukiSU/ReSukiSU + SUSFS**

[English](#gki-kernelsu-susfs) | **简体中文**

</div>

## 📖 简介

本仓库基于 [AnyKernel3](https://github.com/osm0sis/AnyKernel3) 构建，通过 GitHub Actions 自动编译 **Android GKI 内核**，集成多种 KernelSU 变体与 SUSFS 内核级隐藏方案，并附加 ZRAM、BBG等实用补丁。

- 构建工作流修改自 [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS) 与 [Wild Kernels](https://github.com/WildKernels/GKI_KernelSU_SUSFS)
- 刷入规则：***只要内核版本匹配即可刷入***

## 📦 支持的内核版本

| Android | 内核版本 | 手动触发工作流 |
|:---:|:---:|:---:|
| 12 | 5.10 | `kernel-a12-5-10.yml` |
| 13 | 5.15 | `kernel-a13-5-15.yml` |
| 14 | 6.1 | `kernel-a14-6-1.yml` |
| 15 | 6.6 | `kernel-a15-6-6.yml` |
| 16 | 6.12 | `kernel-a16-6-12.yml` |
| 自定义 | 任意 | `kernel-custom.yml` |

## ✨ 功能特性

| 特性 | 说明 |
|:---|:---|
| 🔐 KernelSU 全家桶 | 支持 Official / Next / SukiSU / ReSukiSU 四种变体，构建时按需选择 |
| 🙈 SUSFS | 内核级隐藏，配合 KSU 完成环境伪装 |
| 💾 ZRAM LZ4 | ZRAM 压缩算法增强补丁栈 |
| 🛡️ BBG 防格机 | 添加 BBG 防格机补丁，降低分区损坏风险 |
| ⚡ KPM | 可选开启 KPM 功能 / 构建期修补 |
| 🔔 Re-Kernel | 可选集成 Re-Kernel 驱动 |
| 🩹 CVE-2026-43499 | 可选自动应用 rtmutex 修复补丁 |
| 📱 一加 骁龙Elite 支持 | 可选添加一加 骁龙Elite 处理器支持 |
| 🐳 Droidspaces | 可选容器支持及 NTSync 内核兼容补丁 |

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

## 🚀 使用方法

1. **Fork 本仓库**（或直接使用本仓库）
2. 进入 **Actions** 页面，选择对应内核版本的工作流
3. 点击 **Run workflow**，按需填写参数：
   - `android_version` / `kernel_version` / `sub_level` / `os_patch_level`（内核版本四件套）
   - `ksu_variant`：KernelSU 变体（Official / Next / SukiSU / ReSukiSU）
   - 功能开关：`enable_susfs`、`use_zram`、`use_bbg`、`use_kpm` 等 
4. [安全补丁级别](https://zzh20188.github.io/GKI_KernelSU_SUSFS/index.html)
5. 构建完成后，在本次运行页面下载 **Artifacts**：
   - `AnyKernel3.zip` —— 卡刷包（推荐，配合自定义 Recovery 或 KSU 刷入）
   - `boot.img` / `boot-gz.img` / `boot-lz4.img` —— 对应压缩格式的 boot 镜像

> 💡 产物默认上传为 Actions Artifacts，不自动发布 Release；失败时会额外上传构建日志（`Build-Logs`）与补丁冲突记录（`Rejects`）供排查。

## 🛠️ 安装后推荐
### 🔧 Xposed 模块

| 模块 | 说明 |
|:---:|:---|
| **FuseFixer** | [Unicode零宽修复模块](https://github.com/5ec1cff/FuseFixer) |

## 🙏 致谢

- [osm0sis/AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS) / [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS)
- [KernelSU](https://kernelsu.org/) / [KernelSU-Next](https://kernelsu-next.github.io/webpage/) / [SukiSU](https://sukisu.org/) / [ReSukiSU](https://resukisu.github.io/)
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
