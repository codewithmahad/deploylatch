<p align="center">
  <picture>
    <source media="(max-width: 600px)" srcset="docs/assets/deploylatch-banner-mobile.svg">
    <img src="docs/assets/deploylatch-banner.svg" alt="DeployLatch — Linux, Bash, and Java" width="100%">
  </picture>
</p>

<p align="center">
  A small Linux deployment and rollback tool built with Bash, systemd, and Java.
</p>

<p align="center">
  <sub>Operating Systems · UBIT, University of Karachi · Tested on Ubuntu in VMware</sub>
</p>

<p align="center">
  <a href="#what-it-does">What it does</a> &nbsp;·&nbsp;
  <a href="#how-it-works">Workflow</a> &nbsp;·&nbsp;
  <a href="#demo-result">Demo result</a> &nbsp;·&nbsp;
  <a href="#run-it">Run it</a> &nbsp;·&nbsp;
  <a href="#lets-connect">Connect</a>
</p>

<img src="docs/assets/linux-tux.png" alt="Tux, the Linux mascot" align="right" width="144">

## Why I built this

DeployLatch started as an Operating Systems course project at UBIT, University of Karachi. I wanted to use Linux and Bash for something related to the Java backend development I was learning.

The idea is simple: when a new version of an application is installed, it needs to start successfully and respond correctly. If it fails, the previous working version should still be available.

This project puts those steps together on one local Ubuntu virtual machine.

<br clear="right">

## What it does

- Installs versioned Java JAR releases under `/opt/deploylatch/releases/`.
- Uses a `current` symbolic link to select the active release.
- Starts and restarts the application through a `systemd` service running as a dedicated user.
- Checks the application's HTTP health and version endpoints using `curl`.
- Restores the previous release automatically if a deployment fails its health check.
- Supports manual rollback, service status, and timestamped deployment history.
- Uses a file lock to prevent two deployments from running at the same time.

The application is intentionally small. DeployLatch handles **one Java service on one Ubuntu VM**; it is not a cloud deployment platform.

## How it works

<p align="center">
  <picture>
    <source media="(max-width: 600px)" srcset="docs/assets/deployment-flow-mobile.svg">
    <img src="docs/assets/deployment-flow.svg" alt="Save a new release, restart the service, check health, and keep or roll back the release" width="100%">
  </picture>
</p>

1. Save the incoming JAR in a new release directory.
2. Point `current` to that release and restart the systemd service.
3. Request `/health` and `/version`, checking both the response and expected release ID.
4. Keep a passing release. If the check fails, restore the old release, restart the service, and check it again.
5. Record the outcome in the deployment history.

## Demo result

I tested the deployment and recovery flow on **Ubuntu 26.04.1 LTS running in VMware**.

```text
Deploying v2
Deployment successful: v2

Deploying v3
Deployment failed: v3
Restored v2

Current: v2
Previous: v1
Service: active
Health: OK
```

The build includes three demonstration releases: **v1** and **v2** respond as healthy applications; **v3** deliberately responds with HTTP 503 so the rollback can be tested. The log recorded a successful v2 deployment followed by a rollback from v3 to v2.

<img src="docs/assets/java-sticker.svg" alt="Java" align="right" width="124">

## Inside the project

The Java demo uses the JDK's built-in HTTP server, with no external framework. It listens on `127.0.0.1:8080` and provides two endpoints:

- `GET /health` — returns `200 OK` for a healthy release or `503` for the deliberately unhealthy release.
- `GET /version` — identifies the running release (`v1`, `v2`, or `v3`).

Bash handles deployment control flow and recovery. systemd manages the application process. The PowerShell build script compiles the Java source and packages the three demo JARs.

<br clear="right">

### Project files

```text
deploylatch/
├── demo-app/
│   └── src/main/java/dev/deploylatch/demo/DemoServer.java
├── scripts/
│   ├── build-demo.ps1
│   └── deploylatch.sh
├── systemd/
│   └── deploylatch-demo.service
├── docs/
│   ├── OPERATIONS.md
│   └── assets/
├── .gitattributes
├── .gitignore
└── README.md
```

Build artifacts are generated locally in `demo-app/dist/` and aren't committed to the repository.

## Run it

**Requirements:** Windows with JDK 25 and PowerShell to build the demo; Ubuntu with Java 25, Bash, curl, and systemd to run it.

Build the demonstration JARs from the repository root on Windows:

```powershell
.\scripts\build-demo.ps1
```

After completing the Ubuntu setup and copying the files, deploy a new release:

```bash
sudo bash ~/deploylatch-staging/deploylatch.sh deploy ~/deploylatch-staging/demo-app-v2.jar v2
```

To demonstrate failure recovery, deploy the intentionally unhealthy v3 release:

```bash
sudo bash ~/deploylatch-staging/deploylatch.sh deploy ~/deploylatch-staging/demo-app-v3.jar v3
```

That command is expected to fail while restoring v2. Check the state and log:

```bash
sudo bash ~/deploylatch-staging/deploylatch.sh status
sudo bash ~/deploylatch-staging/deploylatch.sh history
```

**Full setup, file-transfer commands, and troubleshooting:** [Ubuntu operations guide](docs/OPERATIONS.md).

## Tools and environment

| Tool | Used for |
| :--- | :--- |
| <img src="docs/assets/tech/linux-original.svg" width="20" height="20" alt=""> Ubuntu / Linux | Files, permissions, processes, release paths |
| <img src="docs/assets/tech/bash-original.svg" width="20" height="20" alt=""> Bash | Deployment, verification, recovery |
| <img src="docs/assets/tech/java-original.svg" width="20" height="20" alt=""> Java 25 | Demo HTTP service and JAR files |
| systemd | Service lifecycle and restart behavior |
| curl | Local HTTP health checks |
| VMware | Local Ubuntu development VM |
| <img src="docs/assets/tech/github-original.svg" width="20" height="20" alt=""> Git / GitHub | Source history and changes |

## Scope and limitations

This is an educational deployment tool, not a production-ready deployment system. It handles a single local Java application, uses service restarts that cause brief downtime, and checks HTTP health rather than full application correctness. It does not provide remote deployment, Docker/Kubernetes integration, or multi-application orchestration.

## Course context

**Operating Systems (SE-458)** · Department of Computer Science (UBIT), University of Karachi.

This was a five-member course project. I led the project and worked on the implementation, integration, and Ubuntu demonstration. It gave me hands-on experience with Linux services, permissions, release directories, exit codes, shell automation, and failure recovery.

## Let's connect

I'm **Shaikh Mahad Ud Din**, [@codewithmahad](https://github.com/codewithmahad). I'm learning Java backend development and sharing the projects I build along the way.

<p>
  <a href="https://github.com/codewithmahad"><img src="docs/assets/follow-github.svg" alt="Follow on GitHub" height="38"></a>
  <a href="https://www.linkedin.com/in/codewithmahad/"><img src="docs/assets/linkedin.svg" alt="Connect on LinkedIn" height="38"></a>
  <a href="https://shaikhmahad.vercel.app/"><img src="docs/assets/portfolio.svg" alt="Visit my portfolio" height="38"></a>
  <a href="mailto:codewithmahad@gmail.com"><img src="docs/assets/email.svg" alt="Send me an email" height="38"></a>
</p>
