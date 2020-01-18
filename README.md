# Intro

Support for `helmfile` with `argo-cd`.

`argo-cd` already supports `helm` in 2 distinct ways, why is this useful?

- It helps decouple configuration from chart development
- It's similar to using a repo type of `helm` but you can still manage
  configuration with git.
- Because I like the power afforded using `helmfile`'s features such as
  `environments`, `selectors`, templates, and being able to use `ENV` vars as
  conditionals **AND** values.
- https://github.com/roboll/helmfile/blob/master/docs/writing-helmfile.md
- https://github.com/roboll/helmfile/blob/master/docs/shared-configuration-across-teams.md

# Installation

```
    configManagementPlugins: |
      - name: helmfile
        init:                          # Optional command to initialize application source directory
          command: ["argo-cd-helmfile.sh"]
          args: ["init"]
        generate:                      # Command to generate manifests YAML
          command: ["argo-cd-helmfile.sh"]
          args: ["generate"]

```

```
  volumes:
  - name: custom-tools
    emptyDir: {}

  initContainers:
  - name: download-tools
    image: alpine:3.8
    command: [sh, -c]
    args:
      - wget -qO /custom-tools/argo-cd-helmfile.sh https://raw.githubusercontent.com/travisghansen/argo-cd-helmfile/master/src/argo-cd-helmfile.sh &&
        chmod +x /custom-tools/argo-cd-helmfile.sh &&
        wget -qO /custom-tools/helmfile https://github.com/roboll/helmfile/releases/download/v0.98.2/helmfile_linux_amd64 &&
        chmod +x /custom-tools/helmfile
    volumeMounts:
      - mountPath: /custom-tools
        name: custom-tools
  volumeMounts:
  - mountPath: /usr/local/bin/argo-cd-helmfile.sh
    name: custom-tools
    subPath: argo-cd-helmfile.sh
  - mountPath: /usr/local/bin/helmfile
    name: custom-tools
    subPath: helmfile
```

# Usage

Configure your `argo-cd` app to use a repo/directory which holds a valid
`helmfile` configuation. This can be a directory which contains a
`helmfile.yaml` file **OR** a `helmfile.d` directory containing any number of
`*.yaml` files. You cannot have both configurations.

There are a number of specially handled `ENV` variables which can be set (all
optional):

- `HELM_BINARY` - custom path to `helm` binary
- `HELM_TEMPLATE_OPTIONS` - pass-through options for the templating operation
  `helm template --help`
- `HELMFILE_BINARY` - custom path to `helmfile` binary
- `HELMFILE_GLOBAL_OPTIONS` - pass-through options for all `helmfile`
  operations `helmfile --help`
- `HELMFILE_TEMPLATE_OPTIONS` - pass-through options for the templating
  operation `helmfile template --help`
- `HELMFILE_HELMFILE` - a complete `helmfile.yaml` content
- `HELMFILE_HELMFILE_STRATEGY` - one of `REPLACE` or `INCLUDE`
  - `REPLACE` - the default option, only the content of `HELMFILE_HELMFILE` is
    rendered, if any valid files exist in the repo they are ignored
  - `INCLUDE` - any valid files in the repo **AND** the content of
    `HELMFILE_HELMFILE` are rendered, precedence is given to
    `HELMFILE_HELMFILE` should the same release name be declared in multiple
    files

Of the above `ENV` variables, the following do variable expansion on the value:

- `HELMFILE_GLOBAL_OPTIONS`
- `HELMFILE_TEMPLATE_OPTIONS`
- `HELM_TEMPLATE_OPTIONS`

Meaning, you can do things like:

- `HELMFILE_GLOBAL_OPTIONS="--environment ${ARGOCD_APP_NAME} --selector cluster=${CLUSTER_ID}`

Any of the standard `Build Environment` variables can be used as well as
variables declared in the application spec.

# Development

```
# format before commit
shfmt -i 2 -ci -w src/helmfile.sh
```
