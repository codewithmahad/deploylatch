<p align="center">
  <picture>
    <source media="(max-width: 600px)" srcset="docs/assets/deploylatch-banner-mobile.svg">
    <img src="docs/assets/deploylatch-banner.svg" alt="DeployLatch — Linux deployments, with a rollback plan." width="100%">
  </picture>
</p>

<p align="center">
  A Bash tool for deploying a Java service on Linux and recovering from failed updates.<br>
  <sub>Operating Systems course project · UBIT, University of Karachi</sub>
</p>

<p align="center">
  <a href="#how-it-works">Workflow</a> &nbsp;·&nbsp;
  <a href="#the-demonstration">Demo</a> &nbsp;·&nbsp;
  <a href="#run-it">Run it</a> &nbsp;·&nbsp;
  <a href="#project-notes">Project notes</a>
</p>

<img src="docs/assets/linux-tux.png" alt="Tux, the Linux mascot" align="right" width="144">

## Why I built this

I built DeployLatch for my Operating Systems course to use the Linux and Bash skills from the lab alongside Java backend development. I wanted to work through how an application starts as a service, how an update is checked, and how to recover when something goes wrong.

The result is a small deployment tool for **one Java service on one Ubuntu VM**. It brings together shell scripting, Linux services, permissions, HTTP checks, and release management.

<br clear="right">

## How it works

Each JAR gets its own release directory. A `current` symbolic link selects the running release; `previous` identifies the manual rollback target. systemd runs the application under a dedicated, non-root account.

<p align="center">
  <picture>
    <source media="(max-width: 600px)" srcset="docs/assets/deployment-flow-mobile.svg">
    <img src="docs/assets/deployment-flow.svg" alt="Install a versioned JAR, switch the active release, restart the service, and check health and release ID. Restore and verify the old release if deployment fails." width="100%">
  </picture>
</p>

The script accepts an update only when `/health` returns `OK` and `/version` matches the requested release ID. If startup or verification fails, it switches back to the old release, restarts it, and checks recovery. A file lock prevents concurrent deployments; outcomes are recorded with UTC timestamps.

## The demonstration

The course demonstration ran on **Ubuntu 26.04.1 LTS in VMware**. Starting from v1, v2 deploys successfully. v3 deliberately returns HTTP 503, triggering a rollback to v2.

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

The v3 deployment command returns a non-zero exit status even after successful recovery: the requested update failed, while the old service was restored.

## Run it

The demonstrated setup builds the JARs on **Windows with PowerShell and JDK 25**, then runs them on **Ubuntu with Java 25, Bash, curl, flock, and systemd**. SSH/SCP transfers the files to the VM.

<details>
<summary><strong>Build and run the course demo</strong></summary>

In Windows PowerShell:

```powershell
git clone https://github.com/codewithmahad/deploylatch.git
cd deploylatch
.\scripts\build-demo.ps1
```

The build creates `demo-app-v1.jar`, `demo-app-v2.jar`, and `demo-app-v3.jar` in `demo-app/dist/`. v1 and v2 are healthy; v3 is intentionally unhealthy.

Next, follow the [Ubuntu setup guide](docs/OPERATIONS.md) to transfer the files, install v1, create the service account, and enable the systemd service. The commands below assume that setup is complete.

On Ubuntu, deploy v2, then try the failing v3 release:

```bash
sudo bash ~/deploylatch-staging/deploylatch.sh deploy \
  ~/deploylatch-staging/demo-app-v2.jar v2

sudo bash ~/deploylatch-staging/deploylatch.sh deploy \
  ~/deploylatch-staging/demo-app-v3.jar v3
```

After v3 fails and restores v2, inspect the result:

```bash
sudo bash ~/deploylatch-staging/deploylatch.sh status
sudo bash ~/deploylatch-staging/deploylatch.sh history
```

Each deployment needs a unique release ID. Existing release directories, including failed ones, are retained, so rerunning the same release ID is refused.

</details>

The [operations guide](docs/OPERATIONS.md) contains the complete setup, file-transfer commands, manual rollback, and troubleshooting.

<img src="docs/assets/java-sticker.svg" alt="Java" align="right" width="132">

## Inside the project

The Java app uses the JDK's built-in HTTP server. A `release.properties` file packaged into each JAR supplies its version and health behavior, so the same source produces all three demo releases.

It listens on `127.0.0.1:8080`. `GET /health` returns HTTP 200 with `OK` for v1/v2, or HTTP 503 with `UNHEALTHY` for v3. `GET /version` returns the release ID. Requests must come from inside the VM. Unknown paths return `404`; other methods on these endpoints return `405`.

Bash owns the deployment and recovery steps. systemd owns the Java process. Keeping the application small leaves the OS behavior easy to follow.

<br clear="right">

## Project notes

<details>
<summary><strong>Project structure and entry points</strong></summary>

```text
deploylatch/
├── scripts/
│   ├── build-demo.ps1             # Build the three demo JARs on Windows
│   └── deploylatch.sh             # Deploy, verify, recover, inspect history
├── systemd/
│   └── deploylatch-demo.service   # Run the Java process as deploylatch
├── demo-app/src/main/java/dev/deploylatch/demo/
│   └── DemoServer.java            # Health and version endpoints
├── docs/
│   ├── OPERATIONS.md              # Ubuntu setup and demonstration
│   └── assets/                    # README artwork and source notices
├── .gitattributes
├── .gitignore
└── README.md
```

