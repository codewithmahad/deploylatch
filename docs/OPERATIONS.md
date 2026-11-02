# DeployLatch — Ubuntu setup and demonstration

This guide reproduces the local test setup: build Java JARs on Windows, copy them to an Ubuntu VM, configure the systemd service, and test deployment and rollback.

It assumes you own the VM and have sudo access. DeployLatch is a course project, not a production installation tool.

## 1. Requirements

- Windows with PowerShell, Git, JDK 25 (including `javac` and `jar`), and the OpenSSH `scp` client
- Ubuntu VM with Java 25, Bash, curl, flock (from util-linux), systemd, and SSH access
- Both machines able to communicate over the local VMware network

On Ubuntu, install missing tools if needed:

```bash
sudo apt update
sudo apt install openjdk-25-jre-headless curl util-linux openssh-server
sudo systemctl enable --now ssh
```

Find Ubuntu's IP address with `ip -4 -br address`.

## 2. Build the demo applications on Windows

Open PowerShell in the repository root:

```powershell
.\scripts\build-demo.ps1
```

This produces three executable JARs under `demo-app/dist/`:

| Release | /health | /version |
| --- | --- | --- |
| v1 | HTTP 200, OK | v1 |
| v2 | HTTP 200, OK | v2 |
| v3 | HTTP 503, UNHEALTHY | v3 |

v3 intentionally fails the health check to demonstrate rollback.

## 3. Copy the files to Ubuntu

On Ubuntu, prepare a writable staging directory:

```bash
mkdir -p ~/deploylatch-staging
```

Back in Windows PowerShell, replace `VM_IP` with the VM's actual IP address and `mahad` with your Ubuntu login if different:

```powershell
scp .\demo-app\dist\demo-app-v1.jar .\demo-app\dist\demo-app-v2.jar .\demo-app\dist\demo-app-v3.jar .\systemd\deploylatch-demo.service .\scripts\deploylatch.sh mahad@VM_IP:~/deploylatch-staging/
```

Confirm that the five files arrived:

```bash
ls -lh ~/deploylatch-staging/
```

## 4. Install the initial release and service

On Ubuntu, stop any manually started demo app on port 8080 before enabling the service.

Verify the Java executable is available at `/usr/bin/java`:

```bash
command -v java
```

Then run:

```bash
id deploylatch >/dev/null 2>&1 || sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin deploylatch

sudo install -d -m 0755 /opt/deploylatch/releases/v1
sudo install -m 0644 ~/deploylatch-staging/demo-app-v1.jar /opt/deploylatch/releases/v1/app.jar
sudo ln -sfnT releases/v1 /opt/deploylatch/current

sudo install -m 0644 ~/deploylatch-staging/deploylatch-demo.service /etc/systemd/system/deploylatch-demo.service
sudo systemctl daemon-reload
sudo systemctl enable --now deploylatch-demo.service
```

The Java service uses a dedicated non-root Linux account. Its executable JAR is reached through `/opt/deploylatch/current/app.jar`.

Verify:

```bash
systemctl is-active deploylatch-demo.service
curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1:8080/version
```

Expected outputs: `active`, `OK`, and `v1`.

## 5. Deploy a healthy release

```bash
sudo bash ~/deploylatch-staging/deploylatch.sh deploy ~/deploylatch-staging/demo-app-v2.jar v2
```

Expected:

```text
Deploying v2
Deployment successful: v2
```

## 6. Demonstrate automatic rollback

```bash
sudo bash ~/deploylatch-staging/deploylatch.sh deploy ~/deploylatch-staging/demo-app-v3.jar v3
```

The command exits with a failure status **on purpose** because v3 is unhealthy. The tool should restore v2:

```text
Deploying v3
Deployment failed: v3
Restored v2
```

Check the running state and deployment log:

```bash
sudo bash ~/deploylatch-staging/deploylatch.sh status
sudo bash ~/deploylatch-staging/deploylatch.sh history
```

Expected state:

```text
Current: v2
Previous: v1
Service: active
Health: OK
```

## 7. Other commands and troubleshooting

Manual rollback to the previous release:

```bash
sudo bash ~/deploylatch-staging/deploylatch.sh rollback
```

After the demonstration above, this restores v1 and makes v2 the new manual rollback target.

Inspect the service and its logs:

```bash
systemctl status deploylatch-demo.service --no-pager
journalctl -u deploylatch-demo.service -n 40 --no-pager
```

Available CLI actions: `deploy`, `rollback`, `status`, `history`, and `help`.

Deployment actions, status, and history require sudo and take the same exclusive lock. `history` shows the last 20 records from `/var/log/deploylatch/deployments.log`; timestamps are UTC. Java process output is available through `journalctl`.

Each deployment requires a new release ID. Failed release directories remain under `/opt/deploylatch/releases/` for inspection; deploying another JAR with the same release ID will be refused.

## Limits

The script manages one application on one Ubuntu VM. It causes short service restarts, uses local HTTP checks rather than complete functional tests, and does not include remote orchestration, containers, or zero-downtime deployment. These commands are intended for the local course environment.
