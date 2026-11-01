# DeployLatch: Ubuntu deployment guide

DeployLatch is a local Ubuntu OS course demonstration. It deploys a Java application, verifies its health and restores the earlier release if the new one fails.

## Build on Windows

Run the PowerShell build script at scripts/build-demo.ps1 from the repository root. It creates three JARs under demo-app/dist:

- demo-app-v1.jar: healthy application
- demo-app-v2.jar: healthy update
- demo-app-v3.jar: intentionally unhealthy (HTTP 503)

## Ubuntu preparation

Install Java 25 and curl. The systemd service assumes that Java is available at /usr/bin/java. Stop any manually running app on port 8080 first.

Prepare the Ubuntu environment:

    id deploylatch >/dev/null 2>&1 || sudo useradd --system --user-group --no-create-home --shell /usr/sbin/nologin deploylatch
    sudo install -d -m 0755 /opt/deploylatch/releases/v1
    sudo install -m 0644 ~/deploylatch-staging/demo-app-v1.jar /opt/deploylatch/releases/v1/app.jar
    sudo ln -sfnT releases/v1 /opt/deploylatch/current
    sudo install -m 0644 ~/deploylatch-staging/deploylatch-demo.service /etc/systemd/system/deploylatch-demo.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now deploylatch-demo.service
    curl -fsS http://127.0.0.1:8080/health
    curl -fsS http://127.0.0.1:8080/version

The last commands should print OK and v1.

## Deploy, verify and recover

Use SCP to transfer the two newer JARs, the Bash script and the service unit into ~/deploylatch-staging/.

    sudo bash ~/deploylatch-staging/deploylatch.sh deploy ~/deploylatch-staging/demo-app-v2.jar v2
    sudo bash ~/deploylatch-staging/deploylatch.sh status
    sudo bash ~/deploylatch-staging/deploylatch.sh deploy ~/deploylatch-staging/demo-app-v3.jar v3
    sudo bash ~/deploylatch-staging/deploylatch.sh status
    sudo bash ~/deploylatch-staging/deploylatch.sh history

The v3 command is expected to exit with an error because /health returns HTTP 503. DeployLatch should restore v2 and leave the Java service healthy.

Manual rollback:

    sudo bash ~/deploylatch-staging/deploylatch.sh rollback

Troubleshooting:

    systemctl status deploylatch-demo.service --no-pager
    journalctl -u deploylatch-demo.service -n 40 --no-pager

## Project limits

One Java service on one local VM. Restarts cause brief downtime. HTTP health checks do not prove complete application correctness. Each deployment requires a new release ID. Failed releases remain for investigation. The Java demo listens only on localhost. Use sudo deployment commands only on your own VM.
