{
  repoPath,
  nixpkgsPath,
  nixRoot,
  bashRoot,
  coreutilsRoot,
  pythonRoot,
  gitRoot,
  codexRoot,
  ghRoot,
  bwrapRoot,
  batsRoot,
  chezmoiRoot,
  realServices ? false,
}:
let
  nixpkgs = builtins.toPath nixpkgsPath;
  pkgs = import nixpkgs { };
  toStorePath = value: builtins.storePath (toString value);
  cliRoots = map toStorePath [
    nixRoot
    bashRoot
    coreutilsRoot
    pythonRoot
    gitRoot
    codexRoot
    ghRoot
    bwrapRoot
  ];
  testTools = [
    (toStorePath chezmoiRoot)
    pkgs.gnused
    pkgs.ripgrep
    pkgs.findutils
    pkgs.gawk
    pkgs.jq
    pkgs.bun
    pkgs.nodejs_24
    pkgs.uv
  ];
  probeSource = pkgs.runCommand "secret-isolation-probe-source" { } ''
    install -D -m 0444 \
      ${pkgs.writeText "secret-isolation-probe.py" (builtins.readFile "${repoPath}/scripts/secret-isolation-probe.py")} \
      "$out/scripts/secret-isolation-probe.py"
    install -D -m 0444 \
      ${pkgs.writeText "secret-isolation-runtime.py" (builtins.readFile "${repoPath}/tests/fixtures/secret-isolation/runtime.py")} \
      "$out/tests/fixtures/secret-isolation/runtime.py"
    ${pkgs.lib.concatMapStringsSep "\n"
      (name: ''
        install -D -m 0444 ${pkgs.writeText (builtins.baseNameOf name) (builtins.readFile "${repoPath}/${name}")} "$out/${name}"
      '')
      [
        "scripts/secret-isolation-worktree.py"
        "scripts/secret-isolation-gateway.py"
        "private_dot_local/share/codex-isolation/secret-isolation-worktree.py"
        "private_dot_local/share/codex-isolation/secret-isolation-gateway.py"
        "private_dot_local/share/codex-isolation/codex-inner.py"
        "private_dot_local/share/codex-isolation/codex-namespace.py"
        "private_dot_local/share/codex-isolation/github-service.py"
        "private_dot_local/share/codex-isolation/github-client.py"
        "private_dot_local/bin/executable_devshell-env"
        "private_dot_local/bin/executable_codex-worktree"
        "private_dot_local/bin/executable_git-push-topic"
        "private_dot_config/codex/config.toml.tmpl"
        "tests/helpers/raw-codex.bash"
        "tests/devshell-env.bats"
        "tests/raw-codex-integration.bats"
        "tests/raw-codex-services.bats"
        "tests/isolated-github.bats"
        "tests/secret-isolation-gateway.bats"
        "tests/secret-isolation-worktree.bats"
        "tests/fixtures/secret-isolation/worktree-task.py"
        "tests/fixtures/secret-isolation/github-push.py"
      ]
    }
    chmod +x "$out/private_dot_local/bin/"*
  '';
