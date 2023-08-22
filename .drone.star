def main(ctx):
    before = test(ctx)

    stages = [
        docker(ctx, "amd64"),
        docker(ctx, "arm64"),
        build(ctx),
    ]

    after = manifest(ctx) + pushrm(ctx)

    for b in before:
        for s in stages:
            s["depends_on"].append(b["name"])

    for s in stages:
        for a in after:
            a["depends_on"].append(s["name"])

    return before + stages + after

def test(ctx):
    return [{
        "kind": "pipeline",
        "type": "docker",
        "name": "test",
        "platform": {
            "os": "linux",
            "arch": "amd64",
        },
        "steps": [
            {
                "name": "deps",
                "image": "docker.io/golang:1.21",
                "commands": [
                    "make deps",
                ],
                "volumes": [
                    {
                        "name": "godeps",
                        "path": "/go",
                    },
                ],
            },
            {
                "name": "generate",
                "image": "docker.io/golang:1.21",
                "commands": [
                    "make generate",
                ],
                "volumes": [
                    {
                        "name": "godeps",
                        "path": "/go",
                    },
                ],
            },
            {
                "name": "lint",
                "image": "docker.io/golang:1.21",
                "commands": [
                    "make lint",
                ],
                "volumes": [
                    {
                        "name": "godeps",
                        "path": "/go",
                    },
                ],
            },
            {
                "name": "test",
                "image": "docker.io/golang:1.21",
                "commands": [
                    "make test",
                ],
                "volumes": [
                    {
                        "name": "godeps",
                        "path": "/go",
                    },
                ],
            },
        ],
        "volumes": [
            {
                "name": "godeps",
                "temp": {},
            },
        ],
        "trigger": {
            "ref": [
                "refs/heads/master",
                "refs/tags/**",
                "refs/pull/**",
            ],
        },
    }]

def build(ctx):
    return {
        "kind": "pipeline",
        "type": "docker",
        "name": "build-binaries",
        "platform": {
            "os": "linux",
            "arch": "amd64",
        },
        "steps": [
            {
                "name": "generate",
                "image": "docker.io/golang:1.21",
                "pull": "always",
                "commands": [
                    "make generate",
                ],
                "volumes": [
                    {
                        "name": "godeps",
                        "path": "/go",
                    },
                ],
            },
            {
                "name": "build",
                "image": "docker.io/techknowlogick/xgo:go-1.21.x",
                "pull": "always",
                "commands": [
                    "ln -s /drone/src /source",
                    "make release",
                ],
                "volumes": [
                    {
                        "name": "godeps",
                        "path": "/go",
                    },
                ],
            },
            {
                "name": "executable",
                "image": "docker.io/golang:1.21",
                "pull": "always",
                "commands": [
                    "$(find dist/ -executable -type f -iname drone-ansible-linux-amd64) --help",
                ],
            },
            {
                "name": "changelog",
                "image": "quay.io/thegeeklab/git-chglog",
                "commands": [
                    "git fetch -tq",
                    "git-chglog --no-color --no-emoji %s" % (ctx.build.ref.replace("refs/tags/", "") if ctx.build.event == "tag" else "--next-tag unreleased unreleased"),
                    "git-chglog --no-color --no-emoji -o CHANGELOG.md %s" % (ctx.build.ref.replace("refs/tags/", "") if ctx.build.event == "tag" else "--next-tag unreleased unreleased"),
                ],
            },
            {
                "name": "publish",
                "image": "docker.io/plugins/github-release",
                "pull": "always",
                "settings": {
                    "api_key": {
                        "from_secret": "github_token",
                    },
                    "files": [
                        "dist/*",
                    ],
                    "note": "CHANGELOG.md",
                    "title": ctx.build.ref.replace("refs/tags/", ""),
                    "overwrite": True,
                },
                "when": {
                    "ref": [
                        "refs/tags/**",
                    ],
                },
            },
        ],
        "volumes": [
            {
                "name": "godeps",
                "temp": {},
            },
        ],
        "depends_on": [
            "test",
        ],
        "trigger": {
            "ref": [
                "refs/heads/master",
                "refs/tags/**",
                "refs/pull/**",
            ],
        },
    }

