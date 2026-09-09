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
}:
let
  nixpkgs = builtins.toPath nixpkgsPath;
  pkgs = import nixpkgs { };
  toStorePath = value: builtins.storePath (toString value);
  cliRoots = map toStorePath [
    nixRoot bashRoot coreutilsRoot pythonRoot gitRoot codexRoot ghRoot bwrapRoot
  ];
  probeSource = pkgs.runCommand "secret-isolation-probe-source" { } ''
    install -D -m 0444 \
      ${pkgs.writeText "secret-isolation-probe.py"
        (builtins.readFile "${repoPath}/scripts/secret-isolation-probe.py")} \
      "$out/scripts/secret-isolation-probe.py"
    install -D -m 0444 \
      ${pkgs.writeText "secret-isolation-runtime.py"
        (builtins.readFile "${repoPath}/tests/fixtures/secret-isolation/runtime.py")} \
      "$out/tests/fixtures/secret-isolation/runtime.py"
    ${pkgs.lib.concatMapStringsSep "\n" (name: ''
      install -D -m 0444 ${pkgs.writeText (builtins.baseNameOf name)
        (builtins.readFile "${repoPath}/${name}")} "$out/${name}"
    '') [
      "scripts/secret-isolation-worktree.py"
      "scripts/secret-isolation-gateway.py"
      "private_dot_local/bin/executable_devshell-env"
      "tests/secret-isolation-worktree.bats"
      "tests/fixtures/secret-isolation/worktree-task.py"
    ]}
  '';
in
pkgs.testers.runNixOSTest {
  name = "secret-isolation-linux-vm-270";
  globalTimeout = 15 * 60;
  qemu.forceAccel = true;

  nodes.machine = { ... }: {
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
      diskSize = 8192;
      useNixStoreImage = true;
      mountHostNixStore = false;
      writableStore = true;
      writableStoreUseTmpfs = true;
      restrictNetwork = true;
      additionalPaths = cliRoots ++ [ probeSource (toStorePath batsRoot) ];
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
  '';
}
