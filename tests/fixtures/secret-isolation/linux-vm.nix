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
  herdrRoot ? null,
  withEnvRoot ? null,
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
  ]
  ++ pkgs.lib.optional (withEnvRoot != null) (toStorePath withEnvRoot)
  ++ pkgs.lib.optional (herdrRoot != null) (toStorePath herdrRoot);
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
        "scripts/herdr-codex-isolation.py"
        ".herdr/herdr-plugin.toml"
        "tests/herdr-codex-isolation.bats"
        "scripts/secret-isolation-gateway.py"
        "private_dot_local/share/codex-isolation/secret-isolation-worktree.py"
        "private_dot_local/share/codex-isolation/secret-isolation-gateway.py"
        "private_dot_local/share/codex-isolation/codex-inner.py"
        "private_dot_local/share/codex-isolation/codex-namespace.py"
        "private_dot_local/share/codex-isolation/github-service.py"
        "private_dot_local/share/codex-isolation/github-client.py"
        "private_dot_local/bin/executable_devshell-env"
        "private_dot_local/share/devshell-env/devshell_environment.py"
        "private_dot_local/bin/executable_codex-worktree"
        "private_dot_local/bin/executable_git-push-topic"
        "private_dot_config/codex/config.toml.tmpl"
        "tests/helpers/raw-codex.bash"
        "tests/helpers/herdr-codex-isolation.py"
        "tests/devshell-env.bats"
        "tests/raw-codex-integration.bats"
        "tests/human-validation.bats"
        "tests/helpers/human-validation.py"
        "tests/fixtures/secret-isolation/human-reviewed.py"
        "tests/fixtures/secret-isolation/human-boundary.py"
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
  name = "secret-isolation-linux-vm-${
    if withEnvRoot != null then
      "274"
    else if herdrRoot != null then
      "273"
    else
      "270"
  }";
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
      # QEMU advertises IPv6 even when its WSL host has no IPv6 uplink.
      # This fixture measures the supported IPv4 uplink; dual-stack is separate.
      networking.enableIPv6 = false;

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
  ''
  + pkgs.lib.optionalString (herdrRoot != null) ''
    herdr_result = machine.execute(
      "su -s ${toStorePath bashRoot}/bin/bash probe -c '"
      "env PATH=${pkgs.lib.makeBinPath (cliRoots ++ testTools)} "
      "CODEX_ISOLATION_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt "
      "${toStorePath pythonRoot}/bin/python3 ${probeSource}/scripts/herdr-codex-isolation.py "
      "--output /home/probe/herdr-273 > /home/probe/herdr-tests.log 2>&1'"
    )
    machine.copy_from_machine("/home/probe/herdr-tests.log")
    machine.copy_from_machine("/home/probe/herdr-273/report.json")
    for name in ("copied", "restart", "delayed", "untrusted-refused", "primary-refused"):
      machine.copy_from_machine("/home/probe/herdr-273/" + name + ".log")
    assert herdr_result[0] == 0, herdr_result
  ''
  + pkgs.lib.optionalString (withEnvRoot != null) ''
    human_result = machine.execute(
      "su -s ${toStorePath bashRoot}/bin/bash probe -c '"
      "env PATH=${pkgs.lib.makeBinPath (cliRoots ++ testTools)} "
      "CODEX_ISOLATION_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt "
      "${toStorePath batsRoot}/bin/bats ${probeSource}/tests/human-validation.bats "
      "> /home/probe/human-tests.log 2>&1'"
    )
    machine.copy_from_machine("/home/probe/human-tests.log")
    assert human_result[0] == 0, human_result
  ''
  + pkgs.lib.optionalString (herdrRoot == null && withEnvRoot == null) ''
    ${pkgs.lib.optionalString realServices ''
      import os
      # Transfer only the two selected tool-login files after the Nix image is
      # built. Keep guest copies in tmpfs, including when the VM is interrupted.
      machine.succeed("test \"$(stat -f -c %T /run)\" = tmpfs; install -d -m 700 -o probe -g users /run/probe-tool-logins /home/probe/.codex /home/probe/.config /home/probe/.config/gh")
      machine.succeed("ln -s /run/probe-tool-logins/auth.json /home/probe/.codex/auth.json; ln -s /run/probe-tool-logins/hosts.yml /home/probe/.config/gh/hosts.yml")
      try:
        machine.copy_from_host(os.environ["CODEX_ISOLATION_VM_CODEX_AUTH"], "/run/probe-tool-logins/auth.json")
        machine.copy_from_host(os.environ["CODEX_ISOLATION_VM_GH_HOSTS"], "/run/probe-tool-logins/hosts.yml")
        machine.succeed("chown probe:users /run/probe-tool-logins/*; chmod 600 /run/probe-tool-logins/*")
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
        machine.succeed("find /run/probe-tool-logins -maxdepth 1 -type f -exec truncate -s 0 {} +")
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