Start with [the Bash script](scripts/deploylatch.sh), [the service unit](systemd/deploylatch-demo.service), or [the Java application](demo-app/src/main/java/dev/deploylatch/demo/DemoServer.java). Generated JARs and classes are excluded from Git.

</details>

<details>
<summary><strong>Commands, release paths, and logs</strong></summary>

All actions below run on Ubuntu using `sudo bash ~/deploylatch-staging/deploylatch.sh` followed by:

| Action | Result |
| :--- | :--- |
| `deploy JAR RELEASE_ID` | Install and verify a new release; recover on failure |
| `rollback` | Switch to `previous`; on success, make the replaced release the new rollback target |
| `status` | Show current/previous release, service state, and HTTP health |
| `history` | Show the last 20 deployment records |
| `help` | Print command usage; sudo is not required for help |

| Path | Purpose |
| :--- | :--- |
| `/opt/deploylatch/releases/<id>/app.jar` | Stored release |
| `/opt/deploylatch/current` | Active release link |
| `/opt/deploylatch/previous` | Manual rollback target |
| `/opt/deploylatch/.deploy.lock` | Deployment lock |
| `/var/log/deploylatch/deployments.log` | Timestamped deployment outcomes |

For Java startup errors or process output:

```bash
journalctl -u deploylatch-demo.service -n 40 --no-pager
```

</details>

<details>
<summary><strong>Verification and failure behavior</strong></summary>

Verification makes up to **8 attempts**, with a **2-second timeout per HTTP request** and a **1-second pause after each unsuccessful attempt**. Both the health body and expected version must match. These are fixed values in the script.

| Situation | Script behavior |
| :--- | :--- |
| Unreadable JAR, invalid ID, or existing release ID | Refuse the deployment before switching the active release |
| Another command holds the deployment lock | Exit instead of running concurrently |
| New service fails to start or pass verification | Restore the old release and verify it |
| No valid old release exists | Stop the service, remove `current`, and record `FAILED` |
| Automatic recovery also fails | Record `ROLLBACK_FAILED` and report failure |
| Manual rollback target fails | Restore the original active link, attempt a restart, and report failure |

A successful update records `SUCCESS`; successful automatic recovery records `ROLLED_BACK`; a successful manual rollback records `MANUAL_ROLLBACK`. Failed deployments keep a non-zero exit status.

</details>

<details>
<summary><strong>Design choices and boundaries</strong></summary>

- **Separate release directories:** retain old JARs rather than overwrite the running artifact.
- **Atomic link replacement:** prepare a temporary symlink, then rename it over `current`. This makes the pointer change atomic, not the whole deployment.
- **Version-aware verification:** a healthy response alone does not prove the requested release is running.
- **Dedicated service user:** deployment commands use sudo; the Java process runs as `deploylatch`, with `NoNewPrivileges=true`.
- **Local HTTP service:** loopback binding keeps the demonstration inside the VM.

Service restarts cause brief downtime. HTTP checks cover availability and release identity, not complete application correctness. The tool targets one local service, retains releases without automatic cleanup, and does not guarantee recovery from an interrupted deployment or a machine failure. Deployment paths, port, and retry settings are fixed in the source.

</details>

<details>
<summary><strong>Tools and environment</strong></summary>

| Tool | Role |
| :--- | :--- |
| <img src="docs/assets/tech/linux-original.svg" width="20" height="20" alt=""> Ubuntu / Linux | Processes, files, permissions, and release paths |
| <img src="docs/assets/tech/bash-original.svg" width="20" height="20" alt=""> Bash | Deployment control flow, verification, and recovery |
| <img src="docs/assets/tech/java-original.svg" width="20" height="20" alt=""> Java 25 | Demo HTTP service and JAR packaging |
| systemd | Service lifecycle and process logs |
| curl | Local HTTP requests |
| flock | Exclusive deployment lock |
| PowerShell | Windows build script |
| VMware | Ubuntu virtual machine |
| <img src="docs/assets/tech/github-original.svg" width="20" height="20" alt=""> Git / GitHub | Source history |

</details>

<details>
<summary><strong>Course context and learning</strong></summary>

<img src="docs/assets/ubit-emblem.png" alt="Department of Computer Science, UBIT, University of Karachi" align="right" width="120">

<p><strong>Operating Systems · SE-458</strong><br>
Department of Computer Science, UBIT, University of Karachi.</p>

Built for my fourth-semester Operating Systems course in **2026**. I handled the implementation, integration, and Ubuntu demonstration.

The project gave the lab concepts a practical purpose: file permissions protect the releases, symlinks select the active version, exit codes report failures, locking prevents overlapping commands, and systemd manages the process. The Java work connects HTTP responses and JAR packaging to those Linux operations.

<br clear="right">

</details>

## Let's connect

I'm **Shaikh Mahad Ud Din**, [@codewithmahad](https://github.com/codewithmahad). I build Java backend projects and share what I learn. Working with Java or Linux, or have a project you'd like to build together? I'd be glad to connect.

<p>
  <a href="https://github.com/codewithmahad"><img src="docs/assets/follow-github.svg" alt="Follow on GitHub" height="38"></a>
  <a href="https://www.linkedin.com/in/codewithmahad/"><img src="docs/assets/linkedin.svg" alt="Connect on LinkedIn" height="38"></a>
  <a href="https://shaikhmahad.vercel.app/"><img src="docs/assets/portfolio.svg" alt="Visit my portfolio" height="38"></a>
  <a href="mailto:codewithmahad@gmail.com"><img src="docs/assets/email.svg" alt="Send me an email" height="38"></a>
</p>