in
pkgs.testers.runNixOSTest {
  name = "secret-isolation-linux-vm-270";
  globalTimeout = (if realServices then 30 else 15) * 60;
  qemu.forceAccel = true;

  nodes.machine =
    { ... }:
    {
      system.stateVersion = "26.05";
      users.users.probe = {
        isNormalUser = true;
        uid = 1000;
      };
      environment.systemPackages = cliRoots;
      nix.package = pkgs.nix;

      # The QEMU guest reads only an image built from this finite closure.
      virtualisation = {
        memorySize = 4096;
        diskSize = 32768;
        useNixStoreImage = true;
        mountHostNixStore = false;
        writableStore = true;
        writableStoreUseTmpfs = false;
        restrictNetwork = !realServices;
        additionalPaths =
          cliRoots
          ++ testTools
          ++ [
            probeSource
            (toStorePath batsRoot)
            pkgs.cacert
          ];
      };

      # Required by the probe's nested `bwrap --unshare-all`.
      security.allowUserNamespaces = true;
      security.unprivilegedUsernsClone = true;
    };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test \"$(uname -s)\" = Linux")
    machine.succeed("test ! -e /home/ubuntu/.codex")
    ${pkgs.lib.optionalString realServices ''
      import os
      # Transfer only the two selected tool-login files after the Nix image is
      # built. Never embed credentials in a derivation, command, log or evidence.
      machine.copy_from_host(os.environ["CODEX_ISOLATION_VM_CODEX_AUTH"], "/home/probe/.codex/auth.json")
      machine.copy_from_host(os.environ["CODEX_ISOLATION_VM_GH_HOSTS"], "/home/probe/.config/gh/hosts.yml")
      machine.succeed("chown -R probe:users /home/probe/.codex /home/probe/.config; chmod 700 /home/probe/.codex /home/probe/.config /home/probe/.config/gh; chmod 600 /home/probe/.codex/auth.json /home/probe/.config/gh/hosts.yml")
      try:
        live_result = machine.execute(
          "su -s ${toStorePath bashRoot}/bin/bash probe -c '"
          "env PATH=${pkgs.lib.makeBinPath (cliRoots ++ testTools)} "
          "TMPDIR=/home/probe CODEX_ISOLATION_REAL_MCP=1 CODEX_ISOLATION_REAL_GITHUB=1 "
          "CODEX_ISOLATION_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt "
          "${toStorePath batsRoot}/bin/bats ${probeSource}/tests/raw-codex-services.bats "
          "> /home/probe/live-services-tests.log 2>&1'"
        )
        machine.copy_from_machine("/home/probe/live-services-tests.log")
      finally:
        machine.succeed("truncate -s 0 /home/probe/.codex/auth.json /home/probe/.config/gh/hosts.yml")
      assert live_result[0] == 0, live_result
    ''}
    result = machine.execute(
      "su -s ${toStorePath bashRoot}/bin/bash probe -c '"
      "env PATH=${pkgs.lib.makeBinPath cliRoots} "
      "${toStorePath pythonRoot}/bin/python3 "
      "${probeSource}/scripts/secret-isolation-probe.py "
      "--output /home/probe/secret-isolation-270'"
    )
    machine.copy_from_machine("/home/probe/secret-isolation-270/report.json")
    machine.copy_from_machine("/home/probe/secret-isolation-270/runtime.log")
    machine.copy_from_machine("/home/probe/secret-isolation-270/evidence")
    assert result[0] == 0, result
    machine.succeed(
      "${toStorePath pythonRoot}/bin/python3 -c "
      "'import json; "
      "assert json.load(open(\"/home/probe/secret-isolation-270/report.json\"))[\"fixture_result\"] == \"passed\"'"
    )
    worktree_result = machine.execute(
      "su -s ${toStorePath bashRoot}/bin/bash probe -c '"
      "env PATH=${pkgs.lib.makeBinPath cliRoots} SECRET_ISOLATION_REAL_RUNTIME=1 "
      "${toStorePath batsRoot}/bin/bats ${probeSource}/tests/secret-isolation-worktree.bats "
      "> /home/probe/worktree-tests.log 2>&1'"
    )
    machine.copy_from_machine("/home/probe/worktree-tests.log")
    assert worktree_result[0] == 0, worktree_result
    raw_result = machine.execute(
      "su -s ${toStorePath bashRoot}/bin/bash probe -c '"
      "env PATH=${pkgs.lib.makeBinPath (cliRoots ++ testTools)} "
      "CODEX_ISOLATION_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt "
      "${toStorePath batsRoot}/bin/bats ${probeSource}/tests/devshell-env.bats ${probeSource}/tests/raw-codex-integration.bats "
      "> /home/probe/raw-tests.log 2>&1'"
    )
    machine.copy_from_machine("/home/probe/raw-tests.log")
    assert raw_result[0] == 0, raw_result
    services_result = machine.execute(
      "su -s ${toStorePath bashRoot}/bin/bash probe -c '"
      "env PATH=${pkgs.lib.makeBinPath (cliRoots ++ testTools)} "
      "CODEX_ISOLATION_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt "
      "${toStorePath batsRoot}/bin/bats ${probeSource}/tests/raw-codex-services.bats ${probeSource}/tests/isolated-github.bats ${probeSource}/tests/secret-isolation-gateway.bats "
      "> /home/probe/services-tests.log 2>&1'"
    )
    machine.copy_from_machine("/home/probe/services-tests.log")
    assert services_result[0] == 0, services_result
  '';
}