def docker(ctx, arch):
    return {
        "kind": "pipeline",
        "type": "docker",
        "name": "build-%s" % (arch),
        "platform": {
            "os": "linux",
            "arch": arch,
        },
        "steps": [
            {
                "name": "generate",
                "image": "docker.io/golang:1.21",
                "pull": "always",
                "commands": [
                    "make generate",
                ],
                "volumes": [
                    {
                        "name": "godeps",
                        "path": "/go",
                    },
                ],
            },
            {
                "name": "build",
                "image": "docker.io/golang:1.21",
                "pull": "always",
                "commands": [
                    "make build",
                ],
                "volumes": [
                    {
                        "name": "godeps",
                        "path": "/go",
                    },
                ],
            },
            {
                "name": "dryrun",
                "image": "docker.io/plugins/docker:20",
                "pull": "always",
                "settings": {
                    "dry_run": True,
                    "dockerfile": "docker/Dockerfile.%s" % (arch),
                    "repo": "owncloudci/%s" % (ctx.repo.name),
                    "tags": "latest",
                },
                "when": {
                    "ref": {
                        "include": [
                            "refs/pull/**",
                        ],
                    },
                },
            },
            {
                "name": "docker",
                "image": "docker.io/plugins/docker:20",
                "pull": "always",
                "settings": {
                    "username": {
                        "from_secret": "docker_username",
                    },
                    "password": {
                        "from_secret": "docker_password",
                    },
                    "auto_tag": True,
                    "auto_tag_suffix": "%s" % (arch),
                    "dockerfile": "docker/Dockerfile.%s" % (arch),
                    "repo": "owncloudci/%s" % (ctx.repo.name),
                },
                "when": {
                    "ref": {
                        "exclude": [
                            "refs/pull/**",
                        ],
                    },
                },
            },
        ],
        "volumes": [
            {
                "name": "godeps",
                "temp": {},
            },
        ],
        "depends_on": [
            "test",
        ],
        "trigger": {
            "ref": [
                "refs/heads/master",
                "refs/tags/**",
                "refs/pull/**",
            ],
        },
    }

def manifest(ctx):
    return [{
        "kind": "pipeline",
        "type": "docker",
        "name": "manifest",
        "steps": [
            {
                "name": "manifest",
                "image": "docker.io/plugins/manifest",
                "settings": {
                    "auto_tag": "true",
                    "username": {
                        "from_secret": "docker_username",
                    },
                    "password": {
                        "from_secret": "docker_password",
                    },
                    "spec": "docker/manifest.tmpl",
                    "ignore_missing": "true",
                },
            },
        ],
        "depends_on": [],
        "trigger": {
            "ref": [
                "refs/heads/master",
                "refs/tags/**",
            ],
        },
    }]

def pushrm(ctx):
    return [{
        "kind": "pipeline",
        "type": "docker",
        "name": "pushrm",
        "steps": [
            {
                "name": "pushrm",
                "image": "docker.io/chko/docker-pushrm:1",
                "environment": {
                    "DOCKER_PASS": {
                        "from_secret": "docker_password",
                    },
                    "DOCKER_USER": {
                        "from_secret": "docker_username",
                    },
                    "PUSHRM_FILE": "README.md",
                    "PUSHRM_SHORT": "Drone plugin to provision infrastructure with Ansible",
                    "PUSHRM_TARGET": "owncloudci/%s" % (ctx.repo.name),
                },
            },
        ],
        "depends_on": [
            "manifest",
        ],
        "trigger": {
            "ref": [
                "refs/heads/master",
                "refs/tags/**",
            ],
            "status": ["success"],
        },
    }]
