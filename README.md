# DeployLatch

A Linux-based application deployment and rollback project developed for the Operating Systems course at the University of Karachi (UBIT).

## Overview

DeployLatch is a Bash-based tool intended to automate application deployment on Linux. It will handle application updates, check whether a deployment is successful, and restore the previous working version when an update fails.

The initial implementation will use a small Java HTTP application running as a service on Ubuntu Linux.

## Planned Features

- Deploy and update a Java application.
- Manage the application using systemd.
- Verify deployments through HTTP health checks.
- Restore the previous version after a failed deployment.
- Record deployment activity and errors.

## Technologies

- **Linux (Ubuntu):** Deployment and testing environment.
- **Bash:** Deployment and rollback automation.
- **Java:** Demonstration HTTP application.
- **systemd:** Application service management.
- **curl:** HTTP health checks.
- **Git & GitHub:** Version control and team collaboration.

## Project Scope

The project will be developed and tested using Ubuntu running in VMware. It focuses on a single Java application, with no cloud infrastructure or remote server required.

## Team

| Member | Responsibility |
|---|---|
| Shaikh Mahad Ud Din | Architecture, coordination and integration |
| Muhammad Wasiq | Bash deployment automation |
| Muhammad Shayan | Linux environment and service management |
| Muhammad Ali | Java application development |
| Adeel Ali | Health checks, rollback and testing |

## Status

Initial development. The application and deployment automation have not yet been implemented.

---

**Course:** Operating Systems (SE-458)  
**Department:** Department of Computer Science (UBIT), University of Karachi