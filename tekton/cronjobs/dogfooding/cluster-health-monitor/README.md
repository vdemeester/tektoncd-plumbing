# Cluster Health Monitor

A Tekton Task that monitors the health of CronJobs, Jobs, PipelineRuns, and
TaskRuns in the dogfooding cluster. It runs as a CronJob that directly creates
a TaskRun (no EventListener needed), making it independent of the trigger
infrastructure it monitors.

## What it checks

1. **CronJobs**: Detects cronjobs that haven't run successfully in longer than
   2x their schedule interval
2. **Jobs**: Detects jobs stuck in `ImagePullBackOff` or other error states,
   and jobs that have been active longer than a threshold
3. **PipelineRuns/TaskRuns**: Detects recent failures across all namespaces,
   grouped by type (e.g. `TaskRunImagePullFailed`, `Failed`)

## How it alerts

When issues are detected, the task creates a GitHub issue in
`tektoncd/plumbing` with structured labels (`area/infra`, `kind/monitoring`)
and a detailed report of all failures found.

## Architecture

```
CronJob (daily at 06:00 UTC)
  └── creates Job
       └── creates TaskRun (via kubectl)
            └── runs cluster-health-monitor Task
                 ├── step 1: check-cronjobs-and-jobs
                 └── step 2: check-pipelineruns-taskruns
                 └── step 3: report (creates GitHub issue if failures found)
```

The CronJob creates the TaskRun directly using `kubectl`, avoiding dependency
on EventListeners/TriggerTemplates. This means the monitor works even when the
trigger infrastructure is broken.

## RBAC

The `tekton-monitor` ServiceAccount needs:
- `get`, `list` on `cronjobs`, `jobs`, `pods` in `default` namespace
- `get`, `list` on `pipelineruns`, `taskruns` across monitored namespaces
- `create` on `taskruns` in `default` namespace (for the CronJob to create the TaskRun)
